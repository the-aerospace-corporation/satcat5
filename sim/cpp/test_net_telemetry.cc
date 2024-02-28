//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the SatCat5 "Telemetry-Aggregator" system (net_telemetry.h)

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/net_telemetry.h>

using satcat5::io::Readable;
using satcat5::net::TelemetryCbor;
using satcat5::net::TelemetrySource;
using satcat5::net::TelemetryTier;
using satcat5::net::TelemetryAggregator;

// Define numeric keys for the test.
static constexpr u32 KEY_ARRAY_S8       = 0;
static constexpr u32 KEY_ARRAY_U8       = 1;
static constexpr u32 KEY_ARRAY_S16      = 2;
static constexpr u32 KEY_ARRAY_U16      = 3;
static constexpr u32 KEY_ARRAY_S32      = 4;
static constexpr u32 KEY_ARRAY_U32      = 5;
static constexpr u32 KEY_ARRAY_S64      = 6;
static constexpr u32 KEY_ARRAY_U64      = 7;
static constexpr u32 KEY_ARRAY_FLOAT    = 8;
static constexpr u32 KEY_BOOL           = 9;
static constexpr u32 KEY_BYTES          = 10;
static constexpr u32 KEY_FLOAT          = 11;
static constexpr u32 KEY_INT_S8         = 12;
static constexpr u32 KEY_INT_U8         = 13;
static constexpr u32 KEY_INT_S16        = 14;
static constexpr u32 KEY_INT_U16        = 15;
static constexpr u32 KEY_INT_S32        = 16;
static constexpr u32 KEY_INT_U32        = 17;
static constexpr u32 KEY_INT_S64        = 18;
static constexpr u32 KEY_INT_U64        = 19;
static constexpr u32 KEY_NULL           = 20;
static constexpr u32 KEY_STRING         = 21;

// Test message for both UTF-8 strings and byte strings.
const char* TEST_STR = "Hello world!";

// Shortcut function for adding a test array of the given type.
template <class T> void write_array(const TelemetryCbor& cbor, u32 key)
{
    const T temp[4] = {0, 1, 2, 3};
    cbor.add_array(key, 4, temp);
}
template <class T> void write_array(const TelemetryCbor& cbor, const char* key)
{
    const T temp[4] = {0, 1, 2, 3};
    cbor.add_array(key, 4, temp);
}

// Check QCBOR string against the designated constant.
bool string_match(const UsefulBufC& x, const char* y)
{
    const u8* xptr = (const u8*)x.ptr;
    const u8* yptr = (const u8*)y;
    if (x.len != strlen(y)) return false;
    for (size_t n = 0 ; n < x.len ; ++n) {
        if (xptr[n] != yptr[n]) return false;
    }
    return true;
}

// TelemetrySource with three tiers (0, 1, 2)
class TestSource : public TelemetrySource
{
public:
    // Note: All tiers are disabled by default.
    TelemetryTier m_tier0;
    TelemetryTier m_tier1;
    TelemetryTier m_tier2;
    TelemetryTier m_tier3;
    TelemetryTier m_tier4;
    TelemetryTier m_tier5;

    explicit TestSource(TelemetryAggregator* tlm)
        : m_tier0(tlm, this, 0)
        , m_tier1(tlm, this, 1)
        , m_tier2(tlm, this, 2)
        , m_tier3(tlm, this, 3)
        , m_tier4(tlm, this, 4)
        , m_tier5(tlm, this, 5)
    {
        // No other initialization required.
    }

