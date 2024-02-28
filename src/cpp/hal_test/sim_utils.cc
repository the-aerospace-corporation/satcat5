//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cmath>
#include <cstdio>
#include <ctime>
#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::test::CborParser;
using satcat5::test::ConstantTimer;
using satcat5::test::LogProtocol;
using satcat5::test::MockConfigBusMmap;
using satcat5::test::MockInterrupt;
using satcat5::test::RandomSource;
using satcat5::test::Statistics;

bool satcat5::test::write(
    satcat5::io::Writeable* dst,
    unsigned nbytes, const u8* data)
{
    dst->write_bytes(nbytes, data);
    return dst->write_finalize();
}

bool satcat5::test::read(
    satcat5::io::Readable* src,
    unsigned nbytes, const u8* data)
{
    // Even if the lengths don't match, compare as much as we can.
    unsigned rcvd = src->get_read_ready(), match = 0;
    for (unsigned a = 0 ; a < nbytes && src->get_read_ready() ; ++a) {
        u8 next = src->read_u8();
        if (next == data[a]) {
            ++match;
        } else {
            log::Log(log::ERROR, "String mismatch @ index")
                .write10(a).write(next).write(data[a]);
        }
    }

    // End-of-frame cleanup.
    src->read_finalize();

    // Check for leftover bytes in either direction.
    if (rcvd > nbytes) {
        log::Log(log::ERROR, "Unexpected trailing bytes").write10(rcvd - nbytes);
        return false;
    } else if (rcvd < nbytes) {
        log::Log(log::ERROR, "Missing expected bytes").write10(nbytes - rcvd);
        return false;
    } else {
        return (match == nbytes);
    }
}

bool satcat5::test::read(satcat5::io::Readable* src, const std::string& ref)
{
    return satcat5::test::read(src, ref.size(), (const u8*)ref.c_str());
}

bool satcat5::test::write_random(satcat5::io::Writeable* dst, unsigned nbytes)
{
    auto rng = Catch::rng();
    for (unsigned a = 0 ; a < nbytes ; ++a)
        dst->write_u8((u8)rng());
    return dst->write_finalize();
}

bool satcat5::test::read_equal(
    satcat5::io::Readable* src1,
    satcat5::io::Readable* src2)
{
    // Read from both sources until the end.
    unsigned diff = 0;
    for (unsigned a = 0 ; src1->get_read_ready() && src2->get_read_ready() ; ++a) {
        u8 x = src1->read_u8(), y = src2->read_u8();
        if (x != y) {
            ++diff;
            log::Log(log::ERROR, "Stream mismatch @ index")
                .write10(a).write(x).write(y);
        }
    }

    // Any leftover bytes in either sources?
    unsigned trail = src1->get_read_ready() + src2->get_read_ready();
    if (trail > 0) {
        log::Log(log::ERROR, "Unexpected trailing bytes").write10(trail);
    }

    // Cleanup before returning the result.
    src1->read_finalize();
    src2->read_finalize();
    return (diff == 0) && (trail == 0);
}

CborParser::CborParser(satcat5::io::Readable* src, bool verbose)
    : m_len(src->get_read_ready())
{
    REQUIRE(m_len > 0);
    REQUIRE(m_len <= sizeof(m_dat));
    src->read_bytes(m_len, m_dat);
    src->read_finalize();
    if (verbose) {
        log::Log(log::DEBUG, "Raw CBOR").write(m_dat, m_len);
    }
}

#if SATCAT5_CBOR_ENABLE

// A null item for indicating decoder errors.
static const QCBORItem ITEM_ERROR = {
    QCBOR_TYPE_NONE,    // Type (value)
    QCBOR_TYPE_NONE,    // Type (label)
    0, 0, 0, 0,         // Metadata
    {.int64=0},         // Value
    {.int64=0},         // Label
    0,                  // Tags
};

QCBORItem CborParser::get(u32 key_req) const {
    // Open a QCBOR parser object.
    QCBORDecodeContext cbor;
    QCBORDecode_Init(&cbor, {m_dat, m_len}, QCBOR_DECODE_MODE_NORMAL);

    // First item should be the top-level dictionary.
    QCBORItem item;
    int errcode = QCBORDecode_GetNext(&cbor, &item);
    if (errcode || item.uDataType != QCBOR_TYPE_MAP) return ITEM_ERROR;

    // Read key/value pairs until we find the desired key.
    // Or, if no match is found, return ITEM_ERROR.
    // (Iterating over the entire dictionary each time is inefficient
    //  but simple, and we don't need high performance for unit tests.)
    u32 key_rcvd = 0;
    while (1) {
        errcode = QCBORDecode_GetNext(&cbor, &item);    // Read key + value
        if (errcode) return ITEM_ERROR;
        if (item.uNestingLevel > 1) continue;
        if (item.uLabelType == QCBOR_TYPE_INT64) {
            errcode = QCBOR_Int64ToUInt32(item.label.int64, &key_rcvd);
            if (errcode) return ITEM_ERROR;
            if (key_req == key_rcvd) return item;       // Key match?
        }
    }
}

