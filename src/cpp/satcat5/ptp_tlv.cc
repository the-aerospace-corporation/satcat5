//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ptp_client.h>
#include <satcat5/ptp_tlv.h>

using satcat5::ptp::Client;
using satcat5::ptp::TlvHandler;
using satcat5::ptp::TlvHeader;

bool TlvHeader::match(const TlvHeader& other) const
{
    return (type == other.type)
        && (org_id == other.org_id)
        && (org_sub == other.org_sub);
}

bool TlvHeader::propagate() const
{
    // See IEEE 1588-2019, Section 14.2.2, Table 52.
    if (type < 0x0008) return false;    // 0x0000 - 0x0007
    if (type < 0x000A) return true;     // 0x0008 - 0x0009
    if (type < 0x4000) return false;    // 0x000A - 0x3FFF
    if (type < 0x8000) return true;     // 0x4000 - 0x7FFF
    return false;                       // 0x8000 - 0xFFFF
}

void TlvHeader::write_to(satcat5::io::Writeable* wr) const
{
    wr->write_u16(type);
    if (org_id || org_sub) {
        wr->write_u16(length + 6);
        wr->write_u24(org_id);
        wr->write_u24(org_sub);
    } else {
        wr->write_u16(length);
    }
}

bool TlvHeader::read_from(satcat5::io::Readable* rd)
{
    // Reset all fields.
    *this = TLV_HEADER_NONE;
    // Read and sanity-check the basic header.
    if (rd->get_read_ready() < 4) return false;
    type    = rd->read_u16();
    length  = rd->read_u16();
    if (rd->get_read_ready() < length) return false;
    // Is this tlvType a valid organization extension?
    bool type_org =
        type == TLVTYPE_ORG_EXT ||
        type == TLVTYPE_ORG_EXT_P ||
        type == TLVTYPE_ORG_EXT_NP;
    if (type_org && length < 6) return false;
    // Read the organization sub-header, if applicable.
    if (type_org) {
        org_id  = rd->read_u24();
        org_sub = rd->read_u24();
        length -= 6;
    }
    return true;
}

TlvHandler::TlvHandler(satcat5::ptp::Client* client)
    : m_client(client)
    , m_next(0)
{
    if (m_client) m_client->m_tlv_list.add(this);
}

TlvHandler::~TlvHandler()
{
    if (m_client) m_client->m_tlv_list.remove(this);
}

bool TlvHandler::tlv_rcvd(
    const satcat5::ptp::Header& hdr,
    const satcat5::ptp::TlvHeader& tlv,
    satcat5::io::LimitedRead& rd)
{
    // Default handler does nothing. (No tags to read.)
    return false;
}

unsigned TlvHandler::tlv_send(
    const satcat5::ptp::Header& hdr,
    satcat5::io::Writeable* wr)
{
    // Default handler does nothing. (No tags to write.)
    return 0;
}

void TlvHandler::tlv_meas(satcat5::ptp::Measurement& meas)
{
    // Default handler does nothing. (No need to adjust timestamps.)
}
