//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// POSIX and Windows interface objects for connecting to a UART

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
        //! POSIX and Windows interface objects for connecting to a UART.
        //! This class implements a buffered, non-blocking UART compatible
        //! with the usual io::Readable and io::Writeable API.  Portions of
        //! this design are adapted from Andre Renaud's "simple_uart":
        //! https://github.com/AndreRenaud/simple_uart/blob/master/simple_uart.c
        class PosixUart
            : public satcat5::io::BufferedIO
            , public satcat5::poll::Always
        {
        public:
            //! Create UART attached to the given device name.
            //! On Linux, the device name usually looks like "/dev/ttyUSB0".
            //! On Windows, the device name usually looks like "COM4".
            PosixUart(const char* device, unsigned baud,
                unsigned buffer_size_bytes=4096);
            ~PosixUart();

            //! Is this device ready for input and output?
            inline bool ok() const {return m_ok;}

        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            void poll_always() override;
            unsigned chunk_rx();
            unsigned chunk_tx();

            bool m_ok;
            SATCAT5_UART_DESCRIPTOR m_uart;
        };

        //! SLIP-encoded wrapper for the PosixUart class.
        //! Includes calculation and verification of FCS for each frame.
        class SlipUart
            : public satcat5::io::WriteableRedirect
            , public satcat5::io::ReadableRedirect
        {
        public:
            // Create the UART interface object. \see PosixUart.
            SlipUart(const char* device, unsigned baud, unsigned buffer=4096);
            inline bool ok() const {return m_uart.ok();}

        protected:
            satcat5::io::PosixUart m_uart;
            satcat5::eth::SlipCodec m_slip;
        };
    }
}
