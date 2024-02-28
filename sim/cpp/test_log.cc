//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the SatCat5 logging system

#include <cstring>
#include <deque>
#include <string>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>

using satcat5::log::Log;
static const s8 LOG_DEBUG       = satcat5::log::DEBUG;
static const s8 LOG_INFO        = satcat5::log::INFO;
static const s8 LOG_WARNING     = satcat5::log::WARNING;
static const s8 LOG_ERROR       = satcat5::log::ERROR;
static const s8 LOG_CRITICAL    = satcat5::log::CRITICAL;

struct LogEvent {
    s8 priority;
    std::string msg;
};

const LogEvent MSG_A = {LOG_DEBUG,      "MsgA = 0x12"};
const LogEvent MSG_B = {LOG_INFO,       "MsgB = 0x1234"};
const LogEvent MSG_C = {LOG_WARNING,    "MsgC = 0x12345678"};
const LogEvent MSG_D = {LOG_ERROR,      "MsgD = 0x123456789ABCDEF0"};
const LogEvent MSG_E = {LOG_CRITICAL,   "MsgE: Test1234 = 0x1234567890ABCDEF"};
const LogEvent MSG_F = {LOG_INFO,       "MsgF: Var1 = 1, Var2 = 0, Var3 = 0x4321"};
const LogEvent MSG_G = {LOG_WARNING,    "MsgG: Var1 = 0, Var2 = 80, Var3 = 4294967295"};
const LogEvent MSG_H = {LOG_WARNING,    "MsgH: Var1 = +0, Var2 = -2147483648, Var3 = +2147483647"};
const LogEvent MSG_I = {LOG_WARNING,    "MsgI = DE:AD:BE:EF:CA:FE = 192.168.1.42"};
const LogEvent MSG_J = {LOG_WARNING,    "MsgJ = 12345678901234567890 = -1234567890123456789 = +1234567890123456789"};
const u8 MSG_D_BYTES[] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};

// Helper class for storing each Log message in a queue, then cross-checking
// the queue contents against an expected reference priority/string.
class MockLog : public satcat5::log::EventHandler {
public:
    void check_next(const LogEvent& ref) {
        REQUIRE_FALSE(m_queue.empty());
        CHECK(ref.priority == m_queue.front().priority);
        CHECK(ref.msg == m_queue.front().msg);
        m_queue.pop_front();
    };

protected:
    void log_event(s8 priority, unsigned nbytes, const char* msg) override {
        CHECK(nbytes == strlen(msg));
        LogEvent tmp = {priority, std::string(msg)};
        m_queue.push_back(tmp);
    }
    std::deque<LogEvent> m_queue;
};

// Helper function for checking LogToWriteable messages.
void check_buff(satcat5::io::Readable* src, const LogEvent& ref) {
    // Discard everything up to the delimiter character.
    // (LogToWriteable adds an emoji prefix followed by TAB.)
    u8 DELIM = (u8)'\t';
    while ((src->get_read_ready() > 0) && (src->read_u8() != DELIM)) {}

    // Read everything after that point and strip newline (CR+LF).
    std::string msg = satcat5::io::read_str(src);
    REQUIRE(msg.size() > 2);
    std::string trim = std::string(msg.begin(), msg.end()-2);

    // The remainder should exactly match the reference string.
    CHECK(trim == ref.msg);
}

