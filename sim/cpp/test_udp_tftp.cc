//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for UDP dispatch and related blocks

#include <hal_posix/file_tftp.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/udp_tftp.h>

// Enable quiet mode for this test (recommended)
static constexpr bool QUIET_MODE = true;

// Thin-wrappers allow access to protected methods and variables.
namespace satcat5 {
    namespace test {
        class TftpClient : public satcat5::udp::TftpClient {
        public:
            using satcat5::udp::TftpClient::TftpClient;
            void send_ack(u16 block_id)
                { m_xfer.send_ack(block_id); }
            void send_data(u16 block_id)
                { m_xfer.send_data(block_id); }
            u16 block_id() const
                { return (u16)m_xfer.progress_blocks(); }
        };

        class TftpServer : public satcat5::udp::TftpServerSimple {
        public:
            using satcat5::udp::TftpServerSimple::TftpServerSimple;
            void send_ack(u16 block_id)
                { m_xfer.send_ack(block_id); }
            void send_data(u16 block_id)
                { m_xfer.send_data(block_id); }
            u16 block_id() const
                { return (u16)m_xfer.progress_blocks(); }
        };
    }
}

// Run simulation until connection is terminated, real-world timeout
// is exceeded, or client reaches an optional progress threshold.
template<class T> void sim_wait(T& obj, u32 num_blocks = UINT32_MAX) {
    satcat5::util::PosixTimer timer;
    const u32 tref_start = timer.now();
    while (obj.active() && obj.progress_blocks() < num_blocks) {
        u32 tmp = tref_start;
        REQUIRE(timer.elapsed_msec(tmp) < 2000);
        satcat5::poll::service();
    }
}

TEST_CASE("UDP-TFTP") {
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways timer;
    auto rng = Catch::rng();

    // Suppress routine notifications.
    if (QUIET_MODE) {
        log.suppress("TFTP: Connected to");
        log.suppress("TFTP: Connection reset by peer");
        log.suppress("TFTP: Transfer completed");
    } else {
        WARN("Section start");
    }

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink;
    const satcat5::ip::Addr IP_SERVER(xlink.IP0);
    const satcat5::ip::Addr IP_CLIENT(xlink.IP1);

    // File I/O buffers.
    satcat5::io::PacketBufferHeap client_tmp;
    satcat5::io::PacketBufferHeap server_src;
    satcat5::io::PacketBufferHeap server_dst;

    // Units under test.
    satcat5::test::TftpServer uut_server(
        &xlink.net0.m_udp, &server_src, &server_dst);
    satcat5::test::TftpClient uut_client(
        &xlink.net1.m_udp);

    // Test specific lengths as corner cases, plus some random options.
    std::vector<unsigned> len_vec;
    len_vec.push_back(1);
    len_vec.push_back(1234);
    len_vec.push_back(2048);
    len_vec.push_back(3456);
    for (unsigned a = 0 ; a < 8 ; ++a)
        len_vec.push_back(1 + rng() % 4000);

    // Basic upload test at each assigned length.
    SECTION("upload_basic") {
        for (auto len = len_vec.begin() ; len != len_vec.end() ; ++len) {
            REQUIRE(satcat5::test::write_random(&client_tmp, *len));
            uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
            sim_wait(uut_client);   // Run to completion...
            CHECK(server_dst.get_read_ready() == *len);
            server_dst.read_finalize();
        }
    }

    // Repeat test with significant packet loss.
    SECTION("upload_lossy") {
        xlink.set_loss_rate(0.2f);
        for (auto len = len_vec.begin() ; len != len_vec.end() ; ++len) {
            REQUIRE(satcat5::test::write_random(&client_tmp, *len));
            uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
            sim_wait(uut_client);   // Run to completion...
            CHECK(server_dst.get_read_ready() == *len);
            server_dst.read_finalize();
        }
    }

    // Basic download test at each assigned length.
    SECTION("download_basic") {
        for (auto len = len_vec.begin() ; len != len_vec.end() ; ++len) {
            REQUIRE(satcat5::test::write_random(&server_src, *len));
            uut_client.begin_download(&client_tmp, IP_SERVER, "test.txt");
            sim_wait(uut_client);   // Run to completion...
            CHECK(client_tmp.get_read_ready() == *len);
            client_tmp.read_finalize();
        }
    }

    // Repeat test with significant packet loss.
    SECTION("download_lossy") {
        xlink.set_loss_rate(0.2f);
        for (auto len = len_vec.begin() ; len != len_vec.end() ; ++len) {
            REQUIRE(satcat5::test::write_random(&server_src, *len));
            uut_client.begin_download(&client_tmp, IP_SERVER, "test.txt");
            sim_wait(uut_client);   // Run to completion...
            CHECK(client_tmp.get_read_ready() == *len);
            client_tmp.read_finalize();
        }
    }

    // Force an out-of-sequence ACK or DATA message.
    SECTION("out_of_sequence_1") {
        if (QUIET_MODE) log.suppress("Illegal TFTP operation");
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then simulate out-of-order message.
        sim_wait(uut_client, 3);
        uut_client.send_data(42);
        // Run simulation to completion, transfer should abort.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 0);
    }

    SECTION("out_of_sequence_2") {
        if (QUIET_MODE) log.suppress("Illegal TFTP operation");
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then simulate out-of-order message.
        sim_wait(uut_client, 3);
        uut_server.send_ack(42);
        // Run simulation to completion, transfer should abort.
        sim_wait(uut_client);   // Run to completion...
        CHECK(server_dst.get_read_ready() == 0);
    }

    // Force retransmission of the current ACK or DATA packet.
    SECTION("retry_ack") {
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then request retransmission.
        sim_wait(uut_client, 3);
        uut_server.send_ack(uut_server.block_id());
        // Run simulation to completion, transfer should succeed.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 3456);
    }

    SECTION("retry_data") {
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then request retransmission.
        sim_wait(uut_client, 3);
        uut_client.send_data(uut_client.block_id());
        // Run simulation to completion, transfer should succeed.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 3456);
    }

    // Force transmission of ACK message in the wrong direction.
    SECTION("wrong_ack") {
        if (QUIET_MODE) log.suppress("Illegal TFTP operation");
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then inject the bad packet.
        sim_wait(uut_client, 3);
        uut_client.send_ack(uut_client.block_id());
        // Run simulation to completion, transfer should abort.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 0);
    }

    // Cut the client-to-server connection after a few packets.
    SECTION("timeout_client") {
        if (QUIET_MODE) log.suppress("Timeout");
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then cut the connection.
        sim_wait(uut_client, 3);
        xlink.eth1.set_loss_rate(1.0f);
        // Run simulation to completion, transfer should abort.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 0);
    }

    // Cut the server-to-client connection after a few packets.
    SECTION("timeout_server") {
        if (QUIET_MODE) log.suppress("Timeout");
        // Set up a transfer long enough to requires many packets.
        REQUIRE(satcat5::test::write_random(&client_tmp, 3456));
        uut_client.begin_upload(&client_tmp, IP_SERVER, "test.txt");
        // Deliver a handful of packets, then cut the connection.
        sim_wait(uut_client, 3);
        xlink.eth0.set_loss_rate(1.0f);
        // Run simulation to completion, transfer should abort.
        sim_wait(uut_client);
        CHECK(server_dst.get_read_ready() == 0);
    }

    // Force use of the "Unknown error" message.
    SECTION("error_unknown") {
        if (QUIET_MODE) log.suppress("TFTP: Unknown error");
        REQUIRE(satcat5::test::write_random(&client_tmp, 123));
        satcat5::udp::TftpTransfer xfer(&xlink.net1.m_udp);
        xfer.request(IP_SERVER, 1, "test.txt"); // 1 = Read request
        xfer.send_error(99);                    // Send an unusual error.
        sim_wait(uut_client);                   // Run to completion.
        CHECK(log.contains("TFTP: Unknown error"));
    }
}

