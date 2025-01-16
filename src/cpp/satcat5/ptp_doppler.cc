//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_doppler.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/utils.h>
#include <satcat5/wide_integer.h>

using satcat5::io::LimitedRead;
using satcat5::poll::timekeeper;
using satcat5::ptp::ClientMode;
using satcat5::ptp::DopplerSimple;
using satcat5::ptp::DopplerTlv;
using satcat5::ptp::Header;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::Time;
using satcat5::ptp::TlvHeader;
using satcat5::ptp::TLVTYPE_DOPPLER;
using satcat5::util::int128_t;
using satcat5::util::min_u32;

// Enable support for SPTP?
#ifndef SATCAT5_SPTP_ENABLE
#define SATCAT5_SPTP_ENABLE 2
#endif

// Timestamp compensation enabled by default?
#ifndef SATCAT5_DOPPLER_TCOMP
#define SATCAT5_DOPPLER_TCOMP false
#endif

// Set logging verbosity level (0/1/2).
static constexpr unsigned DEBUG_VERBOSE = 1;

// DopplerTLV tags are fixed-length, with a 6-byte payload.
static constexpr TlvHeader TLVHDR_DOPPLER = {TLVTYPE_DOPPLER, 6, 0, 0};

DopplerTlv::DopplerTlv(satcat5::ptp::Client* client)
    : TlvHandler(client)
    , m_predict()
    , m_dstamp(0)
    , m_tref(SATCAT5_CLOCK->now())
    , m_tcomp(SATCAT5_DOPPLER_TCOMP)
{
    // Nothing else to initialize.
}

bool DopplerTlv::tlv_rcvd(const Header& hdr, const TlvHeader& tlv, LimitedRead& rd)
{
    // Ignore everything except DopplerTLV tags.
    if (tlv.type != TLVTYPE_DOPPLER) return false;

    // Read the contents of the DopplerTLV tag.
    // (In many cases, the Doppler field is echoed in the reply.)
    m_dstamp = rd.read_s48();

    // Is this the final message in a two-way handshake?
    bool rcvd_sptp = SATCAT5_SPTP_ENABLE
        && (m_client->get_mode() == ClientMode::SLAVE_SPTP)
        && (hdr.flags & Header::FLAG_SPTP);
    bool rcvd_final = (hdr.type == Header::TYPE_DELAY_RESP)
        || (rcvd_sptp && hdr.type == Header::TYPE_SYNC);

    // Update tracking filter for each complete Doppler measurement.
    if (rcvd_final) {
        u32 elapsed_usec = m_tref.increment_usec();
        elapsed_usec = min_u32(1000000, elapsed_usec);
        m_predict.update(m_dstamp, elapsed_usec);
    }

    // Optional logging
    if (DEBUG_VERBOSE > 1) {
        satcat5::log::Log(satcat5::log::DEBUG, "DopplerTlv::tlv_recv")
            .write("\n  typ").write(hdr.type)       // PTP message type
            .write("\n  raw").write((u64)m_dstamp)  // Raw measurement (hex)
            .write("\n  raw").write10(m_dstamp);    // Raw measurement (dec)
    }

    // Matching tag has been read.
    return true;
}

unsigned DopplerTlv::tlv_send(const Header& hdr, satcat5::io::Writeable* wr)
{
    // Flags from the client state, PTP header, etc.
    bool flag_sptp = SATCAT5_SPTP_ENABLE && (hdr.flags & Header::FLAG_SPTP);

    // Which outgoing messages start or continue a Doppler handshake?
    //  * Normal: SYNC -> DELAY_REQ -> DELAY_RESP
    //  * Peer: PDELAY_REQ -> PDELAY_RESP
    //  * SPTP: DELAY_REQ -> SYNC
    bool send_any = (hdr.type == Header::TYPE_SYNC)
                 || (hdr.type == Header::TYPE_DELAY_REQ)
                 || (hdr.type == Header::TYPE_PDELAY_REQ)
                 || (hdr.type == Header::TYPE_PDELAY_RESP)
                 || (hdr.type == Header::TYPE_DELAY_RESP);
    bool send_first = (hdr.type == Header::TYPE_SYNC && !flag_sptp)
                   || (hdr.type == Header::TYPE_PDELAY_REQ)
                   || (hdr.type == Header::TYPE_DELAY_REQ && flag_sptp);

    // Write header+tag if applicable.
    if (send_any && wr) {
        wr->write_obj(TLVHDR_DOPPLER);              // Tag header
        wr->write_s48(send_first ? 0 : m_dstamp);   // Tag contents
    }
    return send_any ? TLVHDR_DOPPLER.len_total() : 0;
}

// TODO: Verify this model somehow?
void DopplerTlv::tlv_meas(satcat5::ptp::Measurement& meas)
{
    // Calculate round-trip time including all network delays.
    // (Use absolute value because T4 - T1 is negative in SPTP mode.)
    // TODO: Better accuracy if we split CF1, CF2 from T1/T2/T3/T4?
    s64 t = (meas.t4 - meas.t1).abs().delta_subns();  // subns

    // Calculate the current velocity and acceleration.
    s64 v = m_predict.predict(0);               // subns/sec
    s64 a = m_predict.predict(500000) - v;      // 0.5 * subns/sec^2

    // Renormalize T4 to mitigate the effect of motion.
    int128_t tt(t), vv(v), aa(a), s(SUBNS_PER_SEC);
    s64 delta = s64((((aa * tt).div_round(s) + vv) * tt).div_round(s));
    if (m_tcomp) meas.t4 -= Time(delta);

    // Optional logging
    if (DEBUG_VERBOSE > 0) {
        satcat5::log::Log(satcat5::log::DEBUG, "DopplerTlv::tlv_meas")
            .write("\n  time ").write10(t)          // Elapsed time
            .write("\n  vraw ").write10(m_dstamp)   // Raw velocity
            .write("\n  vfilt").write10(v)          // Filtered velocity
            .write("\n  accel").write10(a)          // Filtered acceleration
            .write("\n  tcomp").write10(delta);     // Compensation amount
    }
}

static constexpr satcat5::ptp::CoeffPI DEFAULT_TIME_CONSTANT(3.0);

DopplerSimple::DopplerSimple(satcat5::ptp::Client* client)
    : DopplerTlv(client)
    , m_ampl()
    , m_ctrl(DEFAULT_TIME_CONSTANT)
{
    add_filter(&m_ampl);
    add_filter(&m_ctrl);
}
