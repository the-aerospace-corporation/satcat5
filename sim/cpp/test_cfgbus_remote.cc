//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for remotely-operated ConfigBus tools
//
// This block tests "eth::ConfigBus" back-to-back with the block that
// accepts those commands, "net::ProtoConfig".  The test includes
// both single-register and bulk read/write operations.
//
// TODO: Test masked writes

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_remote.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/net_cfgbus.h>
#include <satcat5/polling.h>
#include <satcat5/udp_dispatch.h>
#include <vector>

namespace cfg = satcat5::cfg;
namespace eth = satcat5::eth;
namespace ip  = satcat5::ip;
namespace udp = satcat5::udp;

// Helper object that executes a READ on every call to poll::service()
class DelayedRead : satcat5::poll::Always {
public:
    DelayedRead(cfg::ConfigBus* cfg)
        : m_cfg(cfg) {}

    void poll_always() override {
        u32 tmp;
        CHECK(m_cfg->read(42, tmp) == cfg::IOSTATUS_CMDERROR);
    }

    cfg::ConfigBus* const m_cfg;
};

TEST_CASE("cfgbus-remote-eth") {
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimekeeper timer;

    // Memory-mapped buffer is large enough for two full device-pages.
    std::vector<u32> mmap(2*cfg::REGS_PER_DEVICE, 0);
    cfg::ConfigBusMmap cfg(&mmap[0], satcat5::irq::IRQ_NONE);

    // Network communication infrastructure.
    satcat5::test::CrosslinkEth xlink;

    // Shortcuts and aliases:
    auto& c2p(xlink.eth0);      // Inject controller-to-peripheral traffic
    auto& p2c(xlink.eth1);      // Inject peripheral-to-controller traffic

    // Basic network headers.
    const eth::Header HDR_CMD = {
        xlink.MAC1, xlink.MAC0,
        eth::ETYPE_CFGBUS_CMD,
        eth::VTAG_NONE,
    };
    const eth::Header HDR_ACK = {
        xlink.MAC0, xlink.MAC1,
        eth::ETYPE_CFGBUS_ACK,
        eth::VTAG_NONE,
    };

    // Unit under test.
    eth::ConfigBus uut_controller(&xlink.net0, timer.timer());
    eth::ProtoConfig uut_peripheral(&xlink.net1, &cfg);
    uut_controller.connect(xlink.MAC1);

    // Screen for backwards traffic (i.e., CMD from peripheral to controller)
    satcat5::test::LogProtocol screen_p2c(&xlink.net0, eth::ETYPE_CFGBUS_CMD);
    satcat5::test::LogProtocol screen_c2p(&xlink.net1, eth::ETYPE_CFGBUS_ACK);

    // Reference values and test working buffers.
    const u32 REF_ARRAY[] = {1234, 1761, 6890, 1709};
    const unsigned REF_SIZE = sizeof(REF_ARRAY) / sizeof(REF_ARRAY[0]);
    u32 rxtmp, rxval[REF_SIZE];

    SECTION("simple") {
        // Request a few simple writes.
        CHECK(uut_controller.write(1, 1234) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(2, 2345) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(3, 3456) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(4, 4567) == cfg::IOSTATUS_OK);

        // Remote read from the same registers.
        CHECK(uut_controller.read(0, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);  // Initial state
        CHECK(uut_controller.read(1, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 1234);
        CHECK(uut_controller.read(2, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 2345);
        CHECK(uut_controller.read(3, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 3456);
        CHECK(uut_controller.read(4, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 4567);

        // Confirm that the writes were executed.
        CHECK(mmap[0] == 0);  // Initial state
        CHECK(mmap[1] == 1234);
        CHECK(mmap[2] == 2345);
        CHECK(mmap[3] == 3456);
        CHECK(mmap[4] == 4567);
    }

    SECTION("devaddr") {
        // Enable write-timeouts to ensure prompt execution.
        // (Forces UUT to call poll::service() for us.)
        uut_controller.set_timeout_wr(100000);

        // Write/read from the second device page.
        u32 test_reg = cfg::REGS_PER_DEVICE + 7;
        CHECK(uut_controller.write(test_reg+1, 1234) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(test_reg+2, 2345) == cfg::IOSTATUS_OK);

        // Confirm that the writes were executed.
        CHECK(mmap[test_reg+1] == 1234);
        CHECK(mmap[test_reg+2] == 2345);

        // Remote read from the same registers.
        CHECK(uut_controller.read(test_reg+1, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 1234);
        CHECK(uut_controller.read(test_reg+2, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 2345);
    }

    SECTION("array") {
        // Request a sequential array-write.
        CHECK(uut_controller.write_array(42, REF_SIZE, REF_ARRAY) == cfg::IOSTATUS_OK);

        // Read from the same registers and check result.
        CHECK(uut_controller.read_array(42, REF_SIZE, rxval) == cfg::IOSTATUS_OK);
        for (unsigned a = 0 ; a < REF_SIZE ; ++a)
            CHECK(rxval[a] == REF_ARRAY[a]);
    }

    SECTION("repeat") {
        // Request a repeated array-write.
        CHECK(uut_controller.write_repeat(47, REF_SIZE, REF_ARRAY) == cfg::IOSTATUS_OK);

        // Read from the same register several times.
        // (Each result should be the a repeat of the final value.)
        CHECK(uut_controller.read_repeat(47, REF_SIZE, rxval) == cfg::IOSTATUS_OK);
        for (unsigned a = 0 ; a < REF_SIZE ; ++a)
            CHECK(rxval[a] == REF_ARRAY[REF_SIZE-1]);

        // Confirm we didn't write the adjacent registers.
        CHECK(uut_controller.read(46, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);
        CHECK(uut_controller.read(48, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);
    }

    SECTION("array-wrap") {
        // Sequential array-write that exceeds page boundary.
        log.suppress("Bad address");    // Suppress error display
        unsigned reg_first = cfg::REGS_PER_DEVICE - REF_SIZE/2;
        uut_controller.write_array(reg_first, REF_SIZE, REF_ARRAY);

        // Confirm that the entire command was rejected.
        for (unsigned a = 0 ; a < REF_SIZE ; ++a) {
            CHECK(uut_controller.read(reg_first+a, rxtmp) == cfg::IOSTATUS_OK);
            CHECK(rxtmp == 0);
        }
        CHECK(log.contains("Bad address"));
    }

    SECTION("bad-command") {
        // Inject an invalid command (Eth header only, too short).
        c2p.write_obj(HDR_CMD);
        c2p.write_finalize();
        // Confirm processing the packet generates an error message.
        log.suppress("Invalid command");        // Suppress error display...
        satcat5::poll::service_all();
        CHECK(log.contains("Invalid command")); // Confirm an error was logged.
    }

    SECTION("bad-length") {
        // Attempt a bulk-write that's longer than the maximum.
        static const unsigned TEST_LEN = 512;   // API max = 256 words
        std::vector<u32> data(TEST_LEN, 0);
        log.suppress("Bad length");             // Suppress error display...
        CHECK(uut_controller.write_array(42, TEST_LEN, &data[0]) == cfg::IOSTATUS_CMDERROR);
        CHECK(log.contains("Bad length"));
    }

    SECTION("bad-length2") {
        // Inject an invalid write command where the length doesn't match.
        c2p.write_obj(HDR_CMD);
        c2p.write_u8(0x2F);                 // Opcode = write
        c2p.write_u8(2);                    // Length = 3 words (M+1)
        c2p.write_u16(0);                   // Reserved / unused
        c2p.write_u32(0);                   // Address = Don't-care
        c2p.write_u32(1234);                // 4 more bytes (expect 12)
        c2p.write_finalize();
        // Confirm processing the packet generates an error message.
        log.suppress("Bad length");         // Suppress error display...
        satcat5::poll::service_all();
        CHECK(log.contains("Bad length"));
    }

    SECTION("bad-opcode") {
        // Inject a command with an invalid opcode.
        c2p.write_obj(HDR_CMD);
        c2p.write_u8(0x10);                 // Opcode = Undefined
        c2p.write_u8(0);                    // Length = 1 word (M+1)
        c2p.write_u16(0);                   // Reserved / unused
        c2p.write_u32(0);                   // Address = Don't-care
        c2p.write_finalize();
        // Confirm processing the packet generates an error message.
        log.suppress("Bad opcode");         // Suppress error display...
        satcat5::poll::service_all();
        CHECK(log.contains("Bad opcode"));
    }

    SECTION("bad-response") {
        // Inject an invalid response (Eth header only, too short).
        p2c.write_obj(HDR_ACK);
        p2c.write_finalize();
        // ConfigRemote ignores traffic if PENDING flag isn't set, so request
        // a READ operation.  (Fake response above will be read first, produce
        // an error, then successfully process the "real" response.)
        log.suppress("Invalid response");   // Suppress error display...
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);
        CHECK(log.contains("Invalid response"));
    }

    SECTION("bad-response2") {
        // Inject a slightly longer, but still invalid response.
        p2c.write_obj(HDR_ACK);             // Ethernet header
        p2c.write_u32(0x50000100u);         // Opcode = read, length 1, seq 1
        p2c.write_u32(42);                  // Address = 42
        p2c.write_u8(0xDD);                 // 1 more byte (expect 4)
        p2c.write_finalize();
        // As above, request a READ operation to process the fake packet.
        log.suppress("Invalid response");   // Suppress error display...
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_CMDERROR);
        CHECK(rxtmp == 0);
        CHECK(log.contains("Invalid response"));
    }

    SECTION("remote-error") {
        // Inject a response with the error flag set.
        p2c.write_obj(HDR_ACK);
        p2c.write_u32(0x50000100u);         // Opcode = read, length 1, seq 1
        p2c.write_u32(0x00000042u);         // Read address = 0x42
        p2c.write_u32(0x12345678u);         // Read data
        p2c.write_u8(0xFF);                 // Read-error flag
        p2c.write_finalize();
        // As above, request a READ operation to process the fake packet.
        log.suppress("Read error");         // Suppress error display...
        CHECK(uut_controller.read(0x42, rxtmp) == cfg::IOSTATUS_BUSERROR);
        CHECK(rxtmp == 0x12345678);         // Confirm read data
        CHECK(log.contains("Read error"));  // Confirm an error was logged.
    }

    SECTION("nested-read") {
        // Attempt to read while another command is pending.
        log.suppress("Already busy");       // Suppress error display...
        DelayedRead rd(&uut_controller);
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(log.contains("Already busy"));
    }

    SECTION("reply-full") {
        // Fill the reply buffer with junk.
        while (p2c.get_write_space())
            p2c.write_u8(0x42);
        // Request a write; the reply should abort.
        // We expect two errors: "Reply error" and "Timeout".
        // Since we can't easily suppress both, just shutdown completely.
        log.disable();
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_TIMEOUT);
        // The log::ToConsole class only retains the most recent error,
        // which is always "Timeout" in this test scenario.
        CHECK(log.contains("Timeout"));
    }

    SECTION("polling") {
        satcat5::test::MockInterrupt irq(&uut_controller);
        uut_controller.set_irq_polling(5);  // Poll every 5 msec.
        u32 tref = timer.timer()->now();    // Run for 10 msec...
        while (timer.timer()->elapsed_usec(tref) < 10000)
            satcat5::poll::service_all();
        CHECK(irq.count() > 0);             // At least one event?
    }

    SECTION("timeout") {
        // Corrupt outgoing command to force a read-timeout.
        log.suppress("Timeout");            // Suppress error display...
        p2c.write_u32(0);                   // Write without finalize
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_TIMEOUT);
        CHECK(log.contains("Timeout"));     // Confirm an error was logged.
    }
}

TEST_CASE("cfgbus-remote-udp") {
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimekeeper timer;

    // Memory-mapped buffer is large enough for two full device-pages.
    std::vector<u32> mmap(2*cfg::REGS_PER_DEVICE, 0);
    cfg::ConfigBusMmap cfg(&mmap[0], satcat5::irq::IRQ_NONE);

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink;
    auto& c2p = xlink.eth0;     // Alias for controller-to-peripheral traffic
    auto& p2c = xlink.eth1;     // Alias for peripheral-to-controller traffic

    // Basic network headers.
    const eth::Header HDR_CMD = {
        xlink.MAC1, xlink.MAC0,
        eth::ETYPE_CFGBUS_CMD,
        eth::VTAG_NONE,
    };
    const eth::Header HDR_ACK = {
        xlink.MAC0, xlink.MAC1,
        eth::ETYPE_CFGBUS_ACK,
        eth::VTAG_NONE,
    };

    // Unit under test.
    udp::ConfigBus uut_controller(&xlink.net0.m_udp);
    udp::ProtoConfig uut_peripheral(&xlink.net1.m_udp, &cfg);

    // Connect to remote host and run ARP handshake.
    uut_controller.connect(xlink.IP1);
    satcat5::poll::service_all();
    REQUIRE(uut_controller.ready());

    // Reference values and test working buffers.
    u32 rxtmp;

    SECTION("simple") {
        // Request a few simple writes.
        CHECK(uut_controller.write(1, 1234) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(2, 2345) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(3, 3456) == cfg::IOSTATUS_OK);
        CHECK(uut_controller.write(4, 4567) == cfg::IOSTATUS_OK);

        // Remote read from the same registers.
        CHECK(uut_controller.read(0, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);  // Initial state
        CHECK(uut_controller.read(1, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 1234);
        CHECK(uut_controller.read(2, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 2345);
        CHECK(uut_controller.read(3, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 3456);
        CHECK(uut_controller.read(4, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 4567);

        // Confirm that the writes were executed.
        CHECK(mmap[0] == 0);  // Initial state
        CHECK(mmap[1] == 1234);
        CHECK(mmap[2] == 2345);
        CHECK(mmap[3] == 3456);
        CHECK(mmap[4] == 4567);
    }

    SECTION("bad-command") {
        // Inject an invalid command (Incomplete IP header).
        c2p.write_obj(HDR_CMD);
        c2p.write_u32(0x1234);
        c2p.write_finalize();
        // Confirm processing the packet doesn't block subsequent commands.
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);
    }

    SECTION("bad-response") {
        // Inject an invalid response (Incomplete IP header).
        p2c.write_obj(HDR_ACK);
        p2c.write_u32(0x1234);
        p2c.write_finalize();
        // ConfigRemote ignores traffic if PENDING flag isn't set, so request
        // a READ operation.  (Fake response above will be read first, produce
        // an error, then successfully process the "real" response.)
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_OK);
        CHECK(rxtmp == 0);
    }

    SECTION("closed") {
        log.suppress("Connection error");   // Suppress error display...
        uut_controller.close();             // Close UDP connection
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_CMDERROR);
        CHECK(log.contains("Connection error"));
    }

    SECTION("timeout") {
        // Corrupt outgoing command to force a read-timeout.
        log.suppress("Timeout");            // Suppress error display...
        p2c.write_u32(0);                   // Write without finalize
        CHECK(uut_controller.read(42, rxtmp) == cfg::IOSTATUS_TIMEOUT);
        CHECK(log.contains("Timeout"));
    }
}