TEST_CASE("log") {
    // Start the logging system.
    MockLog log;

    SECTION("basic") {
        // Log a series of fixed messages.
        {Log(LOG_DEBUG,     "MsgA").write((u8)0x12);}
        {Log(LOG_INFO,      "MsgB").write((u16)0x1234);}
        {Log(LOG_WARNING,   "MsgC").write((u32)0x12345678);}
        {Log(LOG_ERROR,     "MsgD").write(MSG_D_BYTES, sizeof(MSG_D_BYTES));}
        {Log(LOG_CRITICAL,  "MsgE", "Test1234").write((u64)0x1234567890ABCDEFull);}

        // Fixed message with a longer chain of writes.
        {Log(LOG_INFO,      "MsgF")
            .write(": Var1").write((bool)true)
            .write(", Var2").write((bool)false)
            .write(", Var3").write((u16)0x4321);}

        // Fixed message with decimal formatting.
        {Log(LOG_WARNING,   "MsgG")
            .write(": Var1").write10(0u)
            .write(", Var2").write10(80u)
            .write(", Var3").write10(UINT32_MAX);}

        // Fixed message with signed decimal formatting.
        {Log(LOG_WARNING,   "MsgH")
            .write(": Var1").write10((s32)0)
            .write(", Var2").write10(INT32_MIN)
            .write(", Var3").write10(INT32_MAX);}

        // Fixed message with MAC and IP addresses.
        {Log(LOG_WARNING,   "MsgI")
            .write(satcat5::eth::MacAddr {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE})
            .write(satcat5::ip::Addr(192, 168, 1, 42));}

        // Test for signed and unsigned 64-bit decimals.
        {Log(LOG_WARNING,   "MsgJ")
            .write10((u64)12345678901234567890ull)
            .write10((s64)-1234567890123456789ll)
            .write10((s64)+1234567890123456789ll);}

        // Check each one against the expected reference.
        log.check_next(MSG_A);
        log.check_next(MSG_B);
        log.check_next(MSG_C);
        log.check_next(MSG_D);
        log.check_next(MSG_E);
        log.check_next(MSG_F);
        log.check_next(MSG_G);
        log.check_next(MSG_H);
        log.check_next(MSG_I);
        log.check_next(MSG_J);
    }

    SECTION("fixed-len") {
        Log(LOG_DEBUG, "MsgA", 4).write((u8)0x12);
        log.check_next(MSG_A);
    }

    SECTION("overflow") {
        // Construct and truncate the reference message.
        LogEvent ref = {LOG_DEBUG, "Overflow: "};
        while (ref.msg.length() < SATCAT5_LOG_MAXLEN)
            ref.msg += "Test";              // Pad to desired length
        ref.msg.resize(SATCAT5_LOG_MAXLEN); // Trim excess, if any

        // Write the same message to the log.
        {
            Log log(LOG_DEBUG, "Overflow: ");
            for (unsigned a = 0 ; a < SATCAT5_LOG_MAXLEN/4 ; ++a)
                log.write("Test");
        }

        // Check for graceful overflow.
        log.check_next(ref);
    }

    SECTION("readable") {
        // Create an io::Readable wrapper for the raw-bytes test message.
        satcat5::io::ArrayRead uut(MSG_D_BYTES, sizeof(MSG_D_BYTES));
        // The resulting message should have exactly the same formatting.
        {Log(LOG_ERROR, "MsgD").write(&uut);}
        log.check_next(MSG_D);
    }
}

TEST_CASE("LogToWriteable") {
    // Unit under test is the LogToWriteable redirect.
    satcat5::io::PacketBufferHeap buff;
    satcat5::log::ToWriteable uut(&buff);

    // Discard newlines written on startup.
    CHECK(buff.get_read_ready() > 0);
    buff.read_finalize();

    // Write a series of fixed messages.
    {Log(LOG_DEBUG).write("MsgA").write((u8)0x12);}
    {Log(LOG_INFO,      "MsgB").write((u16)0x1234);}
    {Log(LOG_WARNING,   "MsgC").write((u32)0x12345678);}
    {Log(LOG_ERROR,     "MsgD").write(MSG_D_BYTES, sizeof(MSG_D_BYTES));}
    {Log(LOG_CRITICAL,  "MsgE", "Test1234").write((u64)0x1234567890ABCDEFull);}

    // Check each one against the expected reference.
    check_buff(&buff, MSG_A);
    check_buff(&buff, MSG_B);
    check_buff(&buff, MSG_C);
    check_buff(&buff, MSG_D);
    check_buff(&buff, MSG_E);
}