QCBORItem CborParser::get(const char* key_req) const {
    // Convert key to a UsefulBuf object.
    UsefulBufC key_buf = UsefulBuf_FromSZ(key_req);

    // Open a QCBOR parser object.
    QCBORDecodeContext cbor;
    QCBORDecode_Init(&cbor, {m_dat, m_len}, QCBOR_DECODE_MODE_NORMAL);

    // First item should be the top-level dictionary.
    QCBORItem item;
    int errcode = QCBORDecode_GetNext(&cbor, &item);
    if (errcode || item.uDataType != QCBOR_TYPE_MAP) return ITEM_ERROR;

    // Read key/value pairs until we find the desired key.
    // Or, if no match is found, return ITEM_ERROR.
    // (Iterating over the entire dictionary each time is inefficient
    //  but simple, and we don't need high performance for unit tests.)
    while (1) {
        errcode = QCBORDecode_GetNext(&cbor, &item);    // Read key + value
        if (errcode) return ITEM_ERROR;
        if (item.uNestingLevel > 1) continue;
        if (item.uLabelType == QCBOR_TYPE_BYTE_STRING ||
            item.uLabelType == QCBOR_TYPE_TEXT_STRING) {
            int diff = UsefulBuf_Compare(key_buf, item.label.string);
            if (diff == 0) return item;                 // Key match?
        }
    }
}

#endif // SATCAT5_CBOR_ENABLE

ConstantTimer::ConstantTimer(u32 val)
    : satcat5::util::GenericTimer(16)  // 16 ticks = 1 microsecond
    , m_now(val)
{
    // Nothing else to initialize.
}

LogProtocol::LogProtocol(
        satcat5::eth::Dispatch* dispatch,
        const satcat5::eth::MacType& ethertype)
    : satcat5::eth::Protocol(dispatch, ethertype)
{
    // Nothing else to initialize.
}

void LogProtocol::frame_rcvd(satcat5::io::LimitedRead& src)
{
    satcat5::log::Log(satcat5::log::INFO, "Frame received")
        .write(m_etype.value).write(", Len")
        .write10((u16)src.get_read_ready());
}

MockConfigBusMmap::MockConfigBusMmap()
    : satcat5::cfg::ConfigBusMmap(m_regs, satcat5::irq::IRQ_NONE)
{
    clear_all();
}

void MockConfigBusMmap::clear_all(u32 val)
{
    for (unsigned a = 0 ; a < cfg::MAX_DEVICES ; ++a)
        clear_dev(a, val);
}

void MockConfigBusMmap::clear_dev(unsigned devaddr, u32 val)
{
    u32* dev = m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE;
    for (unsigned a = 0 ; a < cfg::REGS_PER_DEVICE ; ++a)
        dev[a] = val;
}

void MockConfigBusMmap::irq_event()
{
    satcat5::cfg::ConfigBusMmap::irq_event();
}

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg)
    : satcat5::cfg::Interrupt(cfg)
    , m_cfg(cfg)
    , m_count(0)
    , m_regaddr(0)
{
    // Nothing else to initialize.
}

static constexpr u32 MOCK_IRQ_ENABLE    = (1u << 0);
static constexpr u32 MOCK_IRQ_REQUEST   = (1u << 1);

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg, unsigned regaddr)
    : satcat5::cfg::Interrupt(cfg, 0, regaddr)
    , m_cfg(cfg)
    , m_count(0)
    , m_regaddr(regaddr)
{
    // Nothing else to initialize.
}

void MockInterrupt::fire() {
    u32 rdval;
    if (m_regaddr) {
        // Register mode -> Always set request bit, fire only if enabled.
        m_cfg->read(m_regaddr, rdval);
        m_cfg->write(m_regaddr, rdval | MOCK_IRQ_REQUEST);
        if (rdval & MOCK_IRQ_ENABLE) m_cfg->irq_poll();
    } else {
        // No-register mode -> Always fire as if enabled.
        m_cfg->irq_poll();
    }
}

RandomSource::RandomSource(unsigned len)
    : satcat5::io::ReadableRedirect(&m_read)
    , m_len(len)
    , m_buff(new u8[len])
    , m_read(m_buff, len)
{
    auto rng = Catch::rng();
    for (unsigned a = 0 ; a < len ; ++a)
        m_buff[a] = (u8)rng();
}

RandomSource::~RandomSource()
{
    delete[] m_buff;
}

satcat5::io::Readable* RandomSource::read()
{
    m_read.read_reset(m_len);
    return &m_read;
}

Statistics::Statistics()
    : m_count(0)
    , m_sum(0.0)
    , m_sumsq(0.0)
    , m_min(0.0)
    , m_max(0.0)
{
    // Nothing else to initialize.
}

void Statistics::add(double x)
{
    if ((m_count == 0) || (x < m_min)) m_min = x;
    if ((m_count == 0) || (x > m_max)) m_max = x;
    ++m_count;
    m_sum += x;
    m_sumsq += x*x;
}

double Statistics::mean() const
    { return m_sum / m_count; }
double Statistics::msq() const
    { return m_sumsq / m_count; }
double Statistics::rms() const
    { return sqrt(msq()); }
double Statistics::std() const
    { return sqrt(var()); }
double Statistics::var() const
    { return msq() - mean()*mean(); }
double Statistics::min() const
    { return m_min; }
double Statistics::max() const
    { return m_max; }

void satcat5::test::TimerAlways::sim_wait(unsigned dly_msec)
{
    // Without a reference (timekeeper::set_clock), each call
    // to service_all() represents one elapsed millisecond.
    satcat5::poll::timekeeper.set_clock(0);
    for (unsigned a = 0 ; a < dly_msec ; ++a)
        satcat5::poll::service_all();
}

