//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// TLV metadata for the IEEE 1588-2019 Precision Time Protocol (PTP)
//
// Type/Length/Value (TLV) extensions are optional metadata tags that
// may be appended to any PTP message.  Any number of TLVs may be
// chained together, up to the maximum practical frame size.  Details
// are defined in IEEE 1588-2019, Section 14.
//
// This file defines a plugin API for the SatCat5 PTP client, providing
// an extensible "TlvHandler" framework to read and write TLV tags.
// Users inherit from this base class to define new TLV functionality.
//
// When reading TLVs, the PTP Client reads the tlvType and lengthField
// from the TLV header (Section 14.1), and if applicable, organizationId
// and organizationSubType for organization-specific TLVs (Section 14.3.2).
// It then calls tlv_rcvd(...) for each registered TlvHandler.  User-defined
// TlvHandlers must accept and read relevant tags (return true) and ignore
// all other tags (return false).  Information from the PTP general header
// (Section 13.3.1) is also provided.
//
// When writing TLVs, the PTP Client first calls tlv_send(NULL) for each
// registered TlvHandler, to query the number of bytes that will be written.
// Next, the Client calls tlv_send(...) again with an io::Writeable pointer,
// giving each the opportunity to append a TLV tag to the outgoing message.
//
// The written length MUST match the predicted length.  Each TlvHandler
// MUST write complete tag(s) starting with tlvType, and it must return
// without calling write_finalize().
//
// Finally, whenever the PTP Client completes a two-way time transfer
// handshake (i.e., SYNC -> DELAY_REQ -> DELAY_RESP), it immediately calls
// tlv_meas(...) for each registered TlvHandler.
//
// The provided ptp::Measurement object contains the four critical timestamps
// and other metadata, which can be read or modified.  If the ptp::Measurement
// should be invalidated, the TlvHandler should set it to MEASUREMENT_NULL.
// Once all TlvHandlers have been notified, the Client will proceed to notify
// its callbacks, including clock discipline based on offsetFromMaster().
//

#pragma once

#include <satcat5/list.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace ptp {
        // Define some key tlvType values (Section 14.1.1)
        constexpr u16
            TLVTYPE_NONE        = 0x0000,
            TLVTYPE_MANAGEMENT  = 0x0001,
            TLVTYPE_ORG_EXT     = 0x0003,
            TLVTYPE_PATH_TRACE  = 0x0008,
            TLVTYPE_DOPPLER     = 0x20AE,   // Experimental / SatCat5 only
            TLVTYPE_ORG_EXT_P   = 0x4000,
            TLVTYPE_ORG_EXT_NP  = 0x8000,
            TLVTYPE_PAD         = 0x8008,
            TLVTYPE_AUTH        = 0x8009;

        // Data structure for identifying TLV headers.
        // Some fields only apply to organization extension TLVs per
        // Section 14.3, and will be set to zero otherwise.
        struct TlvHeader {
            // Access to the raw header fields
            // Note: This "length" field always reflects the user data length,
            //  excluding the 6-byte organizationId/SubType if applicable.
            u16 type;       // (All) tlvType
            u16 length;     // (All) Length of dataField or valueField
            u32 org_id;     // (Org) organizationId (zero = disabled)
            u32 org_sub;    // (Org) organizationSubType (zero = disabled)

            // Does this TLV match the designated type and/or subtype?
            bool match(const satcat5::ptp::TlvHeader& other) const;

            // When attached to ANNOUNCE messages, certain TLVs are required
            // to propagate across boundary clocks, even if those tags are
            // otherwise unsupported by a given implementation.
            bool propagate() const;

            // Total length of TLV header, or header plus associated data.
            // (Use this to predict tag length for "tlv_send".)
            inline constexpr unsigned len_header() const
                {return (org_id || org_sub) ? 10 : 4;}
            inline constexpr unsigned len_total() const
                {return len_header() + length;}

            // I/O functions read or write the TLV header only.
            // User is responsible for reading or writing tag data.
            void write_to(satcat5::io::Writeable* wr) const;
            bool read_from(satcat5::io::Readable* rd);
        };

        constexpr satcat5::ptp::TlvHeader TLV_HEADER_NONE = {0, 0, 0, 0};

        // Users should derive custom TLV objects from this base class.
        // The child class should override tlv_rcvd(), tlv_send(), or both.
        class TlvHandler {
        public:
            // Child class SHOULD override this method to read incoming TLV(s).
            // See discussion above. For matching type(s), read the TLV
            // contents and return true; otherwise return false.
            // The default handler does not match any incoming TLV.
            virtual bool tlv_rcvd(
                const satcat5::ptp::Header& hdr,    // Received message header
                const satcat5::ptp::TlvHeader& tlv, // Received TLV header
                satcat5::io::LimitedRead& rd);      // Received TLV data

            // Child class SHOULD override this method to append outgoing TLV(s).
            // The override method MUST predict its output length (input = null).
            // See discussion above. Returns predicted or actual length in bytes.
            // The default handler does not emit any outgoing TLVs.
            virtual unsigned tlv_send(
                const satcat5::ptp::Header& hdr,    // Received message header
                satcat5::io::Writeable* wr);

            // Child class MAY override this method to read or modify each
            // complete two-way handshake event.  See discussion above.
            // The default handler takes no action.
            virtual void tlv_meas(satcat5::ptp::Measurement& meas);

        protected:
            // Only children should create or destroy the base class.
            explicit TlvHandler(satcat5::ptp::Client* client);
            ~TlvHandler();

            // Pointer to the associated PTP client.
            satcat5::ptp::Client* const m_client;

        private:
            // Linked list pointer to the next registered TlvHandler.
            friend satcat5::util::ListCore;
            satcat5::ptp::TlvHandler* m_next;
        };
    }
}
