//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CoAP request/response handling for a single client-server connection

#pragma once

#include <satcat5/ccsds_spp.h>
#include <satcat5/coap_constants.h>
#include <satcat5/udp_core.h>

// Maximum outgoing message size, excluding Eth/IP/UDP overhead.
// Default matches the recommended maximum from Section 4.6.
#ifndef SATCAT5_COAP_BUFFSIZE
#define SATCAT5_COAP_BUFFSIZE 1152
#endif

// Store a record of the last N received requests (Msg ID + token).
// Allows detection of new requests without assuming sequential IDs.
// Stale out-of-order deliveries must not exceed this upper bound.
#ifndef SATCAT5_COAP_HISTORY
#define SATCAT5_COAP_HISTORY 4
#endif

namespace satcat5 {
    namespace coap {
        //! CoAP request/response handling for a single client-server connection.
        //!
        //! This class implements automatic retry & cache logic for the request
        //! and response layer of the Constrained Applications Protocol (CoAP):
        //!  https://www.rfc-editor.org/rfc/rfc7252
        //!
        //! Because CoAP uses UDP, messages may be lost in transit.  Outgoing
        //! requests must retry after a timeout, repeating until a response is
        //! received. Therefore, some care is required to ensure that requests
        //! are idempotent, i.e., side effects are executed exactly once.  CoAP
        //! achieves this with a response cache, where repeated requests replay
        //! the cached response instead of re-executing the request.
        //!
        //! The coap::Connection class implements either of these functions:
        //! retry of outgoing requests (Section 4.2) and/or cached-replay of
        //! outgoing responses (Section 4.4).  Either mode requires a buffer
        //! equal to the max outgoing message size (i.e., SATCAT5_COAP_BUFFSIZE).
        //!
        //! Due to packet loss and reordering, there are many possible edge-cases
        //! that must be handled gracefully.  A particularly useful reference is
        //! Angelo Castellani's "Learning CoAP separate responses by example":
        //!  https://www.ietf.org/proceedings/83/slides/slides-83-lwig-3.pdf
        //!
        //! Because CoAP allows only one in-progress request/response at a time
        //! (Section 4.7), one buffer is sufficient for any given client/server
        //! pair.  As such, simple clients may only need a single coap::Connection
        //! object, but more complex client/server endpoints may need one for each
        //! concurrent connection, incoming or outgoing.
        //!
        //! Because there may be multiple coap::Connection objects servicing the
        //! same UDP port, both coap::Connection and coap::Endpoint must cooperate
        //! in order to service all possible incoming messages.
        class Connection
            : protected satcat5::net::Protocol
            , protected satcat5::poll::Timer
            , protected satcat5::io::ArrayWriteStatic<SATCAT5_COAP_BUFFSIZE>
        {
        public:
            // Accessors for the cache state.
            inline bool is_idle() const         //!< Idle and ready for use?
                { return m_state == State::IDLE && m_allow_reuse; }
            inline bool is_match_addr() const   //!< Match reply endpoint?
                { return m_addr->matches_reply_address(); }
            bool is_match_coap(                 //!< Match message ID & token?
                const satcat5::coap::ReadHeader* msg) const;
            bool is_match_reuse() const;        //!< Idle or continue same connection
            inline bool is_await() const        //!< Awaiting initial response?
                { return m_state == State::WAIT_RESPONSE_U
                      || m_state == State::WAIT_RESPONSE_M
                      || m_state == State::RESPONSE_SEP1;}
            inline bool is_connecting() const   //!< Connection in progress?
                { return m_state == State::CONNECT_IDLE
                      || m_state == State::CONNECT_BUSY; }
            inline bool is_request() const      //!< Any request state?
                { return m_state == State::REQUEST_CON
                      || m_state == State::REQUEST_NON
                      || m_state == State::REQUEST_SEP; }
            inline bool is_response() const     //!< Any response state?
                { return m_state == State::RESPONSE_CACHE
                      || m_state == State::RESPONSE_DEFER
                      || m_state == State::RESPONSE_SEP1
                      || m_state == State::RESPONSE_SEP2; }
            inline bool is_separate() const     //!< Awaiting separate response?
                { return m_state == State::RESPONSE_SEP1
                      || m_state == State::RESPONSE_SEP2; }
            inline u16 msg_id() const           //!< Most recent message ID
                { return m_msgid[m_meta_idx]; }
            inline u64 token() const            //!< Most recent message token
                { return m_token[m_meta_idx]; }
            inline u8 tkl() const               //!< Most recent token length
                { return m_flags[m_meta_idx] & 0x0F; }

            //! Close any open connections and reset state.
            void close();

            // Child class SHOULD implement a connect(...) method that
            // sets connection parameters for outgoing requests.  That
            // method must call connected() to update the parent state.
            // (See examples ConnectionSpp and ConnectionUdp, below.)
            // Connections in this state remain open until explicitly
            // closed, and are not reused even if they appear to be idle.

            //! If able, send a ping request to the remote client.
            //! (Use child's connect() method to set the target address.)
            bool ping(u16 msg_id);

            //! Query the most recent proxy token. \see proxy_set.
            inline u32 get_proxy_token() const
                { return m_proxy_token; }

            //! Set identifier for matching incoming proxy responses.
            //! This token is set by the coap::ProxyServer, sent with the
            //! forwarded request, then used to route incoming responses.
            //! It is unrelated to the incoming message, \see token().
            inline void set_proxy_token(u32 token)
                { m_proxy_token = token; }

            //! Ready to send a request?
            bool ready() const;

            //! If able, send a request to the current remote server.
            //! \returns Writeable for preparing the request, or null on error.
            satcat5::io::Writeable* open_request();

            //! If able, accept an incoming request from a remote client.
            //! Use this method to send a piggybacked response or the first
            //! message in a separated response.  (See "open_separate".)
            //! Return Writeable for preparing the response, or null on error.
            satcat5::io::Writeable* open_response();

            //! If able, send the first half of a separated response.
            //! Returns true if successful, and automatically sends the initial ACK.
            bool open_separate(const satcat5::coap::ReadHeader* msg);

            //! If able, send the second half of a separated response.
            //! Return Writeable for preparing the pseudo-request, or null on error.
            satcat5::io::Writeable* continue_separate();

            //! Automatically call open_response() or continue_separate().
            //! Return Writeable for preparing the response, or null on error.
            inline satcat5::io::Writeable* open_response_auto()
                { return is_separate() ? continue_separate() : open_response(); }

            //! If able, return an error in response to an incoming request from
            //! a remote client. Sends an ACK with a Client or Server Error code
            //! (4.xx or 5.xx) with an optional string payload diagnostic message
            bool error_response(satcat5::coap::Code code, const char* why = 0);

            //! Determine the expected response type for an incoming request.
            u8 response_type() const;

            //! Test only: Send a message using the active connection.
            //! Users should not call this method in production logic.
            bool test_inject(unsigned len, const void* data);

        protected:
            //! Constructor is only accessible to child classes.
            //! The child class MUST allocate a net::Address object.
            //! The Endpoint pointer MAY be null. \see init.
            //! The Address pointer MUST NOT be null.
            Connection(
                satcat5::coap::Endpoint* endpoint,
                satcat5::net::Address* addr);
            ~Connection() SATCAT5_OPTIONAL_DTOR;

            //! Deferred initialization of the upstream interface.
            //! Used infrequently. If the constructor's Endpoint argument is
            //! null, use this method to later assign the missing interface.
            void init(satcat5::coap::Endpoint* endpoint);

            // External event handling.
            friend satcat5::coap::Endpoint;
            bool deliver(satcat5::coap::Reader* msg);
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;
            bool write_finalize() override;

            // Internal event handling.
            bool connected(bool allow_reuse);
            void error_event();
            int match_history(const satcat5::coap::ReadHeader* msg) const;
            void push_history(const satcat5::coap::ReadHeader* msg);
            void reset_hard();
            void reset_soft();
            bool send_buffer();
            bool send_empty(u8 typ, u16 id);
            bool send_first();
            void timer_rand(u32 base_msec);

            // Internal state.
            enum class State {
                IDLE,               // Idle
                ERROR,              // Error-handling in progress
                CONNECT_IDLE,       // Connection in progress, otherwise idle
                CONNECT_BUSY,       // Connection in progress, transmit once ready
                WAIT_RESPONSE_U,    // Unicast request received, awaiting response
                WAIT_RESPONSE_M,    // Multicast request received, awaiting response
                REQUEST_CON,        // Confirmable request with timed retransmit
                REQUEST_NON,        // Nonconfirmable request without retransmit
                REQUEST_SEP,        // Waiting to receive part 2 of separated response
                RESPONSE_CACHE,     // Standard response with cached retransmit
                RESPONSE_DEFER,     // Delayed response to multicast query
                RESPONSE_SEP1,      // Waiting to send separated response
                RESPONSE_SEP2};     // Waiting for ACK to separated response
            satcat5::coap::Endpoint* m_coap;        // Client or server
            satcat5::net::Address* const m_addr;    // Remote address object
            State m_state;                          // Connection state
            u32 m_proxy_token;                      // Reverse-proxy identifier
            u8 m_allow_reuse;                       // Ephemeral connection?
            u8 m_tx_count;                          // Transmission count
            u8 m_meta_idx;                          // History write index [0..N)
            u8 m_meta_count;                        // History depth [0..N]
            u8 m_flags[SATCAT5_COAP_HISTORY];       // History of transaction flags
            u16 m_msgid[SATCAT5_COAP_HISTORY];      // History of message IDs
            u64 m_token[SATCAT5_COAP_HISTORY];      // History of tokens (0-8 bytes)

        private:
            // Linked list of other Connection objects.
            friend satcat5::util::ListCore;
            satcat5::coap::Connection* m_next;
        };

