//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ntp_header.h>

using satcat5::ntp::Header;

void Header::log_to(satcat5::log::LogBuffer& wr) const {
    wr.wr_str("\r\n  LI:      ");       wr.wr_dec((lvm & LI_MASK) >> 6);
    wr.wr_str("\r\n  VN:      ");       wr.wr_dec((lvm & VN_MASK) >> 3);
    wr.wr_str("\r\n  Mode:    ");       wr.wr_dec(lvm & MODE_MASK);
    wr.wr_str("\r\n  Stratum: ");       wr.wr_dec((u32)stratum);
    wr.wr_str("\r\n  Poll:    ");       wr.wr_dec((s32)poll);
    wr.wr_str("\r\n  Prec:    ");       wr.wr_dec((s32)precision);
    wr.wr_str("\r\n  RtDelay: 0x");     wr.wr_h32(rootdelay);
    wr.wr_str("\r\n  RtDisp:  0x");     wr.wr_h32(rootdisp);
    wr.wr_str("\r\n  RefID:   0x");     wr.wr_h32(refid);
    wr.wr_str("\r\n  RefTime: 0x");     wr.wr_h64(ref);
    wr.wr_str("\r\n  OrgTime: 0x");     wr.wr_h64(org);
    wr.wr_str("\r\n  RecTime: 0x");     wr.wr_h64(rec);
    wr.wr_str("\r\n  XmtTime: 0x");     wr.wr_h64(xmt);
}

bool Header::read_from(satcat5::io::Readable* rd) {
    if (rd->get_read_ready() >= HEADER_LEN) {
        lvm             = rd->read_u8();
        stratum         = rd->read_u8();
        poll            = rd->read_s8();
        precision       = rd->read_s8();
        rootdelay       = rd->read_u32();
        rootdisp        = rd->read_u32();
        refid           = rd->read_u32();
        ref             = rd->read_u64();
        org             = rd->read_u64();
        rec             = rd->read_u64();
        xmt             = rd->read_u64();
        return true;
    } else {
        return false;
    }
}

void Header::write_to(satcat5::io::Writeable* wr) const {
    wr->write_u8(lvm);
    wr->write_u8(stratum);
    wr->write_s8(poll);
    wr->write_s8(precision);
    wr->write_u32(rootdelay);
    wr->write_u32(rootdisp);
    wr->write_u32(refid);
    wr->write_u64(ref);
    wr->write_u64(org);
    wr->write_u64(rec);
    wr->write_u64(xmt);
}
