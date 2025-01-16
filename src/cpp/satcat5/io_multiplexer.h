//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Multiplexers for selecting one of several I/O interfaces.
//! \details
//! We define a "port" as a Readable pointer paired with a Writeable pointer,
//! representing input from and output to the same logical interface.  Examples
//! include a UART (cfg::Uart), or a MailMap object (port::Mailbox), or a
//! UDP socket (udp::Socket).
//!
//! A "controller" is anything that attaches to a port and begins issuing read
//! and write commands, such as an Ethernet network interface (eth::Dispatch)
//! or a port adapter (port::MailAdapter, port::SlipAdapter).  Some objects act
//! as both a port and a controller, such as BufferedIO (io::BufferedIO).

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace io {
        //! Helper object used inside io::MuxDown.
        class MuxPort
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::WriteableRedirect
        {
        public:
            //! Create an unattached port object.
            constexpr MuxPort()
                : ReadableRedirect(0), WriteableRedirect(&null_write) {}

            //! Override set_callback() to set the internal variable only.
            void set_callback(satcat5::io::EventListener* callback) override
                { satcat5::io::Readable::set_callback(callback); }

        protected:
            friend class satcat5::io::MuxDown;

            //! Update the redirect configuration to attach or detach this port.
            void attach(Readable* src, Writeable* dst)
                { read_src(src); write_dst(dst); }
        };

        //! Multiplexer connecting a port to one of several controllers.
        //! An example usage is operating a specific UART port in one of
        //! several different modes.
        //! \copydoc io_multiplexer.h
        class MuxDown : public satcat5::io::EventListener {
        public:
            //! Fetch the interface pointer for attaching the Nth controller.
            //! @{
            inline satcat5::io::Readable* port_rd(unsigned idx)
                { return (idx < m_size) ? (m_ports + idx) : 0; }
            inline satcat5::io::Writeable* port_wr(unsigned idx)
                { return (idx < m_size) ? (m_ports + idx) : 0; }
            //! @}

            //! Select the active controller index, or UINT_MAX for none.
            void select(unsigned idx);

        protected:
            //! Constructor and destructor should only be called by children.
            //! @{
            MuxDown(
                unsigned size, satcat5::io::MuxPort* ports,
                satcat5::io::Readable* src, satcat5::io::Writeable* dst);
            ~MuxDown() SATCAT5_OPTIONAL_DTOR;
            //! @}

            // Implement the EventListener API.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Pointers to the backing array and the shared port interface.
            const unsigned m_size;
            unsigned m_index;
            satcat5::io::MuxPort* const m_ports;
            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* const m_dst;
        };

        //! Multiplexer connecting a controller to one of several ports.
        //! Opposite of io::MuxDown, useful for directing messages to one of
        //! several destinations.
        //! \copydoc io_multiplexer.h
        class MuxUp
            : public satcat5::io::EventListener
            , public satcat5::io::MuxPort
        {
        public:
            //! Designate the read and write interfaces for the Nth port.
            void port_set(unsigned idx, Readable* src, Writeable* dst);

            //! Select the active port index, or UINT_MAX for none.
            void select(unsigned idx);

        protected:
            //! Constructor and destructor should only be called by children.
            //! @{
            constexpr MuxUp(unsigned size,
                satcat5::io::Readable** src, satcat5::io::Writeable** dst)
                : m_size(size), m_index(-1), m_src(src), m_dst(dst) {}
            ~MuxUp() SATCAT5_OPTIONAL_DTOR;
            //! @}

            // Implement the EventListener API.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Pointers to the backing array of port interfaces.
            const unsigned m_size;
            unsigned m_index;
            satcat5::io::Readable** const m_src;
            satcat5::io::Writeable** const m_dst;
        };

        //! Static allocator for io::MuxDown.
        //! \copydoc io::MuxDown
        template <unsigned SIZE>
        class MuxDownStatic final : public satcat5::io::MuxDown {
        public:
            MuxDownStatic(satcat5::io::Readable* src, satcat5::io::Writeable* dst)
                : MuxDown(SIZE, m_port_array, src, dst) {}
        private:
            satcat5::io::MuxPort m_port_array[SIZE];
        };

        //! Static allocator for io::MuxUp.
        //! \copydoc io::MuxUp
        template <unsigned SIZE>
        class MuxUpStatic final : public satcat5::io::MuxUp {
        public:
            MuxUpStatic()
                : MuxUp(SIZE, m_src_array, m_dst_array), m_src_array{0}, m_dst_array{0} {}
        private:
            satcat5::io::Readable* m_src_array[SIZE];
            satcat5::io::Writeable* m_dst_array[SIZE];
        };
    }
}
