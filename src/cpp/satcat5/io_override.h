//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Remote-control override of an I/O device.

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace io {
        //! Remote-control override of an I/O device.
        //! For any I/O device with a io::Readable / io::Writeable interface,
        //! this class allows automatic switching between normal passthrough
        //! operation and remote control by another device.  While in remote
        //! control mode, passthrough commands are blocked.
        //!
        //! The io::Override object is attached to the I/O device on creation.
        //! From that point, users should not access the I/O device directly.
        //! Instead, read and write calls pass through the io::Override object
        //! to the underlying I/O device.
        //! ```
        //!     cfg::Uart my_uart(&cfgbus, 123);        // Example UART object
        //!     io::Override local(&my_uart, &my_uart); // Attach override
        //!     local.write_str("Local data");          // Passthrough to UART
        //!     local.write_finalize();                 // Passthrough to UART
        //!     if (local.get_read_ready()) {...}       // Passthrough to UART
        //! ```
        //!
        //! The remote-control interface is attached later.  Any buffered I/O
        //! stream can be used, such as io::PacketBuffer or net::Tpipe.
        //!
        //! Remote-control mode is activated whenever data appears in the
        //! remote-control buffer, or by direct call to `set_override`.  Once
        //! the object is in remote mode, the remote interface has exclusive
        //! control. Local passthrough calls are blocked, and received data
        //! is copied to the remote interface buffer.
        //! ```
        //!     io::PacketBufferHeap remote;            // Remote control
        //!     local.set_remote(&remote, &remote);     // Attach remote
        //!     local.write_str("In normal mode, local data is accepted.");
        //!     local.write_finalize();                 // Accepted
        //!     remote.write_str("Remote data activates override mode.");
        //!     remote.write_finalize();                // Accepted
        //!     local.write_str("In remote mode, local data is blocked.");
        //!     local.write_finalize();                 // Blocked
        //! ```
        //!
        //! The system returns to normal operation after a period of inactivity
        //! (default 30 seconds) or by another direct call to `set_override`.
        class Override final
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::WriteableRedirect
            , protected satcat5::io::EventListener
            , protected satcat5::poll::Timer
        {
        public:
            //! Attach to the underlying I/O device.
            //! \param src Data source to be read.
            //! \param dst Destination to be written.
            //! \param mode Set data-streaming mode.
            Override(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src,
                satcat5::io::CopyMode mode = CopyMode::PACKET);
            ~Override() SATCAT5_OPTIONAL_DTOR;

            //! Override set_callback() to set the internal variable only.
            void set_callback(satcat5::io::EventListener* callback) override
                { satcat5::io::Readable::set_callback(callback); }

            //! Is this block in local or remote mode?
            inline bool is_remote() const
                { return m_remote; }

            //! Manually set local or remote mode.
            void set_override(bool remote);

            //! Attach the remote-control interface.
            void set_remote(satcat5::io::Writeable* tx, satcat5::io::Readable* rx);

            //! Set timeout for automatic return to local mode.
            //! A timeout of zero disables this function.
            void set_timeout(unsigned msec);

        protected:
            // Event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;
            void timer_event() override;
            void watchdog_reset();

            // Internal state
            satcat5::io::Readable  *m_dev_rd, *m_ovr_rd;
            satcat5::io::Writeable *m_dev_wr, *m_ovr_wr;
            const satcat5::io::CopyMode m_mode;
            bool m_remote;
            unsigned m_timeout;
        };
    }
}
