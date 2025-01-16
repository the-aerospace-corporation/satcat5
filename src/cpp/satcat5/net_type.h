//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Generic numeric "Type" for use with net::Protocol
//!

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        //! Multipurpose filter for matching fields in network packets.
        //! Filter for numeric values, such as IP address or port number, to
        //! allow each instance of net::Protocol to inform the net::Dispatch
        //! layer which packets it accepts.
        //!
        //! Every instance of net::Protocol must define a multipurpose "Type" to
        //! inform the net::Dispatch layer which packets it accepts.  The Type
        //! can hold any numeric value up to 32 bits.  It may be an IP address,
        //! a port number, or any other numeric protocol or endpoint identifier.
        //! Each net::Protocol object is required to contain a net::Type that
        //! designates the type or identity of streams it can accept, or the
        //! corresponding field-values for outgoing frames.
        //!
        //! The formatting depends on the associated Dispatch, but is usually
        //! one-to-one with EtherType, UDP port #, etc. for that network layer.
        //! The size is chosen to fit any of the above without duress. In most
        //! cases, an exact match is required. However, the two-argument Type
        //! constructor can be used in conjunction with the u16 constructor to
        //! explicitly request partial matching on the second argument only.
        //! Such matching is symmetric, i.e., (x) matches (*, x) and vice-versa.
        //!
        //! Note: Dispatch implementations SHOULD provide public accessors
        //!       for creating Type objects from EtherType, Port#, etc.
        struct Type {
        public:
            //! Construct a Type from a single value.
            //! @{
            explicit constexpr Type(u8 val)
                : m_mask(0x000000FFu), m_value(val) {}
            explicit constexpr Type(u16 val)
                : m_mask(0x0000FFFFu), m_value(val) {}
            explicit constexpr Type(u32 val)
                : m_mask(0xFFFFFFFFu), m_value(val) {}
            //! @}

            //! Construct a Type from a pair of values, concatenated.
            explicit constexpr Type(u16 val1, u16 val2)
                : m_mask(0xFFFFFFFFu), m_value(65536ul * val1 + val2) {}

            //! Accessors for `m_value`.
            //! @{
            inline u8  as_u8()  const {return (u8) m_value;}
            inline u16 as_u16() const {return (u16)m_value;}
            inline u32 as_u32() const {return (u32)m_value;}
            //! @}

            //! Sets the given parameter to `m_value`.
            //! @{
            inline void as_u8(u8& a) const {a = as_u8();}
            inline void as_u16(u16& a) const {a = as_u16();}
            inline void as_u32(u32& a) const {a = as_u32();}
            inline void as_pair(u16& a, u16& b) const
                {a = (u16)(m_value >> 16); b = (u16)(m_value & 0xFFFF);}
            //! @}

            //! Is this Type actively filtering or is it TYPE_NONE?
            inline bool bound() const {return (m_value != 0);}

            //! Check if this Type matches `other`.
            inline bool match(const Type& other) const
                {return (m_value & other.m_mask) == (other.m_value & m_mask);}

        private:
            friend satcat5::net::Dispatch;
            u32 m_mask;         //!< 32-bit mask for `m_value`.
            u32 m_value;        //!< Underlying value to check for a match.
        };

        //! Use the TYPE_NONE placeholder when no filtering is required.
        constexpr satcat5::net::Type TYPE_NONE = Type((u32)0);
    }
}
