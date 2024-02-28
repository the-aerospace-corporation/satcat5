//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Generic numeric "Type" for use with net::Protocol
//
// Every instance of net::Protocol must define a multipurpose "Type" to
// inform the dispatch layer which packets it accepts.  The Type can hold
// any numeric value up to 32 bits.  It may be an IP-address, a port number,
// or any other numeric protocol or endpoint identifier.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        // Each Protocol object is required to contain a Type that designates
        // the type or identity of streams it can accept, or the corresponding
        // field-values for outgoing frames.
        //
        // The formatting depends on the associated Dispatch, but is usually
        // one-to-one with EtherType, UDP port #, etc. for that network layer.
        // The size is chosen to fit any of the above without duress.
        //
        // Note: Dispatch implementations SHOULD provide public accessors
        //       for creating Type objects from EtherType, Port#, etc.
        struct Type {
        public:
            explicit constexpr Type(u8 val)   : m_value(val) {}
            explicit constexpr Type(u16 val)  : m_value(val) {}
            explicit constexpr Type(u32 val)  : m_value(val) {}
            explicit constexpr Type(u16 val1, u16 val2)
                : m_value(65536ul * val1 + val2) {}

            inline u8  as_u8()  const {return (u8) m_value;}
            inline u16 as_u16() const {return (u16)m_value;}
            inline u32 as_u32() const {return (u32)m_value;}

            inline void as_u8(u8& a) const {a = as_u8();}
            inline void as_u16(u16& a) const {a = as_u16();}
            inline void as_u32(u32& a) const {a = as_u32();}
            inline void as_pair(u16& a, u16& b) const
                {a = (u16)(m_value >> 16); b = (u16)(m_value & 0xFFFF);}

            inline bool bound() const {return (m_value != 0);}

        private:
            friend satcat5::net::Dispatch;
            u32 m_value;
        };

        // Use the TYPE_NONE placeholder when no filtering is required.
        constexpr satcat5::net::Type TYPE_NONE = Type((u32)0);
    }
}