TEST_CASE("FILE-TFTP") {
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways timer;

    // Suppress routine notifications.
    if (QUIET_MODE) {
        log.suppress("TFTP: Connected to");
        log.suppress("TFTP: Connection reset by peer");
        log.suppress("TFTP: Transfer completed");
        log.suppress("TftpServer: Reading");
        log.suppress("TftpServer: Writing");
    } else {
        WARN("Section start");
    }

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink;
    const satcat5::ip::Addr IP_SERVER(xlink.IP0);
    const satcat5::ip::Addr IP_CLIENT(xlink.IP1);

    // Units under test.
    satcat5::udp::TftpServerPosix uut_server(
        &xlink.net0.m_udp, "./simulations");
    satcat5::udp::TftpClientPosix uut_client(
        &xlink.net1.m_udp);

    SECTION("download-then-upload") {
        // Write a small file to the server's work folder.
        satcat5::io::FileWriter write0("simulations/tftp0.dat");
        REQUIRE(satcat5::test::write_random(&write0, 8192));
        // Download the first file from server to the client.
        uut_client.begin_download(IP_SERVER, "simulations/tftp1.dat", "tftp0.dat");
        sim_wait(uut_client);   // Run to completion.
        // Upload the second file from the client to the server.
        uut_client.begin_upload(IP_SERVER, "simulations/tftp1.dat", "tftp2.dat");
        sim_wait(uut_client);   // Run to completion.
        // Confirm the final contents match the original.
        satcat5::io::FileReader read0("simulations/tftp0.dat");
        satcat5::io::FileReader read2("simulations/tftp2.dat");
        CHECK(satcat5::test::read_equal(&read0, &read2));
    }

    SECTION("illegal-path") {
        if (QUIET_MODE) {
            log.suppress("File not found");
            log.suppress("Rejected write");
            log.suppress("Remote error");
        }
        // Attempt to upload a file outside the working folder.
        uut_client.begin_upload(IP_SERVER, "simulations/tftp0.dat", "../hacked.bin");
        sim_wait(uut_client);   // Run to completion.
        CHECK(log.contains("TFTP: Connection reset by peer"));
    }

    SECTION("no-such-file") {
        if (QUIET_MODE) {
            log.suppress("File not found");
            log.suppress("Remote error");
        }
        // Attempt to download a file that doesn't exist.
        uut_client.begin_download(IP_SERVER, "simulations/tftp0.dat", "does_not_exist.txt");
        sim_wait(uut_client);   // Run to completion.
        CHECK(log.contains("TFTP: Connection reset by peer"));
    }
}
