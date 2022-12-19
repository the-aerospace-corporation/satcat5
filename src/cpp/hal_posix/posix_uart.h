//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// POSIX and Windows interface objects for connecting to a UART
// Portions adapted from: https://github.com/AndreRenaud/simple_uart/blob/master/simple_uart.c

#pragma once

#include <satcat5/eth_checksum.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>

#ifdef _WIN32
    #define SATCAT5_WIN32 1
    typedef void* SATCAT5_UART_DESCRIPTOR;
#else
    #define SATCAT5_WIN32 0
    typedef int SATCAT5_UART_DESCRIPTOR;
#endif

namespace satcat5 {
    namespace io {
        // Connection to a buffered non-blocking UART.
        class PosixUart
            : public satcat5::io::BufferedIO
            , public satcat5::poll::Always
        {
        public:
            PosixUart(const char* device, unsigned baud,
                unsigned buffer_size_bytes=4096);
            ~PosixUart();

            inline bool ok() const {return m_ok;}

        protected:
            void data_rcvd() override;
            void poll_always() override;
            unsigned chunk_rx();
            unsigned chunk_tx();

            bool m_ok;
            SATCAT5_UART_DESCRIPTOR m_uart;
        };

        // SLIP-encoded wrapper for the PosixUart class.
        // Includes calculation and verification of FCS for each frame.
        class SlipUart
            : public satcat5::io::WriteableRedirect
            , public satcat5::io::ReadableRedirect
        {
        public:
            SlipUart(const char* device, unsigned baud, unsigned buffer=4096);
            inline bool ok() const {return m_uart.ok();}

        protected:
            satcat5::io::PosixUart m_uart;
            satcat5::eth::SlipCodec m_slip;
        };
    }
}
