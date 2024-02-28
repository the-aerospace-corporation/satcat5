//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the SatCat5 "PTP Telemetry" system (ptp_telemetry.h)

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_telemetry.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/udp_socket.h>

using satcat5::io::Readable;
using satcat5::ptp::Client;
using satcat5::ptp::ClientMode;
using satcat5::ptp::Logger;
using satcat5::ptp::Telemetry;
using satcat5::ptp::Time;

class DummyClock : public satcat5::ptp::TrackingClock {
    Time clock_adjust(const Time& amount) {return amount;}
    void clock_rate(s64 offset) {m_offset = offset;}
};

TEST_CASE("ptp_logger") {
    // Basic test infrastructure.
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways sim;

    // Suppress routine log messages.
    log.suppress("PtpClient state");
    log.suppress("Selected master");

    // Set up a network with a PTP master and slave.
    satcat5::test::CrosslinkIp xlink;
    Client ptp0(&xlink.eth0, &xlink.net0.m_ip, ClientMode::MASTER_L2);
    Client ptp1(&xlink.eth1, &xlink.net1.m_ip, ClientMode::SLAVE_ONLY);

    // Link the unit under test to the PTP slave.
    satcat5::ptp::Logger uut(&ptp1);

    // Basic test confirms that a message is generated.
    SECTION("basic") {
        // Run the simulation for a few seconds...
        sim.sim_wait(5000);
        CHECK(log.contains("PtpClient state"));
    }
};

TEST_CASE("ptp_telemetry") {
    // Basic test infrastructure.
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways sim;
    DummyClock clk;

    // Suppress routine log messages.
    log.suppress("Selected master");

    // Set up a network with a PTP master and slave.
    satcat5::test::CrosslinkIp xlink;
    Client ptp0(&xlink.eth0, &xlink.net0.m_ip, ClientMode::MASTER_L2);
    Client ptp1(&xlink.eth1, &xlink.net1.m_ip, ClientMode::SLAVE_ONLY);

    // Link the unit under test to the PTP slave.
    Telemetry uut(&ptp1, &xlink.net1.m_udp, &clk);
    uut.connect(xlink.net0.ipaddr());

    // Create a buffer to receive test telemetry.
    satcat5::udp::Socket rx_udp(&xlink.net0.m_udp);
    rx_udp.bind(satcat5::udp::PORT_CBOR_TLM);

    // Basic test confirms that all expected fields are present.
    SECTION("basic") {
        // Run the simulation for a few seconds...
        uut.set_level(999);
        sim.sim_wait(5000);

        // Parse the first received CBOR message.
        satcat5::test::CborParser rcvd(&rx_udp);
        CHECK(rcvd.get("client_state").uDataType == QCBOR_TYPE_TEXT_STRING);
        CHECK(rcvd.get("mean_path_delay").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("offset_from_master").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("tuning_offset").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t1_secs").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t1_subns").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t2_secs").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t2_subns").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t3_secs").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t3_subns").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t4_secs").uDataType == QCBOR_TYPE_INT64);
        CHECK(rcvd.get("t4_subns").uDataType == QCBOR_TYPE_INT64);
    }
}
