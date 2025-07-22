//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "coap::ProxyResource" and "coap::ProxyServer" classes.

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/coap_proxy.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/port_adapter.h>
#include <satcat5/utils.h>

using satcat5::udp::PORT_COAP;
namespace coap = satcat5::coap;

// Test server for sending and forwarding queries.
class TestServer : public coap::ProxyServer {
public:
    // Attach this server to the designated network interface.
    TestServer(satcat5::udp::Dispatch* udp)
        : ProxyServer(udp, PORT_COAP), m_client(nullptr), m_errct(0) {}

    unsigned errct() const {return m_errct;}

    // Handler for incoming responses.
    void local_response(coap::Connection* obj, coap::Reader* msg) override {
        if (msg->code().is_error()) ++m_errct;
        msg->read_data()->copy_and_finalize(&m_rx);
    }

    satcat5::io::Readable* rx() {
        return &m_rx;
    }

    // Send a request to another server.
    bool send_request(coap::Code code, satcat5::ip::Addr dst, const char* uri, const char* msg) {
        // Can we reuse the existing connection?  Open or reopen if needed.
        bool reuse = m_client && m_client->is_match_addr(dst, PORT_COAP);
        if (m_client && !reuse) m_client->close();
        if (!reuse) m_client = connect(dst, PORT_COAP);

        // Create a new request message.
        coap::Writer hdr(m_client->open_request());
        if (!hdr.ready()) return false;

        // Write CoAP message header and contents.
        hdr.write_header(coap::TYPE_CON, code, next_msgid(), next_token());
        hdr.write_uri(coap::OPTION_URI_PATH, uri);
        hdr.write_option(coap::OPTION_FORMAT, coap::FORMAT_TEXT);
        satcat5::io::Writeable* dat = hdr.write_data();
        dat->write_str(msg);
        return dat->write_finalize();
    }

protected:
    satcat5::io::PacketBufferHeap m_rx; // Buffer for incoming responses
    coap::ConnectionUdp* m_client;      // Active client (for connection reuse)
    unsigned m_errct;                   // Count error response codes
};

TEST_CASE("coap_proxy") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}},
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};
    const satcat5::ip::Addr
        IP0(192, 168, 0, 0),
        IP1(192, 168, 0, 1),
        IP2(192, 168, 0, 2),
        IP3(192, 168, 0, 3);

    // Create three network endpoints with CoAP proxy servers.
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    TestServer coap0(nic0.udp());
    TestServer coap1(nic1.udp());
    TestServer coap2(nic2.udp());

    // Attach the endpoints to a three-port Ethernet switch.
    satcat5::eth::SwitchCoreStatic<> uut;
    satcat5::eth::SwitchCache<> cache(&uut);
    uut.set_debug(&pcap);
    satcat5::port::MailAdapter port0(&uut, &nic0, &nic0);
    satcat5::port::MailAdapter port1(&uut, &nic1, &nic1);
    satcat5::port::MailAdapter port2(&uut, &nic2, &nic2);

    // Create the "real" resources located on each server.
    coap::ResourceEcho echo0(&coap0, "echo0");
    coap::ResourceEcho echo1(&coap1, "echo1");
    coap::ResourceEcho echo2(&coap2, "echo2");

    // Create the proxy resources forwarding to other servers.
    // (Note that "IP3/echo3" resource doesn't actually exist.)
    coap::ProxyResource proxy01(&coap0, "echo1", IP1, PORT_COAP);
    coap::ProxyResource proxy02(&coap0, "echo2", IP2, PORT_COAP);
    coap::ProxyResource proxy03(&coap0, "echo3", IP3, PORT_COAP);
    coap::ProxyResource proxy10(&coap1, "echo0", IP0, PORT_COAP);
    coap::ProxyResource proxy12(&coap1, "echo2", IP2, PORT_COAP);
    coap::ProxyResource proxy13(&coap1, "echo3", IP3, PORT_COAP);
    coap::ProxyResource proxy20(&coap2, "echo0", IP0, PORT_COAP);
    coap::ProxyResource proxy21(&coap2, "echo1", IP1, PORT_COAP);
    coap::ProxyResource proxy23(&coap2, "echo3", IP3, PORT_COAP);

    // Query from coap0 to coap1/echo1.
    SECTION("basic_local") {
        CHECK(coap0.send_request(coap::CODE_GET, IP1, "echo1", "Direct echo"));
        timer.sim_wait(1000);
        CHECK(satcat5::test::read(coap0.rx(), "Direct echo"));
    }

    // Query from coap0 to coap1/echo2. (Proxy reply.)
    SECTION("basic_proxy") {
        CHECK(coap0.send_request(coap::CODE_GET, IP1, "echo2", "Proxy echo"));
        timer.sim_wait(1000);
        CHECK(satcat5::test::read(coap0.rx(), "Proxy echo"));
    }

    // Proxy to undefined methods PUT, POST, and DELETE.
    SECTION("proxy_put") {
        CHECK(coap0.send_request(coap::CODE_PUT, IP1, "echo2", "Proxy put"));
        timer.sim_wait(1000);
        CHECK(coap0.errct() == 1);
    }
    SECTION("proxy_post") {
        CHECK(coap0.send_request(coap::CODE_POST, IP1, "echo2", "Proxy post"));
        timer.sim_wait(1000);
        CHECK(coap0.errct() == 1);
    }
    SECTION("proxy_delete") {
        CHECK(coap0.send_request(coap::CODE_DELETE, IP1, "echo2", "Proxy delete"));
        timer.sim_wait(1000);
        CHECK(coap0.errct() == 1);
    }

    // Proxy to an undefined endpoint (should timeout).
    SECTION("proxy_timeout") {
        CHECK(coap0.send_request(coap::CODE_PUT, IP1, "echo3", "IP3 where are you?"));
        timer.sim_wait(30000);
        CHECK(coap0.errct() == 1);
        CHECK(satcat5::test::read(coap0.rx(), "Proxy timeout"));
    }

    // Test connection-reuse over multiple consecutive queries.
    SECTION("reuse") {
        // 1st request: Client 0 -> Proxy 1 -> Server 2
        CHECK(coap0.send_request(coap::CODE_GET, IP1, "echo2", "Proxy echo #1"));
        timer.sim_wait(1000);   // Wait for response (new connections)
        CHECK(satcat5::test::read(coap0.rx(), "Proxy echo #1"));
        // 2nd request: Client 0 -> Proxy 1 -> Server 2
        CHECK(coap0.send_request(coap::CODE_GET, IP1, "echo2", "Proxy echo #2"));
        timer.sim_wait(1000);   // Wait for response (reuse connections)
        CHECK(satcat5::test::read(coap0.rx(), "Proxy echo #2"));
        // 3rd request: Client 2 -> Proxy 1 -> Server 0
        timer.sim_wait(20000);  // Wait for cached-response timeout
        CHECK(coap2.send_request(coap::CODE_GET, IP1, "echo0", "Proxy echo #3"));
        timer.sim_wait(1000);   // Wait for resonse (new connections)
        CHECK(satcat5::test::read(coap2.rx(), "Proxy echo #3"));
    }
}
