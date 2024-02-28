//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