        //! Variant of coap::Connection for CCSDS-SPP connections.
        class ConnectionSpp final : public satcat5::coap::Connection {
        public:
            //! Create cache object and link it to the designated endpoint.
            ConnectionSpp(
                satcat5::coap::Endpoint* endpoint,
                satcat5::ccsds_spp::Dispatch* iface);

            //! Set remote APID for later calls to open_request().
            //! Allowed from the idle state only. Returns true on success.
            bool connect(u16 apid);

        private:
            //! Connection to a specific APID.
            satcat5::ccsds_spp::Address m_spp;
        };

        //! Variant of coap::Connection for UDP connections.
        class ConnectionUdp final : public satcat5::coap::Connection {
        public:
            //! Create cache object and link it to the designated endpoint.
            ConnectionUdp(
                satcat5::coap::Endpoint* endpoint,
                satcat5::udp::Dispatch* iface)
                : Connection(endpoint, &m_udp), m_udp(iface) {}

            //! Default constructor must subsequently call init().
            ConnectionUdp()
                : Connection(nullptr, &m_udp), m_udp(nullptr) {}

            //! Deferred initialization of the upstream interface.
            //! Required for array initialization. \see ConnectionUdpArray.
            void init(
                satcat5::coap::Endpoint* endpoint,
                satcat5::udp::Dispatch* iface);

            //! Set remote endpoint for later calls to open_request().
            //! Allowed from the idle state only. Returns true on success.
            bool connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport = satcat5::udp::PORT_COAP,
                const satcat5::udp::Port& srcport = satcat5::udp::PORT_NONE,
                bool allow_reuse = false);

            //! Is this object connected to the designated address?
            bool is_match_addr(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport) const;

            //! Connection to a specific IP address and UDP port.
            satcat5::udp::Address m_udp;
        };

        //! Statically-allocated array of ConnectionUdp objects.
        template <unsigned SIZE>
        class ConnectionUdpArray final {
        public:
            //! Link each ConnectionUdp object to the specified interfaces.
            ConnectionUdpArray(
                satcat5::coap::Endpoint* endpoint,
                satcat5::udp::Dispatch* iface)
                : m_array{} // Use default constructor
            {
                for (unsigned a = 0 ; a < SIZE ; ++a) {
                    m_array[a].init(endpoint, iface);
                }
            }

            //! Access an internal connection object by index.
            inline ConnectionUdp& operator[](unsigned idx)
                { return m_array[idx]; }

        private:
            satcat5::coap::ConnectionUdp m_array[SIZE];
        };
    }
}
