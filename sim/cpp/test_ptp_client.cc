//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "ptp::Client" class

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_stack.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_doppler.h>

using satcat5::ptp::Client;
using satcat5::ptp::ClientMode;
using satcat5::ptp::ClientState;
using satcat5::ptp::DopplerSimple;
using satcat5::test::CountPtpCallback;

// Helper object for testing TLV handlers.
// (Always attach a tag, but don't bother decoding.)
class JunkTlv : public satcat5::ptp::TlvHandler {
public:
    JunkTlv(Client* client) : TlvHandler(client) {}

    unsigned tlv_send(const satcat5::ptp::Header& hdr, satcat5::io::Writeable* wr) {
        static constexpr satcat5::ptp::TlvHeader JUNK_HEADER = {1234, 0, 0, 0};
        if (wr) wr->write_obj(JUNK_HEADER);
        return JUNK_HEADER.len_total();
    }
};

// Helper functions for converting PTP mode or state to a string.
inline static std::string mode2str(ClientMode mode)
    {return std::string(satcat5::ptp::to_string(mode));}
inline static std::string state2str(ClientState state)
    {return std::string(satcat5::ptp::to_string(state));}

TEST_CASE("ptp_strings") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("mode") {
        CHECK(mode2str(ClientMode::DISABLED)    == "Disabled");
        CHECK(mode2str(ClientMode::MASTER_L2)   == "MasterL2");
        CHECK(mode2str(ClientMode::MASTER_L3)   == "MasterL3");
        CHECK(mode2str(ClientMode::SLAVE_ONLY)  == "SlaveOnly");
        CHECK(mode2str(ClientMode::SLAVE_SPTP)  == "SlaveSimple");
        CHECK(mode2str(ClientMode::PASSIVE)     == "Passive");
    }

    SECTION("state") {
        CHECK(state2str(ClientState::DISABLED)  == "Disabled");
        CHECK(state2str(ClientState::LISTENING) == "Listening");
        CHECK(state2str(ClientState::MASTER)    == "Master");
        CHECK(state2str(ClientState::PASSIVE)   == "Passive");
        CHECK(state2str(ClientState::SLAVE)     == "Slave");
    }
}

