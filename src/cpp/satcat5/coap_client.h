//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simplified CoAP client implementation.

#pragma once
#include <satcat5/coap_endpoint.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace coap {
        //! Simplified CoAP client that writes responses to a PacketBuffer.
        //!
        //! This CoAP endpoint can send simple requests to a remote server,
        //! saving response data to a PacketBuffer for later access.
        class SimpleClient : public satcat5::coap::Endpoint {
        public:
            //! Message-ID and token for the most recent request.
            inline u16 msg_id() const
                { return m_msg_id; }

            //! Request notifications for incoming responses.
            inline void set_callback(satcat5::io::EventListener* obj)
                { m_rcvd.set_callback(obj); }

            //! Create and send a CoAP request, with optional data.
            //! Various options are provided for generating message contents.
            //!@{
            bool request(satcat5::coap::Code code,
                const char* uri, const char* data,
                u16 fmt = satcat5::coap::FORMAT_TEXT);
            bool request(satcat5::coap::Code code,
                const char* uri, satcat5::io::Readable* data = 0,
                u16 fmt = satcat5::coap::FORMAT_BYTES);
            bool request(satcat5::coap::Code code,
                const char* uri, satcat5::cbor::CborWriter& cbor);
            //!@}

            //! Read full header and contents of the next CoAP response.
            satcat5::io::Readable* response_all();

            //! Read the contents of the next CoAP response.
            satcat5::io::Readable* response_data();

            //! Discard the contents of the next CoAP response.
            bool response_discard();

        protected:
            //! Constructor attaches to a network interface.
            //! User may optionally request additional connection buffers.
            explicit SimpleClient(satcat5::net::Dispatch* iface);

            //! Save the incoming response message.
            void coap_response(
                satcat5::coap::Connection* obj,
                satcat5::coap::Reader* msg) override;

            // Other internal variables.
            satcat5::io::PacketBufferStatic<SATCAT5_COAP_BUFFSIZE> m_rcvd;
            u16 m_msg_id;
        };

        //! Variant of SimpleClient using a single outgoing SPP connection.
        class SimpleClientSpp
            : public satcat5::coap::SimpleClient
            , public satcat5::coap::ManageSpp {
        public:
            SimpleClientSpp(satcat5::ccsds_spp::Dispatch* iface, u16 apid);
        };

        //! Variant of SimpleClient using a single outgoing UDP connection.
        class SimpleClientUdp
            : public satcat5::coap::SimpleClient
            , public satcat5::coap::ManageUdp {
        public:
            explicit SimpleClientUdp(satcat5::udp::Dispatch* iface);

        protected:
            satcat5::coap::ConnectionUdp m_connection;
        };
    }
};
