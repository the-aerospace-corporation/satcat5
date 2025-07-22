//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for the CCSDS Space Packet Protocol

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ccsds_spp.h>

using satcat5::net::TYPE_NONE;

// Implement various behaviors using ccsds_spp::Protocol.
class TestSppEcho final : public satcat5::ccsds_spp::Protocol {
public:
    TestSppEcho(satcat5::ccsds_spp::Dispatch* iface, u16 apid)
        : Protocol(iface, apid) {}
    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        auto wr = m_iface->open_reply(TYPE_NONE, src.get_read_ready());
        if (wr) src.copy_and_finalize(wr);
    }
};

class TestSppLog final : public satcat5::ccsds_spp::Protocol {
public:
    TestSppLog(satcat5::ccsds_spp::Dispatch* iface, u16 apid)
        : Protocol(iface, apid) {}
    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        satcat5::log::Log(satcat5::log::INFO, "TestSppLog").write(&src);
    }
};

TEST_CASE("ccsds_spp") {
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap(true);
    pcap.open(
        satcat5::test::sim_filename(__FILE__, "pcap"),
        satcat5::io::LINKTYPE_USER0);

    // Basic tests of the ccsds_spp::Header helper class.
    SECTION("header") {
        satcat5::ccsds_spp::Header uut = {0x087BC908u};
        CHECK(uut.version() == satcat5::ccsds_spp::VERSION_1);
        CHECK_FALSE(uut.type_cmd());
        CHECK(uut.type_tlm());
        CHECK(uut.sec_hdr());
        CHECK(uut.apid() == 123);
        CHECK(uut.seqf() == satcat5::ccsds_spp::SEQF_UNSEG);
        CHECK(uut.seqc() == 0x0908);
    }

    // Test parsing of packets from a byte-stream.
    SECTION("packetizer") {
        log.suppress("packetizer timeout");
        // Test packets:       Header                  Len         Data
        constexpr u8 PKT1[] = {0x00, 0x7B, 0xC9, 0x08, 0x00, 0x01, 0xCA, 0xFE};
        constexpr u8 PKT2[] = {0x00, 0x7B, 0xC9, 0x09, 0x00, 0x05, 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
        constexpr u8 PKT3[] = {0x00, 0x7B, 0xC9};   // Truncated mid-header
        // Add unsegmented test data to the input buffer.
        satcat5::io::StreamBufferHeap src;
        src.write_bytes(sizeof(PKT1), PKT1);
        src.write_bytes(sizeof(PKT2), PKT2);
        src.write_bytes(sizeof(PKT3), PKT3);
        REQUIRE(src.write_finalize());
        // Create unit under test and parse the input data.
        satcat5::ccsds_spp::PacketizerStatic<> uut(&src);
        uut.set_timeout(250);   // Timeout = 250 msec
        timer.sim_wait(500);    // Run simulation.
        CHECK(log.contains("packetizer timeout"));
        // Confirm the contents of the output buffer.
        CHECK(satcat5::test::read(&uut, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::read(&uut, sizeof(PKT2), PKT2));
        CHECK(uut.get_read_ready() == 0);
        // Confirm that accessors aren't returning null-pointers.
        CHECK(uut.bypass());
        CHECK(uut.packet());
        CHECK(uut.listen());
        // Try again, using explicit "reset" rather than timeout..
        src.write_bytes(sizeof(PKT3), PKT3);
        REQUIRE(src.write_finalize());
        timer.sim_wait(1);
        uut.reset();            // Discard partial packet.
        src.write_bytes(sizeof(PKT1), PKT1);
        src.write_bytes(sizeof(PKT2), PKT2);
        REQUIRE(src.write_finalize());
        timer.sim_wait(500);    // Run simulation.
        CHECK(satcat5::test::read(&uut, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::read(&uut, sizeof(PKT2), PKT2));
        CHECK(uut.get_read_ready() == 0);
    }

    // Test ccsds_spp::Dispatch and ccsds_spp::Protocol.
    SECTION("dispatch") {
        log.suppress("TestSppLog");
        // Test packets:       Header                  Len         Data
        constexpr u8 PKT1[] = {0x10, 0x7B, 0xC9, 0x08, 0x00, 0x01, 0xCA, 0xFE};
        constexpr u8 PKT2[] = {0x10, 0x7B, 0xC9, 0x09, 0x00, 0x05, 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
        constexpr u8 PKT3[] = {0x10, 0x7C, 0xC1, 0x23, 0x00, 0x03, 0xAB, 0xAD, 0xD0, 0x0D};
        constexpr u8 ECHO[] = {0x00, 0x7C, 0xC1, 0x23, 0x00, 0x03, 0xAB, 0xAD, 0xD0, 0x0D};
        // Create the simulated network stack.
        satcat5::io::PacketBufferHeap rx, tx;
        satcat5::ccsds_spp::Dispatch spp(&rx, &pcap);
        pcap.set_passthrough(&tx);      // Capture reply packets
        TestSppLog  test1(&spp, 123);   // APID 123 = 0x07B (PKT1, PKT2)
        TestSppEcho test2(&spp, 124);   // APID 124 = 0x07C (PKT3, ECHO)
        // Test the 1st packet: APID 123 = Write to log
        CHECK(satcat5::test::write(&rx, sizeof(PKT1), PKT1));
        timer.sim_wait(100);
        CHECK(log.contains("0xCAFE"));
        // Test the 2nd packet: APID 123 = Write to log
        CHECK(satcat5::test::write(&rx, sizeof(PKT2), PKT2));
        timer.sim_wait(100);
        CHECK(log.contains("0xDEADBEEFCAFE"));
        // Test the 3rd packet: APID 124 = Echo
        // (ECHO is the same as PKT3 except CMD/TLM bit is flipped.)
        CHECK(satcat5::test::write(&rx, sizeof(PKT3), PKT3));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&tx, sizeof(ECHO), ECHO));
    }

    // Test ccsds_spp::Dispatch and ccsds_spp::Address.
    SECTION("address") {
        satcat5::io::Writeable* wr = 0;
        // Test packets:       Header                  Len         Data
        constexpr u8 PKT1[] = {0x10, 0xEA, 0xC0, 0x00, 0x00, 0x04, 't', 'e', 's', 't', '1'};
        constexpr u8 PKT2[] = {0x10, 0xEA, 0xC0, 0x01, 0x00, 0x04, 't', 'e', 's', 't', '2'};
        constexpr u8 PKT3[] = {0x10, 0x7C, 0xC1, 0x23, 0x00, 0x02, 'c', 'm', 'd'};
        constexpr u8 PKT4[] = {0x00, 0x7C, 0xC1, 0x23, 0x00, 0x04, 'r', 'e', 'p', 'l', 'y'};
        // Create the simulated network stack.
        satcat5::io::PacketBufferHeap rx, tx;
        satcat5::ccsds_spp::Dispatch spp(&rx, &pcap);
        satcat5::ccsds_spp::Address uut(&spp);
        pcap.set_passthrough(&tx);  // Capture outgoing packets
        CHECK_FALSE(uut.ready());
        CHECK(uut.iface() == &spp);
        // Test user-specified connection.
        uut.connect(true, 234);     // APID 234 = 0xEA
        CHECK(uut.ready());
        CHECK((wr = uut.open_write(5)));
        CHECK(satcat5::test::write(wr, "test1"));
        CHECK((wr = uut.open_write(5)));
        CHECK(satcat5::test::write(wr, "test2"));
        timer.sim_wait(100);
        CHECK_FALSE(uut.is_multicast());
        CHECK_FALSE(uut.reply_is_multicast());
        CHECK(satcat5::test::read(&tx, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::read(&tx, sizeof(PKT2), PKT2));
        // Close the connection.
        uut.close();
        CHECK_FALSE(uut.ready());
        // Incoming message sets reply address.
        CHECK(satcat5::test::write(&rx, sizeof(PKT3), PKT3));
        timer.sim_wait(100);
        // Test reply-connection mode.
        uut.save_reply_address();   // APID 123 = 0x7C
        CHECK(uut.ready());
        CHECK(uut.matches_reply_address());
        CHECK((wr = uut.open_write(5)));
        CHECK(satcat5::test::write(wr, "reply"));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&tx, sizeof(PKT4), PKT4));
    }

    // Back-to-back test of ReadStream and ToStream.
    SECTION("stream") {
        // Create the simulated network stack.
        satcat5::io::PacketBufferHeap tx, wire, rx;
        satcat5::ccsds_spp::Dispatch spp_tx(nullptr, &pcap);
        pcap.set_passthrough(&wire);  // Capture outgoing packets
        satcat5::ccsds_spp::Dispatch spp_rx(&wire, nullptr);
        // Instantiate the transmitter and receiver.
        satcat5::ccsds_spp::BytesToSpp uut_tx(&tx, &spp_tx, 1234, 16);
        satcat5::ccsds_spp::SppToBytes uut_rx(&spp_rx, &rx, 1234);
        CHECK(uut_tx.strm());
        // Transmit some data.
        CHECK(satcat5::test::write(&tx, "Short message."));
        CHECK(satcat5::test::write(&tx, "Longer message split into multiple packets."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&rx, "Short message."));
        CHECK(satcat5::test::read(&rx, "Longer message s"));
        CHECK(satcat5::test::read(&rx, "plit into multip"));
        CHECK(satcat5::test::read(&rx, "le packets."));
    }
}
