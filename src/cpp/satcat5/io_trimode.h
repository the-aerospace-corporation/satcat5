//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Configurable port with Raw, CCSDS, or SLIP mode.
//!
//! \copydetails TriMode


#pragma once

#include <satcat5/ccsds_aos.h>
#include <satcat5/ccsds_spp.h>
#include <satcat5/eth_switch.h>
#include <satcat5/io_multiplexer.h>
#include <satcat5/port_adapter.h>

// Default buffer size and block-size parameters.
#ifndef SATCAT5_TRIMODE_AOSBLOCK
#define SATCAT5_TRIMODE_AOSBLOCK 251
#endif

#ifndef SATCAT5_TRIMODE_BUFFSIZE
#define SATCAT5_TRIMODE_BUFFSIZE 2048
#endif

// In many applications, an SPP packet must be contained in a UDP datagram,
// which is contained in an IP packet, which is contained in a single Ethernet
// frame. An Ethernet frame has a maximum data payload of 1500 bytes,
// an IPv4 header is 20 bytes, a UDP header is 8 bytes, and an SPP header is
// 6 bytes. So the maximum SPP payload size is 1500 - 20 - 8 - 6 = 1466 bytes.
#ifndef SATCAT5_TRIMODE_SPPMAXSIZE
#define SATCAT5_TRIMODE_SPPMAXSIZE 1466
#endif

namespace satcat5 {
    namespace io {
        //! Configurable port with Raw, CCSDS, or SLIP mode.
        //!
        //! When attached to a UART or other streaming I/O device, this
        //! port toggles between three different operating modes:
        //! * In "Off" mode, all input and output are disabled.
        //! * In "Raw" mode, the user formats the byte-stream.
        //! * In "AOS" mode, the physical layer is CCSDS-AOS carrying
        //!   either CCSDS-SPP packets (M_PDU on virtual channel 0) or
        //!   a byte-stream (B_PDU on virtual channel 1).
        //! * In "SPP" mode, the physical layer is carries concatenated
        //!   CCSDS-SPP packets with no additional encoding or framing.
        //! * In "SLIP" mode, the physical layer is SLIP-encoded Ethernet.
        //!
        //! Raw and CCSDS modes are connected through this object's
        //! io::Readable and io::Writeable API.  Both input and output
        //! streams may use raw or CCSDS-SPP format, chosen separately.
        //! SPP headers are added or removed as needed, using the APID
        //! for raw byte-streams that is passed to the constructor.
        class TriMode
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::WriteableRedirect {
        public:
            //! Specify format of an internal stream.
            enum class Stream { OFF, RAW, SPP };

            //! Specify format of the external port.
            enum class Port { OFF, RAW, AOS, SPP, SLIP };

            //! Constructor binds to an I/O device and the Ethernet switch.
            //! Default port state is OFF. Call `configure` to set mode.
            TriMode(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst,
                u16 apid_raw = 0);

            //! Set the input and output formats.
            //! If #port is OFF or SLIP, then arguments #tx and #rx are unused.
            void configure(Port port,
                Stream tx = Stream::OFF,
                Stream rx = Stream::OFF);

            //! Count invalid Ethernet or AOS frames since last query.
            //! (This function will always return zero in RAW mode.)
            unsigned error_count();

            //! Count valid Ethernet or AOS frames since last query.
            //! (This function will always return zero in RAW mode.)
            unsigned frame_count();

            //! Accessor for the inner Ethernet port.
            inline satcat5::port::SlipAdapter* eth_port()
                { return &m_eth_slip; }

        protected:
            //! Pointer to the source object.
            satcat5::io::Readable* const m_src;

            //! Egress/transmit buffer with optional SPP packetization.
            satcat5::ccsds_spp::PacketizerStatic<SATCAT5_TRIMODE_BUFFSIZE> m_rx_buff;

            //! Ingress/receive buffer with optional SPP packetization.
            satcat5::ccsds_spp::PacketizerStatic<SATCAT5_TRIMODE_BUFFSIZE> m_tx_buff;

            //! Auxiliary buffers and decoders required for Rx AOS channels.
            //!@{
            satcat5::io::StreamBufferStatic<SATCAT5_TRIMODE_BUFFSIZE>      m_rx_bpdu;
            satcat5::ccsds_spp::PacketizerStatic<SATCAT5_TRIMODE_BUFFSIZE> m_rx_mpdu;
            satcat5::ccsds_aos::DispatchStatic<SATCAT5_TRIMODE_AOSBLOCK> m_aos_core;
            satcat5::ccsds_aos::Channel     m_aos_bpdu;
            satcat5::ccsds_aos::Channel     m_aos_mpdu;
            //!@}

            //! Encoder & decoder units for Raw and SPP modes.
            //!@{
            satcat5::io::BufferedCopy       m_copy_rx;
            satcat5::io::BufferedCopy       m_copy_tx;
            satcat5::port::SlipAdapter      m_eth_slip;
            satcat5::ccsds_spp::Dispatch    m_spp_rx;
            satcat5::ccsds_spp::BytesToSpp  m_spp_rxi;
            satcat5::ccsds_spp::SppToBytes  m_spp_rxr;
            satcat5::ccsds_spp::Dispatch    m_spp_tx;
            satcat5::ccsds_spp::BytesToSpp  m_spp_txi;
            satcat5::ccsds_spp::SppToBytes  m_spp_txr;
            //!@}
        };
    }
}
