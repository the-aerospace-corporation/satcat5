//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Generic API for network ports that support PTP
//
// PTP-compatible network interfaces must provide additional
// methods for accessing precise timestamps, and for inspecting
// incoming messages to determine their type. This file defines
// the minimum set of required methods.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace ptp {
        // Mark whether an incoming message is:
        //  * Not a PTP message
        //  * A PTP message transported on Layer 2 (Ethernet)
        //  * A PTP message transported on Layer 3 (UDP)
        enum class PacketType {NON_PTP, PTP_L2, PTP_L3};

        // Network interfaces with PTP support must derive from this class.
        class Interface
        {
        public:
            // Set callback object for PTP-related packet handling.
            inline void ptp_callback(satcat5::poll::OnDemand* obj)
                { m_ptp_callback = obj; }

            // Begin sending a timestamped message.
            // Return effective one-step timestamp if known, otherwise zero.
            // Child class MUST override this method.
            virtual satcat5::ptp::Time ptp_tx_start() = 0;

            // Return an object suitable for writing the next PTP frame.
            // (This may be the primary interface or a separate pointer.)
            // Child class MUST override this method.
            virtual satcat5::io::Writeable* ptp_tx_write() = 0;

            // Return timestamp of the most recent outgoing message.
            // Child class MUST override this method.
            virtual satcat5::ptp::Time ptp_tx_timestamp() = 0;

            // Return an object suitable for reading the next PTP frame.
            // (This may be the primary interface or a separate pointer.)
            // Child class MUST override this method.
            virtual satcat5::io::Readable* ptp_rx_read() = 0;

            // Return timestamp of the current incoming message.
            // Child class MUST override this method.
            virtual satcat5::ptp::Time ptp_rx_timestamp() = 0;

            // Return the packet type for the most recent message.
            inline satcat5::ptp::PacketType ptp_rx_type() const
                { return m_ptp_rx_type; }

        protected:
            // Constructor is not publicly accessible.
            Interface()
                : m_ptp_callback(0)
                , m_ptp_rx_type(PacketType::NON_PTP) {}

            // Determine if an incoming packet is a PTP message.
            // Child class MUST call this method for each received packet.
            // If this method returns true, call ptp_notify_now() or
            // ptp_notify_req(). Otherwise, continue normal processing.
            bool ptp_dispatch(const u8* peek, unsigned length);

            // Notify the PTP callback object in immediate or deferred mode.
            inline void ptp_notify_now()    {m_ptp_callback->poll_demand();}
            inline void ptp_notify_req()    {m_ptp_callback->request_poll();}

        private:
            satcat5::poll::OnDemand* m_ptp_callback;
            satcat5::ptp::PacketType m_ptp_rx_type;
        };
    }
}
