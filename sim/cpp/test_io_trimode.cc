//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Configurable port with Raw, CCSDS, or SLIP mode.

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_socket.h>
#include <satcat5/io_trimode.h>

using satcat5::eth::ETYPE_CBOR_TLM;
using satcat5::io::TriMode;

// Use a specific APID for all tests in this file.
static const u16 APID_STRM = 1234;

// Make a valid SPP frame containing a string.
static std::string make_spp(u16 seq, const char* str) {
    // Create the SPP header.
    satcat5::ccsds_spp::Header hdr;
    hdr.set(false, APID_STRM, seq);
    u16 len = strlen(str);
    REQUIRE(len > 0);
    // Write header and contents to a temporary buffer.
    satcat5::io::PacketBufferHeap tmp;
    tmp.write_u32(hdr.value);
    tmp.write_u16(len - 1);
    tmp.write_bytes(len, str);
    tmp.write_finalize();
    // Copy the complete SPP into an STL string.
    return satcat5::io::read_str(&tmp);
}

TEST_CASE("io_trimode") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::StreamBufferHeap loopback;
    satcat5::io::WritePcap pcap;

    // Network infrastructure.
    // Note: Omit the MAC-cache plugin and default to broadcast mode.
    // (The switch would otherwise be confused by loopback packets.)
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}};
    const satcat5::ip::Addr IP0(192, 168, 0, 1);
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::eth::SwitchCoreStatic<> eth;
    satcat5::port::MailAdapter port0(&eth, &nic0, &nic0);

    // Attach packet-capture to the loopback buffer.
    pcap.open(
        satcat5::test::sim_filename(__FILE__, "pcap"),
        satcat5::io::LINKTYPE_USER0);
    pcap.set_passthrough(&loopback);

    // Unit under test is configured in self-loopback.
    TriMode uut(&eth, &loopback, &pcap, APID_STRM);

    // Test mode: port = OFF
    SECTION("Mode-OFF") {
        uut.configure(TriMode::Port::OFF);
        CHECK(satcat5::test::write(&uut, "In OFF mode, all inputs are discarded."));
        timer.sim_wait(100);
        CHECK(uut.get_read_ready() == 0);
    }

    // Test mode: port = RAW, stream = RAW
    SECTION("Mode-RAW-RAW") {
        uut.configure(TriMode::Port::RAW, TriMode::Stream::RAW, TriMode::Stream::RAW);
        CHECK(satcat5::test::write(&uut, "Short raw message."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, "Short raw message."));
    }

    // Test mode: port = RAW, stream = SPP
    SECTION("Mode-RAW-SPP") {
        uut.configure(TriMode::Port::RAW, TriMode::Stream::SPP, TriMode::Stream::SPP);
        CHECK(satcat5::test::write(&uut, make_spp(0, "SPP headers removed and replaced.")));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, make_spp(0, "SPP headers removed and replaced.")));
    }

    // Test mode: port = AOS, stream = RAW
    SECTION("Mode-AOS-RAW") {
        uut.configure(TriMode::Port::AOS, TriMode::Stream::RAW, TriMode::Stream::RAW);
        CHECK(satcat5::test::write(&uut, "AOS carrying B_PDU stream."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, "AOS carrying B_PDU stream."));
        CHECK(uut.frame_count() == 1);
    }

    // Test mode: port = AOS, stream = SPP
    SECTION("Mode-AOS-SPP") {
        uut.configure(TriMode::Port::AOS, TriMode::Stream::SPP, TriMode::Stream::SPP);
        CHECK(satcat5::test::write(&uut, make_spp(0, "AOS carrying SPP over M_PDU.")));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, make_spp(0, "AOS carrying SPP over M_PDU.")));
        CHECK(uut.frame_count() == 1);
    }

    // Test mode: port = SPP, stream = RAW
    SECTION("Mode-SPP-RAW") {
        uut.configure(TriMode::Port::SPP, TriMode::Stream::RAW, TriMode::Stream::RAW);
        CHECK(satcat5::test::write(&uut, "Single SPP packet, but TriMode adds headers."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, "Single SPP packet, but TriMode adds headers."));
    }

    // Test mode: port = SPP, stream = SPP
    SECTION("Mode-SPP-SPP") {
        uut.configure(TriMode::Port::SPP, TriMode::Stream::SPP, TriMode::Stream::SPP);
        CHECK(satcat5::test::write(&uut, make_spp(0, "Single SPP packet.")));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&uut, make_spp(0, "Single SPP packet.")));
    }

    // Test mode: port = SLIP
    SECTION("Mode-SLIP") {
        uut.configure(TriMode::Port::SLIP);
        CHECK(uut.eth_port()->port_enabled());
        satcat5::eth::Socket sock0(nic0.eth());
        sock0.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&uut, "Streaming inputs are discarded."));
        CHECK(satcat5::test::write(&sock0, "Packet via Ethernet switch."));
        timer.sim_wait(100);
        CHECK(uut.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock0, "Packet via Ethernet switch."));
        CHECK(uut.frame_count() == 1);
    }

    // Sanity check: No unexpected errors.
    CHECK(uut.error_count() == 0);
}