    void telem_event(u32 tier_id, const TelemetryCbor& cbor) override
    {
        if (tier_id == 0) {
            // Tier 0 adds the basic numeric types.
            cbor.add_bool(KEY_BOOL,    true);
            cbor.add_item(KEY_FLOAT,   42.0f);
            cbor.add_item(KEY_INT_S8,  (s8)42);
            cbor.add_item(KEY_INT_U8,  (u8)42);
            cbor.add_item(KEY_INT_S16, (s16)42);
            cbor.add_item(KEY_INT_U16, (u16)42);
            cbor.add_item(KEY_INT_S32, (s32)42);
            cbor.add_item(KEY_INT_U32, (u32)42);
            cbor.add_item(KEY_INT_S64, (s64)42);
            cbor.add_item(KEY_INT_U64, (u64)42);
            cbor.add_null(KEY_NULL);
        } else if (tier_id == 1) {
            // Tier 1 adds both string-like types.
            cbor.add_bytes(KEY_BYTES, strlen(TEST_STR), (const u8*)TEST_STR);
            cbor.add_string(KEY_STRING, TEST_STR);
        } else if (tier_id == 2) {
            // Tier 2 adds the numeric array types.
            write_array<s8>   (cbor, KEY_ARRAY_S8);
            write_array<u8>   (cbor, KEY_ARRAY_U8);
            write_array<s16>  (cbor, KEY_ARRAY_S16);
            write_array<u16>  (cbor, KEY_ARRAY_U16);
            write_array<s32>  (cbor, KEY_ARRAY_S32);
            write_array<u32>  (cbor, KEY_ARRAY_U32);
            write_array<s64>  (cbor, KEY_ARRAY_S64);
            write_array<u64>  (cbor, KEY_ARRAY_U64);
            write_array<float>(cbor, KEY_ARRAY_FLOAT);
        } else if (tier_id == 3) {
            // Tier 0 but with string keys.
            cbor.add_bool("KEY_BOOL",    true);
            cbor.add_item("KEY_FLOAT",   42.0f);
            cbor.add_item("KEY_INT_S8",  (s8)42);
            cbor.add_item("KEY_INT_U8",  (u8)42);
            cbor.add_item("KEY_INT_S16", (s16)42);
            cbor.add_item("KEY_INT_U16", (u16)42);
            cbor.add_item("KEY_INT_S32", (s32)42);
            cbor.add_item("KEY_INT_U32", (u32)42);
            cbor.add_item("KEY_INT_S64", (s64)42);
            cbor.add_item("KEY_INT_U64", (u64)42);
            cbor.add_null("KEY_NULL");
        } else if (tier_id == 4) {
            // Tier 1 but with string keys.
            cbor.add_bytes("KEY_BYTES", strlen(TEST_STR), (const u8*)TEST_STR);
            cbor.add_string("KEY_STRING", TEST_STR);
        } else if (tier_id == 5) {
            // Tier 2 but with string keys.
            write_array<s8>   (cbor, "KEY_ARRAY_S8");
            write_array<u8>   (cbor, "KEY_ARRAY_U8");
            write_array<s16>  (cbor, "KEY_ARRAY_S16");
            write_array<u16>  (cbor, "KEY_ARRAY_U16");
            write_array<s32>  (cbor, "KEY_ARRAY_S32");
            write_array<u32>  (cbor, "KEY_ARRAY_U32");
            write_array<s64>  (cbor, "KEY_ARRAY_S64");
            write_array<u64>  (cbor, "KEY_ARRAY_U64");
            write_array<float>(cbor, "KEY_ARRAY_FLOAT");
        }
    }
};

