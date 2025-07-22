//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Connect a SatCat5 byte-stream to a Linux or Windows TCP socket.

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace tcp {
        //! Connect a SatCat5 byte-stream to a Linux or Windows TCP socket.
        //! This is a thin-wrapper around the "sys/socket.h" or "winsock.h"
        //! API, depending on the host platform.  In both cases, it operates
        //! in the main SatCat5 thread, using non-blocking I/O with polling.
        //! Server sockets accept one connection at a time, reverting to
        //! listen/accept mode once the connected client is closed.  Once
        //! a connection is established, bytes stream from the local endpoint
        //! to the remote endpoint and vice-versa.
        class SocketPosix
            : public satcat5::io::BufferedIO
            , public satcat5::poll::Timer
        {
        public:
            explicit SocketPosix(unsigned txbytes=8192, unsigned rxbytes=8192);
            virtual ~SocketPosix();

            //! Close any open sockets and return to idle.
            void close();

            //! Prepare to accept connection from a remote client endpoint.
            bool bind(const satcat5::ip::Port& port);

            //! Attempt connection to a remote server endpoint.
            //!@{
            bool connect(
                const char* hostname,
                const satcat5::ip::Port& port);
            bool connect(
                const satcat5::ip::Addr& addr,
                const satcat5::ip::Port& port);
            //!@}

            //! Is this connection ready to send and receive data?
            bool ready();

            //! Set a Tx/Rx rate-limit in kilobits-per-second, or zero to disable.
            inline void set_rate_kbps(unsigned kbps)
                { m_rate_kbps = kbps; }

        private:
            // Internal event handlers:
            void data_rcvd(satcat5::io::Readable* src) override;
            void timer_event() override;
            int open_nonblock_socket();
            unsigned rate_limit(satcat5::util::TimeVal& tv);

            // Internal state:
            u32 m_flags;                //!< Additional status flags.
            util::TimeVal m_last_rx;    //!< Time since last receive event.
            util::TimeVal m_last_tx;    //!< Time since last transmit event.
            int m_sock_listen;          //!< Socket for accept/bind, if applicable.
            int m_sock_data;            //!< Socket for data transfer, if connected.
            unsigned m_rate_kbps;      //!< Maximum bytes/msec, if applicable.
        };
    }
}
