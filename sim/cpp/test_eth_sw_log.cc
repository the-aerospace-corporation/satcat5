//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the packet-logging system

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_sw_log.h>

using satcat5::eth::SwitchLogFormatter;
using satcat5::eth::SwitchLogHardware;
using satcat5::eth::SwitchLogMessage;
using satcat5::eth::SwitchLogStats;
using satcat5::eth::SwitchLogWriter;

TEST_CASE("eth_sw_log") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Dummy Ethernet frame header
    constexpr satcat5::eth::Header HDR = {
        satcat5::eth::MACADDR_BROADCAST,
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x56, 0x2F}},
        satcat5::eth::ETYPE_RECOVERY,
        satcat5::eth::VTAG_DEFAULT};

    // Test each of the "reason" messages.
    SECTION("reason") {
        SwitchLogMessage msg;
        msg.init_drop(HDR,  1, SwitchLogMessage::REASON_KEEP);
        CHECK(msg.reason_str() == std::string("N/A"));
        msg.init_drop(HDR,  2, SwitchLogMessage::DROP_OVERFLOW);
        CHECK(msg.reason_str() == std::string("Overflow"));
        msg.init_drop(HDR,  3, SwitchLogMessage::DROP_BADFCS);
        CHECK(msg.reason_str() == std::string("Bad CRC"));
        msg.init_drop(HDR,  4, SwitchLogMessage::DROP_BADFRM);
        CHECK(msg.reason_str() == std::string("Bad header"));
        msg.init_drop(HDR,  5, SwitchLogMessage::DROP_MCTRL);
        CHECK(msg.reason_str() == std::string("Link-local"));
        msg.init_drop(HDR,  6, SwitchLogMessage::DROP_VLAN);
        CHECK(msg.reason_str() == std::string("VLAN policy"));
        msg.init_drop(HDR,  7, SwitchLogMessage::DROP_VRATE);
        CHECK(msg.reason_str() == std::string("Rate-limit"));
        msg.init_drop(HDR,  8, SwitchLogMessage::DROP_PTPERR);
        CHECK(msg.reason_str() == std::string("PTP error"));
        msg.init_drop(HDR,  9, SwitchLogMessage::DROP_NO_ROUTE);
        CHECK(msg.reason_str() == std::string("No route"));
        msg.init_drop(HDR, 10, SwitchLogMessage::DROP_DISABLED);
        CHECK(msg.reason_str() == std::string("Port off"));
        msg.init_drop(HDR, 11, SwitchLogMessage::DROP_UNKNOWN);
        CHECK(msg.reason_str() == std::string("Unknown"));
    }

    // Test the count_keep and count_drop methods.
    SECTION("count") {
        SwitchLogMessage msg;
        msg.init_keep(HDR, 1, 0xCAFE);
        CHECK(msg.reason() == SwitchLogMessage::REASON_KEEP);
        CHECK(msg.count_drop() == 0);
        CHECK(msg.count_keep() == 1);
        msg.init_drop(HDR, 2, SwitchLogMessage::DROP_OVERFLOW);
        CHECK(msg.reason() == SwitchLogMessage::DROP_OVERFLOW);
        CHECK(msg.count_drop() == 1);
        CHECK(msg.count_keep() == 0);
        msg.init_skip(1234, 5678);
        CHECK(msg.reason() == SwitchLogMessage::DROP_UNKNOWN);
        CHECK(msg.count_drop() == 1234);
        CHECK(msg.count_keep() == 5678);
    }

    // Test hardware polling driver.
    SECTION("hardware") {
        // Support systems read and write log data.
        satcat5::io::PacketBufferHeap buf;
        SwitchLogWriter log_wr(&buf);
        SwitchLogFormatter log_fmt(&buf, "PktLog");
        log.suppress("PktLog");
        // Driver under test, using a simulated ConfigBus register.
        satcat5::test::CfgRegister reg;
        SwitchLogHardware log_hw(&log_wr, reg.get_register(0));
        // Load the FIFO register with data, then check output.
        reg.read_default(0);
        reg.read_push(0x80123456u); // Message #1 = KEEP
        reg.read_push(0x8000DEADu);
        reg.read_push(0x80BEEF12u);
        reg.read_push(0x8034DEADu);
        reg.read_push(0x80BEEF43u);
        reg.read_push(0x80210800u);
        reg.read_push(0x800000CAu);
        reg.read_push(0xC0FED00Du);
        timer.sim_wait(100);
        CHECK(log.contains("Delivered to: 0xCAFED00D"));
        reg.read_push(0x80123457u); // Message #2 = SKIP
        reg.read_push(0x80400000u);
        reg.read_push(0x80000000u);
        reg.read_push(0x80000000u);
        reg.read_push(0x80000000u);
        reg.read_push(0x80000000u);
        reg.read_push(0x80000012u);
        reg.read_push(0xC0345678u);
        timer.sim_wait(100);
        CHECK(log.contains("Summary: 22136 delivered, 4660 dropped."));
    }

    // Test the packet-statistics counter.
    SECTION("stats") {
        satcat5::eth::SwitchLogStatsStatic<2> uut;
        SwitchLogMessage msg;
        // Log a few example packets.
        msg.init_keep(HDR, 0, 0xFFFE);  // OK
        uut.log_packet(msg);
        msg.init_drop(HDR, 0, SwitchLogMessage::DROP_OVERFLOW);
        uut.log_packet(msg);
        msg.init_drop(HDR, 1, SwitchLogMessage::DROP_BADFCS);
        uut.log_packet(msg);
        msg.init_drop(HDR, 1, SwitchLogMessage::DROP_BADFRM);
        uut.log_packet(msg);
        msg.init_keep(HDR, 2, 0xFFEF);  // Ignored (Invalid source)
        uut.log_packet(msg);
        // Query packet counters.
        auto port0 = uut.get_port(0);
        CHECK(port0.bcast_frames    == 1);
        CHECK(port0.rcvd_frames     == 1);
        CHECK(port0.sent_frames     == 0);
        CHECK(port0.errct_ovr       == 1);
        CHECK(port0.errct_pkt       == 0);
        CHECK(port0.errct_total     == 1);
        auto port1 = uut.get_port(1);
        CHECK(port1.bcast_frames    == 0);
        CHECK(port1.rcvd_frames     == 0);
        CHECK(port1.sent_frames     == 1);
        CHECK(port1.errct_ovr       == 0);
        CHECK(port1.errct_pkt       == 2);
        CHECK(port1.errct_total     == 2);
        auto port2 = uut.get_port(2);   // Invalid source
        CHECK(port2.bcast_frames    == 0);
        CHECK(port2.rcvd_frames     == 0);
        CHECK(port2.sent_frames     == 0);
        CHECK(port2.errct_ovr       == 0);
        CHECK(port2.errct_pkt       == 0);
        CHECK(port2.errct_total     == 0);
    }

    // Test the "summarize if full" function.
    SECTION("summary") {
        // Create a buffer that fits exactly one message.
        satcat5::io::StreamBufferHeap buf(SwitchLogMessage::LEN_BYTES);
        SwitchLogMessage msg;
        SwitchLogWriter log_wr(&buf);
        SwitchLogFormatter log_fmt(&buf, "PktLog");
        log.suppress("PktLog");
        // Write several messages into the buffer.
        // The first will be saved, the rest will be summarized.
        msg.init_drop(HDR, 2, SwitchLogMessage::DROP_OVERFLOW);
        log_wr.log_packet(msg);     // Accepted
        msg.init_keep(HDR, 2, 1234);
        log_wr.log_packet(msg);     // Create summary
        msg.init_drop(HDR, 2, SwitchLogMessage::DROP_BADFCS);
        log_wr.log_packet(msg);     // Append to summary
        msg.init_skip(3, 1000);
        log_wr.log_packet(msg);     // Append to summary
        timer.sim_wait(100);
        CHECK(log.contains("Summary: 1001 delivered, 4 dropped."));
    }
}