TEST_CASE("net_telemetry") {
    // Configuration constants.
    constexpr satcat5::eth::MacType TYPE_ETH = {0x4321};
    constexpr satcat5::udp::Port    PORT_UDP = {0x4321};

    // Logging and timing infrastructure.
    satcat5::log::ToConsole logger;
    satcat5::test::TimerAlways timekeeper;
    satcat5::test::FastPosixTimer timer;

    // Network infrastructure for client and server.
    satcat5::test::CrosslinkIp xlink;

    // Client-side telemetry aggregators for each protocol.
    satcat5::eth::Telemetry tx_eth(&xlink.net0.m_eth, TYPE_ETH);
    satcat5::udp::Telemetry tx_udp(&xlink.net0.m_udp, PORT_UDP);

    // Server-side infrastructure records incoming messages.
    satcat5::eth::Socket rx_eth(&xlink.net1.m_eth);
    satcat5::udp::Socket rx_udp(&xlink.net1.m_udp);
    rx_eth.bind(TYPE_ETH);
    rx_udp.bind(PORT_UDP);

    // If all tiers are disabled, then no messages should be sent.
    SECTION("none") {
        TestSource src(&tx_eth);
        timekeeper.sim_wait(1000);
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-0 telemetry.
    SECTION("tier0") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_eth);
        src.m_tier0.set_interval(700);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_eth.get_read_ready() > 0);
        // Inspect the contents of the received message.
        satcat5::test::CborParser rcvd(&rx_eth);
        QCBORItem next;
        next = rcvd.get(KEY_BOOL);
        CHECK(next.uDataType == QCBOR_TYPE_TRUE);
        next = rcvd.get(KEY_FLOAT);
        if (next.uDataType == QCBOR_TYPE_FLOAT) {
            CHECK(next.val.fnum == 42.0f);
        } else {
            CHECK(next.uDataType == QCBOR_TYPE_DOUBLE);
            CHECK(next.val.dfnum == 42.0);
        }
        next = rcvd.get(KEY_INT_S8);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_U8);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_S16);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_U16);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_S32);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_U32);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_S64);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_INT_U64);
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get(KEY_NULL);
        CHECK(next.uDataType == QCBOR_TYPE_NULL);
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-1 telemetry.
    SECTION("tier1") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_udp);
        src.m_tier1.set_interval(800);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_udp.get_read_ready() > 0);
        // Inspect the contents of the received message.
        satcat5::test::CborParser rcvd(&rx_udp);
        QCBORItem next;
        next = rcvd.get(KEY_BYTES);
        CHECK(next.uDataType == QCBOR_TYPE_BYTE_STRING);
        CHECK(string_match(next.val.string, TEST_STR));
        next = rcvd.get(KEY_STRING);
        CHECK(next.uDataType == QCBOR_TYPE_TEXT_STRING);
        CHECK(string_match(next.val.string, TEST_STR));
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-2 telemetry.
    SECTION("tier2") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_udp);
        src.m_tier2.set_interval(900);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_udp.get_read_ready() > 0);
        // Inspect the format of the received message.
        // TODO: Just type and length for now. Inspect array contents?
        satcat5::test::CborParser rcvd(&rx_udp);
        QCBORItem next;
        next = rcvd.get(KEY_ARRAY_S8);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_U8);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_S16);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_U16);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_S32);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_U32);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_S64);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_U64);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get(KEY_ARRAY_FLOAT);
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-3 telemetry.
    SECTION("tier3") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_eth);
        src.m_tier3.set_interval(700);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_eth.get_read_ready() > 0);
        // Inspect the contents of the received message.
        satcat5::test::CborParser rcvd(&rx_eth);
        QCBORItem next;
        next = rcvd.get("KEY_BOOL");
        CHECK(next.uDataType == QCBOR_TYPE_TRUE);
        next = rcvd.get("KEY_FLOAT");
        if (next.uDataType == QCBOR_TYPE_FLOAT) {
            CHECK(next.val.fnum == 42.0f);
        } else {
            CHECK(next.uDataType == QCBOR_TYPE_DOUBLE);
            CHECK(next.val.dfnum == 42.0);
        }
        next = rcvd.get("KEY_INT_S8");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_U8");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_S16");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_U16");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_S32");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_U32");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_S64");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_INT_U64");
        CHECK(next.uDataType == QCBOR_TYPE_INT64);
        CHECK(next.val.int64 == 42);
        next = rcvd.get("KEY_NULL");
        CHECK(next.uDataType == QCBOR_TYPE_NULL);
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-4 telemetry.
    SECTION("tier4") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_udp);
        src.m_tier4.set_interval(800);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_udp.get_read_ready() > 0);
        // Inspect the contents of the received message.
        satcat5::test::CborParser rcvd(&rx_udp);
        QCBORItem next;
        next = rcvd.get("KEY_BYTES");
        CHECK(next.uDataType == QCBOR_TYPE_BYTE_STRING);
        CHECK(string_match(next.val.string, TEST_STR));
        next = rcvd.get("KEY_STRING");
        CHECK(next.uDataType == QCBOR_TYPE_TEXT_STRING);
        CHECK(string_match(next.val.string, TEST_STR));
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Enable and inspect Tier-5 telemetry.
    SECTION("tier5") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_udp);
        src.m_tier5.set_interval(900);
        timekeeper.sim_wait(1000);
        REQUIRE(rx_udp.get_read_ready() > 0);
        // Inspect the format of the received message.
        // TODO: Just type and length for now. Inspect array contents?
        satcat5::test::CborParser rcvd(&rx_udp);
        QCBORItem next;
        next = rcvd.get("KEY_ARRAY_S8");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_U8");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_S16");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_U16");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_S32");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_U32");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_S64");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_U64");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        next = rcvd.get("KEY_ARRAY_FLOAT");
        CHECK(next.uDataType == QCBOR_TYPE_ARRAY);
        CHECK(next.val.uCount == 4);
        // Confirm no other messages were sent.
        CHECK(rx_eth.get_read_ready() == 0);
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Timer-phase should be maintained after re-enabling a tier.
    SECTION("re-enable") {
        // Enable tier and wait long enough for a single message.
        TestSource src(&tx_udp);
        src.m_tier2.set_interval(1000);
        // Confirm the first message goes out at the expected time.
        timekeeper.sim_wait(900);   // T = 900
        CHECK(rx_udp.get_read_ready() == 0);
        timekeeper.sim_wait(200);   // T = 1100
        CHECK(rx_udp.get_read_ready() > 0);
        rx_udp.read_finalize();
        timekeeper.sim_wait(800);   // T = 1900
        CHECK(rx_udp.get_read_ready() == 0);
        // Disable tier just before the second message.
        src.m_tier2.set_interval(0);
        timekeeper.sim_wait(200);   // T = 2100
        CHECK(rx_udp.get_read_ready() == 0);
        // Re-enable tier and confirm expected timing.
        src.m_tier2.set_interval(1000);
        timekeeper.sim_wait(800);   // T = 2900
        CHECK(rx_udp.get_read_ready() == 0);
        timekeeper.sim_wait(200);   // T = 3100
        CHECK(rx_udp.get_read_ready() > 0);
    }

    // Test the concatenated mode.
    SECTION("mode-concat") {
        // Set the source to concatenated mode.
        tx_udp.telem_concat(true);
        // Enable all three tiers at the same rate.
        TestSource src(&tx_udp);
        src.m_tier0.set_interval(200);
        src.m_tier1.set_interval(200);
        src.m_tier2.set_interval(200);
        // Wait for the first polling event.
        timekeeper.sim_wait(250);
        // Confirm we received a single packet.
        CHECK(rx_udp.get_read_ready() > 0);
        rx_udp.read_finalize();
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Test the per-tier mode.
    SECTION("mode-tier") {
        // Set the source to per-tier mode.
        tx_udp.telem_concat(false);
        // Enable all three tiers at the same rate.
        TestSource src(&tx_udp);
        src.m_tier0.set_interval(200);
        src.m_tier1.set_interval(200);
        src.m_tier2.set_interval(200);
        // Wait for the first polling event.
        timekeeper.sim_wait(250);
        // Confirm we received three packets.
        CHECK(rx_udp.get_read_ready() > 0);
        rx_udp.read_finalize();
        CHECK(rx_udp.get_read_ready() > 0);
        rx_udp.read_finalize();
        CHECK(rx_udp.get_read_ready() > 0);
        rx_udp.read_finalize();
        CHECK(rx_udp.get_read_ready() == 0);
    }

    // Adding a very fast tier should auto-update polling interval.
    SECTION("poll-rate") {
        TestSource src(&tx_udp);
        CHECK(tx_udp.timer_interval() > 10);
        src.m_tier0.set_interval(10);
        CHECK(tx_udp.timer_interval() == 10);
        src.m_tier1.set_interval(1);
        CHECK(tx_udp.timer_interval() == 1);
    }
}
