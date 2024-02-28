//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Test cases for AeroFTP client and server
//

#include <hal_posix/file_aeroftp.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/net_aeroftp.h>
#include <satcat5/utils.h>

// Enable quiet mode for this test (recommended)
static constexpr bool QUIET_MODE = true;

// Sequential counter ensures unique File ID numbers for each test.
static u32 next_file_id()
{
    static u32 file_id = 0;
    return ++file_id;
}

// Check output from AeroFTP server.
static bool file_test(u32 file_id, satcat5::io::Readable* ref)
{
    // Calculate expected length including zero-pad.
    unsigned len_ref = ref->get_read_ready();
    unsigned len_pad = 4 * satcat5::util::div_ceil(len_ref, 4u);

    // Load the file from the working folder.
    char filename[256];
    snprintf(filename, sizeof(filename),
        "simulations/file_%08u.data", file_id);
    satcat5::io::FileReader rd_file(filename);

    // Check the length matches expectations, including zero-pad.
    if (rd_file.get_read_ready() != len_pad) {
        printf("WARNING: Length mismatch: Got %u, expected %u\n",
            rd_file.get_read_ready(), len_pad);
        return false;
    }

    // Confirm contents match the reference, ignoring trailing zeros.
    satcat5::io::LimitedRead rd_trim(&rd_file, len_ref);
    return satcat5::test::read_equal(&rd_trim, ref);
}

TEST_CASE("Net-AeroFTP") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways timer;
    satcat5::test::CrosslinkIp xlink;

    // Quiet mode suppresses various routine messages.
    if (QUIET_MODE) {
        log.suppress("AeroFTP: Already complete");
        log.suppress("AeroFTP: Completed file");
        log.suppress("AeroFTP: Continued file");
        log.suppress("AeroFTP: Length mismatch");
        log.suppress("AeroFTP: New file");
        log.suppress("AeroFTP: Restart file");
        log.suppress("AeroFTP: Transmission complete");
    }

    // Units under test.
    satcat5::eth::AeroFtpClient client_eth(&xlink.net0.m_eth);
    satcat5::udp::AeroFtpClient client_udp(&xlink.net0.m_udp);
    satcat5::eth::AeroFtpServer server_eth("simulations", &xlink.net1.m_eth);
    satcat5::udp::AeroFtpServer server_udp("simulations", &xlink.net1.m_udp);

    // Configure both clients.
    client_eth.connect(xlink.net1.macaddr());
    client_udp.connect(xlink.net1.ipaddr());
    client_udp.throttle(2);

    // Servers should always start from scratch.
    // (Otherwise, stale files in the working folder affect test results.)
    server_eth.resume(false);
    server_udp.resume(false);

    // Randomized test files of various lengths...
    u32 ref_len = GENERATE(4, 1024, 2044, 2047, 23456);
    satcat5::test::RandomSource ref(ref_len);

    // Basic upload test.
    SECTION("eth_basic") {
        u32 file_id = next_file_id();
        // Transmit the entire file.
        REQUIRE(client_eth.send(file_id, ref.read()));
        timer.sim_wait(5000);
        // Confirm file received.
        CHECK(server_eth.done(file_id));
        CHECK(file_test(file_id, ref.read()));
        // Restart transmission but close abruptly.
        CHECK(client_eth.send(file_id, ref.read()));
        timer.sim_wait(5);
        client_eth.close();
        CHECK(server_eth.done(file_id));
    }

    SECTION("udp_basic") {
        u32 file_id = next_file_id();
        // Transmit the entire file.
        REQUIRE(client_udp.send(file_id, ref.read()));
        timer.sim_wait(5000);
        // Confirm file received.
        CHECK(server_udp.done(file_id));
        CHECK(file_test(file_id, ref.read()));
    }

    // Repeat test with significant packet loss.
    SECTION("eth_lossy") {
        u32 file_id = next_file_id();
        // First pass sends the entire file with random loss.
        xlink.set_loss_rate(0.2f);
        REQUIRE(client_eth.send(file_id, ref.read()));
        timer.sim_wait(5000);
        // Second pass sends the missing blocks.
        xlink.set_loss_rate(0.0f);
        auto retry = server_eth.missing_blocks(file_id);
        CHECK(client_eth.send(file_id, ref.read(), retry));
        // Confirm file received.
        CHECK(server_eth.done(file_id));
        CHECK(file_test(file_id, ref.read()));
    }

    SECTION("udp_lossy") {
        u32 file_id = next_file_id();
        // First pass sends the entire file with random loss.
        xlink.set_loss_rate(0.2f);
        REQUIRE(client_udp.send(file_id, ref.read()));
        timer.sim_wait(5000);
        // Second pass sends the missing blocks.
        xlink.set_loss_rate(0.0f);
        auto retry = server_udp.missing_blocks(file_id);
        CHECK(client_udp.send(file_id, ref.read(), retry));
        // Confirm file received.
        CHECK(server_udp.done(file_id));
        CHECK(file_test(file_id, ref.read()));
    }
}
