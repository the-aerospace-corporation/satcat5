//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for the SatCat5 "Telemetry-Aggregator" system (net_telemetry.h)

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <qcbor/qcbor_decode.h>
#include <satcat5/ip_stack.h>
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
    // Note: All three tiers are disabled by default.
    TelemetryTier m_tier0;
    TelemetryTier m_tier1;
    TelemetryTier m_tier2;

    explicit TestSource(TelemetryAggregator* tlm)
        : m_tier0(tlm, this, 0)
        , m_tier1(tlm, this, 1)
        , m_tier2(tlm, this, 2)
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
        } else {
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
        }
    }
};

// Helper object for parsing a CBOR key/value dictionary.
class TestParser {
public:
    // Copy received message to local buffer.
    explicit TestParser(Readable* src, bool verbose=false)
        : m_len(src->get_read_ready())
    {
        REQUIRE(m_len > 0);
        REQUIRE(m_len <= sizeof(m_dat));
        src->read_bytes(m_len, m_dat);
        src->read_finalize();
        if (verbose) {
            satcat5::log::Log(satcat5::log::DEBUG, "Raw CBOR").write(m_dat, m_len);
        }
    }

    // Fetch QCBOR item for the given key.
    // (Iterating over the entire dictionary each time is inefficient
    //  but simple, and we don't need high performance for this test.)
    QCBORItem get(u32 key_req) const {
        // A null item for indicating decoder errors.
        static const QCBORItem ITEM_ERROR = {
            QCBOR_TYPE_NONE,    // Type (value)
            QCBOR_TYPE_NONE,    // Type (label)
            0, 0, 0, 0,         // Metadata
            {.int64=0},         // Value
            {.int64=0},         // Label
            0,                  // Tags
        };

        // Open a QCBOR parser object.
        QCBORDecodeContext cbor;
        QCBORDecode_Init(&cbor, {m_dat, m_len}, QCBOR_DECODE_MODE_NORMAL);

        // First item should be the top-level dictionary.
        QCBORItem item;
        int errcode = QCBORDecode_GetNext(&cbor, &item);
        if (errcode || item.uDataType != QCBOR_TYPE_MAP) return ITEM_ERROR;

        // Read key/value pairs until we find the desired key.
        // (Or, if no match is found, return ITEM_ERROR.)
        u32 key_rcvd = 0;
        while (1) {
            errcode = QCBORDecode_GetNext(&cbor, &item);    // Read key + value
            if (errcode) return ITEM_ERROR;
            if (item.uNestingLevel > 1) continue;
            if (item.uLabelType != QCBOR_TYPE_INT64) return ITEM_ERROR;
            errcode = QCBOR_Int64ToUInt32(item.label.int64, &key_rcvd);
            if (errcode) return ITEM_ERROR;
            if (key_req == key_rcvd) return item;           // Key match?
        }
    }
private:
    u8 m_dat[2048];
    unsigned m_len;
};

TEST_CASE("net_telemetry") {
    // Configuration constants.
    constexpr satcat5::eth::MacAddr MAC_CLIENT = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    constexpr satcat5::eth::MacAddr MAC_SERVER = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    constexpr satcat5::ip::Addr IP_CLIENT(192, 168, 0, 11);
    constexpr satcat5::ip::Addr IP_SERVER(192, 168, 0, 22);
    constexpr satcat5::eth::MacType TYPE_ETH = {0x4321};
    constexpr satcat5::udp::Port    PORT_UDP = {0x4321};

    // Logging and timing infrastructure.
    satcat5::log::ToConsole logger;
    satcat5::test::TimerAlways timekeeper;
    satcat5::test::FastPosixTimer timer;

    // Network infrastructure for client and server.
    satcat5::io::PacketBufferHeap c2s, s2c;
    satcat5::ip::Stack client(MAC_CLIENT, IP_CLIENT, &c2s, &s2c, &timer);
    satcat5::ip::Stack server(MAC_SERVER, IP_SERVER, &s2c, &c2s, &timer);

    // Client-side telemetry aggregators for each protocol.
    satcat5::eth::Telemetry tx_eth(&client.m_eth, TYPE_ETH);
    satcat5::udp::Telemetry tx_udp(&client.m_udp, PORT_UDP);

    // Server-side infrastructure records incoming messages.
    satcat5::eth::Socket rx_eth(&server.m_eth);
    satcat5::udp::Socket rx_udp(&server.m_udp);
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
        TestParser rcvd(&rx_eth);
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
        TestParser rcvd(&rx_udp);
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
        TestParser rcvd(&rx_udp);
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
