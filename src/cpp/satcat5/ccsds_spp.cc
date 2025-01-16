//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ccsds_spp.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::ccsds_spp::Header;
using satcat5::ccsds_spp::Address;
using satcat5::ccsds_spp::Dispatch;
using satcat5::ccsds_spp::Packetizer;
using satcat5::ccsds_spp::Protocol;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::net::Type;
using satcat5::util::min_unsigned;

void Header::set(bool cmd, u16 apid, u16 seq) {
    // TODO: Should the default be SEQF_FIRST or SEQF_LAST?
    value = VERSION_1 | SEQF_FIRST
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

Packetizer::Packetizer(Readable* src, u8* buff, unsigned rxbytes, unsigned rxpkt)
    : ReadableRedirect(&m_buff)
    , m_src(src)
    , m_buff(buff, rxbytes, rxpkt)
    , m_rem(0)
    , m_timeout(1000)
{
    m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Packetizer::~Packetizer() {
    if (m_src) m_src->set_callback(0);
}
#endif

void Packetizer::data_rcvd(Readable* src) {
    // At the start of each packet, attempt to read the header.
    if (!m_rem) {
        // Start watchdog timer only on the first attempt.
        // (Source will call data_rcvd on every service loop.)
        if (!timer_remaining()) timer_once(m_timeout);
        // Can we read the entire header?
        if (src->get_read_ready() < 6) return;
        // Read header contents.
        u32 hdr = src->read_u32();  // Read header
        u16 len = src->read_u16();
        m_rem = 1 + unsigned(len);  // Note length
        m_buff.write_u32(hdr);      // Forward header
        m_buff.write_u16(len);
    }

    // Once we've read the header, forward packet contents verbatim.
    if (m_rem) {
        // Copy as much data as we can...
        unsigned max_rd = min_unsigned(m_rem, src->get_read_ready());
        m_rem -= LimitedRead(m_src, max_rd).copy_to(&m_buff);
        // If there's still data pending, restart the watchdog.
        if (m_rem) {timer_once(m_timeout); return;}
        // Otherwise, stop watchdog and mark end-of-frame.
        timer_stop();
        m_buff.write_finalize();
    }
}

void Packetizer::data_unlink(Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

void Packetizer::timer_event() {
    satcat5::log::Log(satcat5::log::WARNING, "CCSDS-SDS packetizer timeout.");
    m_buff.write_abort();       // Flush partial output
    m_src->read_finalize();     // Flush partial input
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
    m_src->set_callback(this);
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
    // Read the incoming SPP header.
    m_rcvd_hdr.value = src->read_u32();
    unsigned len = 1 + unsigned(src->read_u16());
    bool ok = (src->get_read_ready() >= len)
        && (m_rcvd_hdr.apid() != APID_IDLE);

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
