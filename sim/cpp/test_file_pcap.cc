//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Test cases for reading and writing packet capture files (PCAP, PCAPNG)
//

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/datetime.h>

using satcat5::io::ReadPcap;
using satcat5::io::WritePcap;

// Define a few short "packets" for the tests below.
static const unsigned PKT_COUNT = 2;
static const std::string PKT_DATA[PKT_COUNT] = {
    "Is this question an Ethernet packet? Maybe.",
    "SatCat5 is FPGA gateware that implements a low-power, mixed-media Ethernet switch.",
};

TEST_CASE("File-PCAP") {
    // Test infrastructure.
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimer timer;
    satcat5::datetime::Clock clock(&timer);

    // Scan through several known-good example files.
    SECTION("Read-Examples") {
        // Each example contains the same sequence of packets.
        const std::string filename = GENERATE(
            "example1.pcap", "example2.pcapng", "example3.pcapng");
        ReadPcap uut(filename.c_str());

        // For each packet, count stats and discard data.
        unsigned pkt_count = 0;
        unsigned pkt_bytes = 0;
        while (uut.get_read_ready()) {
            pkt_count += 1;
            pkt_bytes += uut.get_read_ready();
            uut.read_finalize();
        }
        CHECK(pkt_count == 53);
        CHECK(pkt_bytes == 3202);
    }

    // Write capture files in each mode and verify in loopback.
    SECTION("Write-Loopback") {
        // Test each mode...
        const std::string filename = GENERATE(
            "simulations/pcap1.pcap",
            "simulations/pcap2.pcapng");
        bool mode_ng = filename.find(".pcapng") != std::string::npos;

        // Write a handful of test packets to the unit under test.
        WritePcap uut_wr(&clock, filename.c_str(), mode_ng);
        for (unsigned a = 0 ; a < PKT_COUNT ; ++a) {
            uut_wr.write_str(PKT_DATA[a].c_str());
            CHECK(uut_wr.write_finalize());
        }
        uut_wr.close();

        // Verify that we can successfully read back the same data.
        ReadPcap uut_rd(filename.c_str());
        for (unsigned a = 0 ; a < PKT_COUNT ; ++a) {
            CHECK(satcat5::test::read(&uut_rd, PKT_DATA[a]));
        }
        CHECK(uut_rd.get_read_ready() == 0);
    }
}
