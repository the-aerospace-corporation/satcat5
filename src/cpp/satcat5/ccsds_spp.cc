//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ccsds_spp.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::ccsds_spp::Address;
using satcat5::ccsds_spp::BytesToSpp;
using satcat5::ccsds_spp::Dispatch;
using satcat5::ccsds_spp::Header;
using satcat5::ccsds_spp::Packetizer;
using satcat5::ccsds_spp::Protocol;
using satcat5::ccsds_spp::SppToBytes;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::log::DEBUG;
using satcat5::log::Log;
using satcat5::log::WARNING;
using satcat5::net::Type;
using satcat5::util::min_unsigned;

// Set debugging verbosity (0/1/2)
#define DEBUG_VERBOSE 0

void Header::set(bool cmd, u16 apid, u16 seq) {
    value = VERSION_1 | SEQF_UNSEG
          | (cmd ? TYPE_CMD : TYPE_TLM)
          | pack_apid(apid) | pack_seqc(seq);
}

Header& Header::operator++() {
    // Increment the sequence-count field, with wraparound.
    u32 old_hdr = u32(value & ~SEQC_MASK);
    u16 old_seq = u16(value &  SEQC_MASK);
    value = old_hdr | pack_seqc(old_seq + 1);
    return *this;
}

Packetizer::Packetizer(u8* buff, unsigned rxbytes, unsigned rxpkt, Readable* src)
    : ReadableRedirect(&m_buff)
    , m_copy(src, this)
    , m_buff(buff, rxbytes, rxpkt)
    , m_rem(0)
    , m_timeout(1000)
    , m_wridx(0)
    , m_sreg(0)
{
    // Nothing else to initialize.
}

unsigned Packetizer::get_write_space() const {
    return m_buff.get_write_space();
}

void Packetizer::flush() {
    auto src = m_copy.src();
    m_buff.write_abort();           // Flush partial output
    if (src) src->read_finalize();  // Flush partial input
    m_rem = 0;                      // Reset packet state
    m_wridx = 0;                    // Reset header state
}

void Packetizer::reset() {
    m_buff.clear();                 // Discard buffer contents
    flush();                        // Reset parser state
}

void Packetizer::timer_event() {
    Log(WARNING, "CCSDS-SDS packetizer timeout.");
    flush();                        // Discard partials and reset state
}

void Packetizer::write_next(u8 data) {
    // Always copy new data to the output buffer.
    m_buff.write_u8(data);

    // Shift-register holds the two most recent bytes.
    m_sreg = 256 * m_sreg + data;

    // Update packet-parsing state...
    if (m_rem) {
        // Countdown to end of SPP packet.
        bool ok = (--m_rem) || m_buff.write_finalize();
        if (DEBUG_VERBOSE > 0 && !ok)
            Log(DEBUG, "ccsds_spp::Packetizer overflow");
    } else if (++m_wridx == 6) {
        // End of 6-byte SPP primary header.
        m_rem = 1 + unsigned(m_sreg);
        m_wridx = 0;
    }

    // Refresh the watchdog timer.
    if (m_rem || m_wridx) timer_once(m_timeout);
    else timer_stop();
}

satcat5::net::Dispatch* Address::iface() const {
    return m_iface;
}

Writeable* Address::open_write(unsigned len) {
    Writeable* wr = m_iface->open_write(m_dst, len);
    if (wr) ++m_dst;    // Increment sequence count?
    return wr;          // Return Writeable object.
}

void Address::close() {
    m_dst.value = 0;
}

bool Address::ready() const {
    return !!m_dst.value;
}

bool Address::matches_reply_address() const {
    return m_dst.apid() == m_iface->rcvd_hdr().apid();
}

void Address::save_reply_address() {
    Header tmp = m_iface->rcvd_hdr();
    m_dst.set(tmp.type_tlm(), tmp.apid(), tmp.seqc());
}

Dispatch::Dispatch(Readable* src, Writeable* dst)
    : m_src(src)
    , m_dst(dst)
    , m_rcvd_hdr{0}
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch() {
    if (m_src) m_src->set_callback(0);
}
#endif

Writeable* Dispatch::open_reply(const Type& type, unsigned len) {
    // Use the same APID, but invert cmd/tlm type.
    // Echo the sequence counter. (Not ideal, but better than zero.)
    Header hdr;
    hdr.set(!m_rcvd_hdr.type_cmd(), m_rcvd_hdr.apid(), m_rcvd_hdr.seqc());
    return open_write(hdr, len);
}

Writeable* Dispatch::open_write(const Header& hdr, unsigned len) {
    // Sanity check if user provided a null destination.
    if (!m_dst) return nullptr;
    if (DEBUG_VERBOSE > 1)
        Log(DEBUG, "ccsds_spp::Transmit").write(hdr.apid()).write10(u32(len));
    // Flush leftovers from incomplete previous transmissions.
    m_dst->write_abort();
    // Sanity check: Is user trying to send an empty packet?
    if (len < 1) return 0;
    // Sanity check: Can we fit a complete and valid packet?
    if (m_dst->get_write_space() < len + 6) return 0;
    // If so, write the header and let user write contents.
    m_dst->write_u32(hdr.value);
    m_dst->write_u16(len - 1);
    return m_dst;
}

void Dispatch::data_rcvd(Readable* src) {
    // Attempt to read the incoming SPP header.
    u32 len = 0; bool ok = false;
    if (src->get_read_ready() >= 6) {
        m_rcvd_hdr.value = src->read_u32();
        len = 1 + u32(src->read_u16());
        ok = (src->get_read_ready() >= len)
            && (m_rcvd_hdr.apid() != APID_IDLE);
    }

    // Optionally log each received packet.
    if (DEBUG_VERBOSE > 1 && ok)
        Log(DEBUG, "ccsds_spp::Received").write(m_rcvd_hdr.apid()).write10(u32(len));

    // Attempt delivery, filtered by APID.
    Type typ(m_rcvd_hdr.apid());
    if (ok) deliver(typ, src, len);

    // Cleanup any trailing bytes.
    src->read_finalize();
}

void Dispatch::data_unlink(Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

Protocol::Protocol(Dispatch* iface, u16 apid)
    : satcat5::net::Protocol(Type(apid))
    , m_iface(iface)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
Protocol::~Protocol() {
    m_iface->remove(this);
}
#endif

BytesToSpp::BytesToSpp(Readable* src, Dispatch* dst, u16 apid, unsigned max_chunk)
    : m_dst(dst)
    , m_strm(src, &m_dst, max_chunk)
{
    m_dst.connect(false, apid);
}

SppToBytes::SppToBytes(Dispatch* src, Writeable* dst, u16 apid)
    : Protocol(src, apid)
    , m_dst(dst)
{
    // Nothing else to initialize.
}

void SppToBytes::frame_rcvd(satcat5::io::LimitedRead& src) {
    // Copy all data, ignoring header fields.
    src.copy_and_finalize(m_dst, satcat5::io::CopyMode::STREAM);
}