TEST_CASE("ptp_client") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Two back-to-back PTP clients.
    Client uut0(&xlink.eth0, &xlink.net0.m_ip);
    Client uut1(&xlink.eth1, &xlink.net1.m_ip);
    CountPtpCallback count0(&uut0);
    CountPtpCallback count1(&uut1);
    // Sanity check on initial state.
    CHECK(uut0.get_state() == ClientState::DISABLED);
    CHECK(uut1.get_state() == ClientState::DISABLED);

    // Suppress routine messages.
    log.suppress("Selected master");

    // Basic test in L2 mode (Ethernet)
    SECTION("BasicL2") {
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::SLAVE);
        CHECK(count1.count() > 0);
    }

    // Basic test in L3 mode (UDP)
    SECTION("BasicL3") {
        uut0.set_mode(ClientMode::MASTER_L3);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::SLAVE);
        CHECK(count1.count() > 0);
    }

    // Same as "BasicL2", but we add some TLV handlers.
    SECTION("DopplerTlv") {
        log.suppress("DopplerTlv");
        JunkTlv tlv_junk0(&uut0);
        JunkTlv tlv_junk1(&uut1);
        DopplerSimple tlv_dop0(&uut0);
        DopplerSimple tlv_dop1(&uut1);
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        xlink.timer.sim_wait(2500);
        CHECK(count1.count() > 0);
        CHECK(tlv_dop0.get_velocity() == 0);
        CHECK(tlv_dop1.get_velocity() == 0);
        CHECK(tlv_dop0.get_acceleration() == 0);
        CHECK(tlv_dop1.get_acceleration() == 0);
    }

    // Same as "BasicL2", but the server operates in two-step mode.
    SECTION("TwoStep") {
        xlink.eth0.support_one_step(false);
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::SLAVE);
        CHECK(count1.count() > 0);
    }

    // Basic test for PDelay
    SECTION("PeerToPeer_OneStep")
    {
        uut0.set_mode(ClientMode::PASSIVE);
        uut1.set_mode(ClientMode::PASSIVE);
        CHECK(uut0.get_state() == ClientState::PASSIVE);
        CHECK(uut1.get_state() == ClientState::PASSIVE);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::PASSIVE);
        CHECK(uut1.get_state() == ClientState::PASSIVE);
        CHECK(count0.count() > 0);
        CHECK(count1.count() > 0);
    }

    // Same as "PeerToPeer_OneStep", but the server operates in two-step mode.
    SECTION("PeerToPeer_TwoStep") {
        xlink.eth1.support_one_step(false);
        uut0.set_mode(ClientMode::PASSIVE);
        uut1.set_mode(ClientMode::PASSIVE);
        CHECK(uut0.get_state() == ClientState::PASSIVE);
        CHECK(uut1.get_state() == ClientState::PASSIVE);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::PASSIVE);
        CHECK(uut1.get_state() == ClientState::PASSIVE);
        CHECK(count0.count() > 0);
        CHECK(count1.count() > 0);
    }

    // Test the simple precision time protocol (SPTP) mode.
    SECTION("SPTP") {
        // Test the normal operating condition.
        uut0.set_mode(ClientMode::MASTER_L2);
        uut0.set_sync_rate(-1);     // No SYNC from master
        uut1.set_mode(ClientMode::SLAVE_SPTP);
        uut1.set_sync_rate(3);      // 2^3 = 8 per sec
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::SLAVE);
        CHECK(count1.count() > 0);
        // Drop all packets to force a timeout.
        log.suppress("PtpClient: Connection timeout");
        xlink.set_loss_rate(1);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        CHECK(log.contains("PtpClient: Connection timeout"));
    }

    // Test the methods that set broadcast message rates.
    SECTION("SyncRate") {
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        uut0.set_sync_rate(2);      // 2^2 = 4 per sec
        xlink.timer.sim_wait(2000);
        CHECK(count1.count() >= 7);
        CHECK(count1.count() <= 9);
        uut0.set_sync_rate(3);      // 2^3 = 8 per sec
        count1.count_reset();
        xlink.timer.sim_wait(2000);
        CHECK(count1.count() >= 15);
        CHECK(count1.count() <= 17);
    }

    SECTION("PDelayRate") {
        uut0.set_mode(ClientMode::PASSIVE);
        uut1.set_mode(ClientMode::PASSIVE);
        uut0.set_pdelay_rate(2);    // 2^2 = 4 per 0.9 sec
        xlink.timer.sim_wait(1800);
        CHECK(count0.count() >= 7);
        CHECK(count0.count() <= 9);
        uut0.set_pdelay_rate(3);    // 2^3 = 8 per 0.9 sec
        count0.count_reset();
        xlink.timer.sim_wait(1800);
        CHECK(count0.count() >= 15);
        CHECK(count0.count() <= 17);
    }

    // Test the client's response to an invalid message type.
    SECTION("BadHeader") {
        // SYNC message from Wireshark examples, but with message type mangled.
        // See "ptpv2.pcap" from https://wiki.wireshark.org/SampleCaptures
        log.suppress("PtpClient: Unexpected message");
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        const u8 test_message[] = {
            0x1f, 0x02, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x63, 0xff,
            0xff, 0x00, 0x09, 0xba, 0x00, 0x02, 0x04, 0x3d,
            0x00, 0x00, 0x45, 0xb1, 0x11, 0x49, 0x2e, 0x32,
            0x42, 0x63, 0x00, 0x00
        };
        satcat5::io::ArrayRead ard(test_message, sizeof(test_message));
        satcat5::io::LimitedRead lrd = satcat5::io::LimitedRead(&ard);
        uut1.ptp_rcvd(lrd);
        // Check for the expected error message.
        CHECK(log.contains("PtpClient: Unexpected message"));
    }

    SECTION("BadLength") {
        // A SYNC message, but the header length is mangled.
        log.suppress("PtpClient: Malformed header");
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        // This array is the PTP message only (no Eth or IP header).
        // Call "ptp_rcvd" directly instead of writing to the Ethernet link.
        const u8 test_message[] = {
            0x00, 0x02, 0x42, 0x42, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x63, 0xff,
            0xff, 0x00, 0x09, 0xba, 0x00, 0x02, 0x04, 0x3d,
            0x00, 0x00, 0x45, 0xb1, 0x11, 0x49, 0x2e, 0x32,
            0x42, 0x63, 0x00, 0x00
        };
        satcat5::io::ArrayRead ard(test_message, sizeof(test_message));
        satcat5::io::LimitedRead lrd = satcat5::io::LimitedRead(&ard);
        uut1.ptp_rcvd(lrd);
        // Check for the expected error message.
        CHECK(log.contains("PtpClient: Malformed header"));
    }

    SECTION("BadSeqID") {
        // Send a series of PDELAY_RESPONSE messages with an invalid
        // sequence ID. This should trigger the "cache_miss" event.
        log.suppress("PtpClient: Unmatched SeqID");
        uut0.set_mode(ClientMode::PASSIVE);
        uut1.set_mode(ClientMode::PASSIVE);
        CHECK(uut0.get_state() == ClientState::PASSIVE);
        CHECK(uut1.get_state() == ClientState::PASSIVE);
        const u8 test_message[] = {
            0x13, 0x02, 0x00, 0x36, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x63, 0xff,
            0xff, 0x00, 0x09, 0xba, 0x00, 0x02, 0x04, 0x3d,
            0x00, 0x00, 0x45, 0xb1, 0x11, 0x49, 0xCA, 0xFE,
            0x42, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        };
        for (unsigned a = 0 ; a < 10 ; ++a) {
            satcat5::io::ArrayRead ard(test_message, sizeof(test_message));
            satcat5::io::LimitedRead lrd = satcat5::io::LimitedRead(&ard);
            uut1.ptp_rcvd(lrd);
        }
        // Check for the expected error message.
        CHECK(log.contains("PtpClient: Unmatched SeqID"));
    }

    // Test the slave's ability to detect a lost connection.
    SECTION("Timeout") {
        log.suppress("PtpClient: Connection timeout");
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        xlink.timer.sim_wait(2500);
        // Set for 100% packet drop rate to force timeout
        xlink.set_loss_rate(1);
        xlink.timer.sim_wait(5000);
        CHECK(uut0.get_state() == ClientState::MASTER);
        CHECK(uut1.get_state() == ClientState::LISTENING);
        CHECK(log.contains("PtpClient: Connection timeout"));
    }

    // Test the unicast messaging modes.
    SECTION("UnicastL2") {
        uut0.set_mode(ClientMode::MASTER_L2);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        satcat5::ptp::SyncUnicastL2 unicast(&uut0);
        unicast.connect(xlink.MAC1);
        unicast.timer_every(3);
        xlink.timer.sim_wait(1000);
        CHECK(count1.count() >= 300);
    }

    SECTION("UnicastL3") {
        uut0.set_mode(ClientMode::MASTER_L3);
        uut1.set_mode(ClientMode::SLAVE_ONLY);
        satcat5::ptp::SyncUnicastL3 unicast(&uut0);
        unicast.connect(xlink.IP1);
        unicast.timer_every(3);
        xlink.timer.sim_wait(1000);
        CHECK(count1.count() >= 300);
    }
}
