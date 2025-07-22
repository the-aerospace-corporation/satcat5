//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_client.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <satcat5/io_cbor.h>
#include <satcat5/udp_dispatch.h>

using satcat5::coap::SimpleClient;

SimpleClient::SimpleClient(satcat5::net::Dispatch* iface)
    : Endpoint(iface)
    , m_rcvd(16)        // Up to 16 packets
    , m_msg_id(0)       // Initial message ID
{
    // Nothing else to initialize.
}

bool SimpleClient::request(satcat5::coap::Code code,
    const char* uri, satcat5::io::Readable* data, u16 fmt)
{
    // User needs to call connect() first.
    if (!m_prefer) return false;

    // Every request needs a unique ID.
    ++m_msg_id;

    // Write header with all requested options and data.
    // TODO: Can we add an API for additional options?
    satcat5::coap::Writer wr(m_prefer->open_request());
    if (!wr.ready()) return false;
    wr.write_header(satcat5::coap::TYPE_CON, code, m_msg_id, m_msg_id);
    if (uri) wr.write_uri(satcat5::coap::OPTION_URI_PATH, uri);
    if (data) {
        wr.write_option(satcat5::coap::OPTION_FORMAT, fmt);
        data->copy_to(wr.write_data());
        data->read_finalize();
    }
    return wr.write_finalize();
}

bool SimpleClient::request(satcat5::coap::Code code,
    const char* uri, const char* data, u16 fmt)
{
    satcat5::io::ArrayRead rd(data, strlen(data));
    return request(code, uri, &rd, fmt);
}

bool SimpleClient::request(satcat5::coap::Code code,
    const char* uri, satcat5::cbor::CborWriter& cbor)
{
#if SATCAT5_CBOR_ENABLE
    // TODO: Automatically add the CBOR format tag?
    return request(code, uri, cbor.get_buffer(), satcat5::coap::FORMAT_CBOR);
#else
    return false;   // CBOR disabled -> Abort.
#endif
}

satcat5::io::Readable* SimpleClient::response_all() {
    if (m_rcvd.get_read_ready() == 0) return nullptr;
    return &m_rcvd;
}

satcat5::io::Readable* SimpleClient::response_data() {
    if (m_rcvd.get_read_ready() == 0) return nullptr;
    satcat5::coap::ReadSimple rd(response_all());
    return rd.read_data();
}

bool SimpleClient::response_discard() {
    if (m_rcvd.get_read_ready() == 0) return false;
    m_rcvd.read_finalize();
    return true;
}

void SimpleClient::coap_response(Connection* obj, Reader* msg) {
    // Flush any partial data in the buffer.
    m_rcvd.write_abort();

    // Copy the message contents to the "m_rcvd" buffer.
    // (Include tags of interest. Expand this list as needed.)
    satcat5::coap::Writer wr(&m_rcvd);
    wr.write_header(msg->code(), obj);
    if (msg->format()) {
        wr.write_option(satcat5::coap::OPTION_FORMAT, msg->format().value());
    }
    msg->read_data()->copy_to(wr.write_data());
    wr.write_finalize();
}

satcat5::coap::SimpleClientSpp::SimpleClientSpp(
    satcat5::ccsds_spp::Dispatch* iface, u16 apid)
    : SimpleClient(iface)
    , ManageSpp(this, apid)
{
    // Point-to-point link, no connection setup required.
    set_connection(&m_connection);
}

satcat5::coap::SimpleClientUdp::SimpleClientUdp(
    satcat5::udp::Dispatch* iface)
    : SimpleClient(iface)
    , ManageUdp(this)
    , m_connection(this, iface)
{
    // Nothing else to initialize.
}
