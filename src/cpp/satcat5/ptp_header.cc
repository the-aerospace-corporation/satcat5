//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ptp_header.h>

using satcat5::ptp::PortId;
using satcat5::ptp::Header;
using satcat5::ptp::ClockInfo;

bool PortId::read_from(satcat5::io::Readable* rd)
{
    if (rd->get_read_ready() >= 10) {
        clock_id = rd->read_u64();
        port_num = rd->read_u16();
        return true;
    } else {
        return false;
    }
}

void PortId::write_to(satcat5::io::Writeable* wr) const
{
    wr->write_u64(clock_id);
    wr->write_u16(port_num);
}

bool Header::read_from(satcat5::io::Readable* rd)
{
    if (rd->get_read_ready() >= HEADER_LEN) {
        u8 sdo_type     = rd->read_u8();
        version         = rd->read_u8() & 0x0F; // Drop minor version
        length          = rd->read_u16();
        domain          = rd->read_u8();
        u8 minor_sdo    = rd->read_u8();
        flags           = rd->read_u16();
        correction      = rd->read_u64();
        subtype         = rd->read_u32();
        rd->read_obj(src_port);
        seq_id          = rd->read_u16();
        control         = rd->read_u8();
        log_interval    = rd->read_u8();
        type = sdo_type & 0x0F; // Lower nibble
        sdo_id = ((sdo_type & 0xF0) << 8) | minor_sdo; // Combine major/minor
        return true;
    } else {
        return false;
    }
}

void Header::write_to(satcat5::io::Writeable* wr) const
{
    wr->write_u8(((u8) (sdo_id >> 4) & 0xF0) | (type & 0x0F));
    wr->write_u8(version);
    wr->write_u16(length);
    wr->write_u8(domain);
    wr->write_u8((u8) sdo_id); // Truncate
    wr->write_u16(flags);
    wr->write_u64(correction);
    wr->write_u32(subtype);
    wr->write_obj(src_port);
    wr->write_u16(seq_id);
    wr->write_u8(control);
    wr->write_u8(log_interval);
}

bool ClockInfo::read_from(satcat5::io::Readable* rd)
{
    if (rd->get_read_ready() >= 17) {
        grandmasterPriority1    = rd->read_u8();
        grandmasterClass        = rd->read_u8();
        grandmasterAccuracy     = rd->read_u8();
        grandmasterVariance     = rd->read_u16();
        grandmasterPriority2    = rd->read_u8();
        grandmasterIdentity     = rd->read_u64();
        stepsRemoved            = rd->read_u16();
        timeSource              = rd->read_u8();
        return true;
    } else {
        return false;
    }
}

void ClockInfo::write_to(satcat5::io::Writeable* wr) const
{
    wr->write_u8(grandmasterPriority1);
    wr->write_u8(grandmasterClass);
    wr->write_u8(grandmasterAccuracy);
    wr->write_u16(grandmasterVariance);
    wr->write_u8(grandmasterPriority2);
    wr->write_u64(grandmasterIdentity);
    wr->write_u16(stepsRemoved);
    wr->write_u8(timeSource);
}
