//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cmath>
#include <cstdio>
#include <ctime>
#include <map>
#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::poll::timekeeper;
using satcat5::test::CborParser;
using satcat5::test::LogProtocol;
using satcat5::test::MockConfigBusMmap;
using satcat5::test::MockInterrupt;
using satcat5::test::RandomSource;
using satcat5::test::Statistics;
using satcat5::test::TimerSimulation;
using satcat5::util::TimeVal;

// Global PRNG using the Catch2 framework.
static Catch::SimplePcg32 global_prng = Catch::rng();

bool satcat5::test::pre_test_reset() {
    // Set a consistent seed for unit-testing purposes.
    global_prng.seed(0xED743CC4u);
    return true;
}

u8 satcat5::test::rand_u8() {
    return u8(global_prng());
}

u32 satcat5::test::rand_u32() {
    return global_prng();
}

u64 satcat5::test::rand_u64() {
    u64 msb = rand_u32(), lsb = rand_u32();
    return (msb << 32) | lsb;
}

std::string satcat5::test::sim_filename(const char* pre, const char* ext) {
    // Persistent counter lookup for each unique prefix.
    static std::map<std::string, unsigned> counts;
    if (counts.find(pre) == counts.end()) counts[pre] = 0;
    unsigned idx = counts[pre]++;
    // Construct the filename.
    char buff[256];
    snprintf(buff, sizeof(buff), "simulations/%s_%03u.%s", pre, idx, ext);
    return std::string(buff);
}

bool satcat5::test::write(Writeable* dst, unsigned nbytes, const u8* data) {
    dst->write_bytes(nbytes, data);
    return dst->write_finalize();
}

bool satcat5::test::write(Writeable* dst, const std::string& dat) {
    dst->write_bytes(dat.length(), dat.c_str());
    return dst->write_finalize();
}

bool satcat5::test::read(Readable* src, unsigned nbytes, const u8* data) {
    // Sanity check: Null source only matches a null string.
    if (!src && nbytes) {
        log::Log(log::ERROR, "Unexpected null source.");
        return false;
    } else if (!src) {
        return true;
    }

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

bool satcat5::test::read(Readable* src, const std::string& ref) {
    return satcat5::test::read(src, ref.size(), (const u8*)ref.c_str());
}

void satcat5::test::write_random_bytes(Writeable* dst, unsigned nbytes) {
    for (unsigned a = 0 ; a < nbytes ; ++a)
        dst->write_u8(rand_u8());
}

bool satcat5::test::write_random_final(Writeable* dst, unsigned nbytes) {
    write_random_bytes(dst, nbytes);
    return dst->write_finalize();
}

bool satcat5::test::read_equal(Readable* src1, Readable* src2) {
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

CborParser::CborParser(Readable* src, bool verbose)
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

LogProtocol::LogProtocol(
        satcat5::eth::Dispatch* dispatch,
        const satcat5::eth::MacType& ethertype)
    : satcat5::eth::Protocol(dispatch, ethertype)
{
    // Nothing else to initialize.
}

void LogProtocol::frame_rcvd(satcat5::io::LimitedRead& src) {
    satcat5::log::Log(satcat5::log::INFO, "Frame received")
        .write(m_etype.value).write(", Len")
        .write10((u16)src.get_read_ready());
}

MockConfigBusMmap::MockConfigBusMmap()
    : satcat5::cfg::ConfigBusMmap(m_regs, satcat5::irq::IRQ_NONE)
{
    clear_all();
}

void MockConfigBusMmap::clear_all(u32 val) {
    for (unsigned a = 0 ; a < cfg::MAX_DEVICES ; ++a)
        clear_dev(a, val);
}

void MockConfigBusMmap::clear_dev(unsigned devaddr, u32 val) {
    u32* dev = m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE;
    for (unsigned a = 0 ; a < cfg::REGS_PER_DEVICE ; ++a)
        dev[a] = val;
}

void MockConfigBusMmap::irq_event() {
    satcat5::cfg::ConfigBusMmap::irq_event();
}

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg)
    : satcat5::cfg::Interrupt(cfg)
    , m_cfg(cfg)
    , m_regaddr(0)
{
    // Nothing else to initialize.
}

static constexpr u32 MOCK_IRQ_ENABLE    = (1u << 0);
static constexpr u32 MOCK_IRQ_REQUEST   = (1u << 1);

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg, unsigned regaddr)
    : satcat5::cfg::Interrupt(cfg, 0, regaddr)
    , m_cfg(cfg)
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
    : HeapAllocator(len)
    , ArrayRead(m_buffptr, len)
    , m_len(len)
{
    for (unsigned a = 0 ; a < len ; ++a)
        m_buffptr[a] = (u8)rand_u32();
}

Readable* RandomSource::read() {
    read_reset(m_len);
    return this;
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

void Statistics::add(double x) {
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

TimerSimulation::TimerSimulation()
    : TimeRef(1000000), m_tref(0), m_tnow(0)
{
    // Always use this simulation clock as the reference.
    timekeeper.set_clock(this);
}

TimerSimulation::~TimerSimulation() {
    // Cleanup links established in the constructor.
    timekeeper.set_clock(0);
}

u32 TimerSimulation::raw() {
    // Each call to raw() increments a few microseconds, to avoid
    // stalling functions like busywait_usec().
    m_tnow += 5;
    // If a full millisecond has elapsed, notify the timekeeper.
    if (m_tnow - m_tref >= 1000) {
        m_tref = m_tnow;
        timekeeper.request_poll();
    }
    return m_tnow;
}

void TimerSimulation::sim_step() {
    // Confirm this clock is still the timekeeping reference.
    if (timekeeper.get_clock() != this)
        timekeeper.set_clock(this);
    // Step time forward to the next millisecond boundary.
    m_tnow += 1000 - (m_tnow % 1000);
    m_tref = m_tnow;
    // Notify timekeeper that at least one millisecond has elapsed.
    timekeeper.request_poll();
}

void TimerSimulation::sim_wait(unsigned dly_msec) {
    // Sanity check before we start...
    if (dly_msec > 10000000)
        log::Log(log::WARNING, "Excessive delay request").write10(dly_msec);
    for (unsigned a = 0 ; a < dly_msec ; ++a) {
        sim_step();
        satcat5::poll::service_all();
    }
}
