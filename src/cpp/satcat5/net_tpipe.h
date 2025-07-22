//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// "Tpipe" protocol for reliable byte-streams over UDP or Ethernet.

#pragma once

#include <satcat5/eth_address.h>
#include <satcat5/io_buffer.h>
#include <satcat5/net_core.h>
#include <satcat5/polling.h>
#include <satcat5/timeref.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace net {
        //! Simple network pipe service for reliable byte-streams.
        //!
        //! This class implements a bidirectional byte-stream over unreliable
        //! networks, using a simple lockstep protocol.  As with other lockstep
        //! protocols such as CoAP or TFTP, this trades simplicity for reduced
        //! performance.  Like TCP, it provides flow-control and retransmission
        //! logic for an abstract general-purpose byte-stream.  Unlike TCP, it
        //! does not adjust window-size to achieve maximum throughput.
        //!
        //! The protocol is transport-agnostic.  Child classes must provide a
        //! net::Address object for connectivity. \see eth::Tpipe, udp::Tpipe.
        //! Once a Tpipe object is created at each end of the link, one must
        //! call bind() to listen for a connection, and the other must call
        //! connect() with the remote address.  Once the connection is formed,
        //! data written to the local Tpipe can be read from the remote Tpipe,
        //! and vice-versa.
        //!
        //! The Tpipe packet header contains the following fields:
        //!     u16 flags = Start and end flags, data length.
        //!     u16 txpos = Transmit position for new data, if present.
        //!     u16 rxpos = Current acknowledge/receive position.
        //!     u8 data[] = Next block of data, if applicable.
        class Tpipe
            : public satcat5::io::BufferedIO
            , public satcat5::net::Protocol
            , protected satcat5::poll::Timer
        {
        public:
            //! Close the active connection.
            //! Note: Does not wait for acknowledgment.  If assured delivery
            //! is required, wait for `completed` before calling `close`.
            void close();

            //! Has all queued data been acknowledged?
            bool completed() const;

            //! Adjust retransmit interval.
            inline void set_retransmit(u16 msec) {m_retransmit = msec;}

            //! Adjust lost-connection timeout.
            inline void set_timeout(u16 msec) {m_timeout = msec;}

            //! Enable unidirectional transmission?
            //! Transmit-only endpoints do not wait for acknowledgements.
            //! Use this mode for unidirectional connections.  Not recommended
            //! for connections that may drop or reorder packets frequently.
            //! This flag remains set until the connection is closed.
            void set_txonly();

        protected:
            //! Create link and set the transport service.
            //! Also sets initial filter for incoming packets.
            explicit Tpipe(satcat5::net::Address* dst);
            ~Tpipe() SATCAT5_OPTIONAL_DTOR;

            // Internal event callbacks.
            void data_rcvd(satcat5::io::Readable* src) override;
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            //! Send a synchronization packet, with data if applicable.
            //! The `send_block` method is called whenever it's time to send a
            //! packet. This serves two purposes simultaneously.  First, it
            //! sends the latest acknowledgement state (txpos, rxpos) so the
            //! other side knows what data we've received.  Second, if there's
            //! any data in the transmit queue, it sends (or re-sends) that
            //! data using the `PacketBuffer::peek` method.  That data will
            //! be re-sent as needed (i.e., by future calls to `send_block`)
            //! until it is acknowledged and consumed from the FIFO.
            void send_block();

            //! Special case of `send_block` used to open a new connection.
            //! To open a new connection, the child class should configure its
            //! net::Address object and then call this method.
            void send_start();

            //! Buffer size is set by the maximum transmit window.
            static constexpr unsigned MAX_WINDOW = 512;

            // Other protocol constants:
            static constexpr u16
                FLAG_START      = 0x8000,   //!< Open new connection
                FLAG_STOP       = 0x4000,   //!< Connection is closing
                FLAG_LEN        = 0x03FF,   //!< Data length
                STATE_OPENREQ   = 0x0001,   //!< Opening new connection
                STATE_READY     = 0x0002,   //!< Connection acknowledged
                STATE_TXBUSY    = 0x0004,   //!< Tx sent, wait for ack
                STATE_CLOSING   = 0x0008,   //!< Closing connection
                STATE_TXONLY    = 0x0010;   //!< Unidirectional streaming

            // Protocol state.
            satcat5::net::Address* const m_iface; //!< Network interface
            u16 m_retry;                    //!< Retry elapsed time (msec)
            u16 m_state;                    //!< Status flags
            u16 m_retransmit;               //!< Retransmit timeout (msec)
            u16 m_timeout;                  //!< Connection timeout (msec)
            u16 m_txpos;                    //!< Transmit position
            u16 m_txref;                    //!< Transmit reference
            u16 m_rxpos;                    //!< Receive position
            u16 m_rxref;                    //!< Receive reference
            u8 m_txbuff[MAX_WINDOW];        //!< Working buffer (transmit)
            u8 m_rxbuff[MAX_WINDOW];        //!< Working buffer (receive)
        };
    }

    // Wrappers for commonly used network interfaces:
    namespace eth {
        //! Simple network pipe service over raw Ethernet.
        class Tpipe final
            : protected satcat5::eth::AddressContainer
            , public satcat5::net::Tpipe
        {
        public:
            //! Create an idle network pipe.
            explicit Tpipe(satcat5::eth::Dispatch* iface);

            //! Wait for incoming connections to the specified EtherType.
            void bind(
                const satcat5::eth::MacType& etype,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Create an outgoing connection with the specified server.
            void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& etype,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Is this connection ready to send and receive?
            inline bool ready() const {return m_addr.ready();}
        };
    }

    namespace udp {
        //! Simple network pipe service over raw Ethernet.
        class Tpipe final
            : protected satcat5::udp::AddressContainer
            , public satcat5::net::Tpipe
        {
        public:
            //! Create an idle network pipe.
            explicit Tpipe(satcat5::udp::Dispatch* iface);

            //! Wait for incoming connections to the specified UDP port.
            void bind(const satcat5::udp::Port& port);

            //! Create an outgoing connection with the specified server.
            void connect(
                const satcat5::ip::Addr& addr,
                const satcat5::udp::Port& port,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Is this connection ready to send and receive?
            inline bool ready() const {return m_addr.ready();}
        };
    }
}
