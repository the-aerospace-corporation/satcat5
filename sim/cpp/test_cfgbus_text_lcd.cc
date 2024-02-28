//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus Text-LCD driver

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_text_lcd.h>
#include <string>

namespace cfg = satcat5::cfg;

// Define register map (see "cfgbus_uart.vhd")
static const unsigned CFG_DEVADDR = 42;
static const u32 CMD_RESET = (1u << 31);

// Simulate the LCD interface.
class MockLcd : public cfg::ConfigBus {
public:
    std::string get_str() const {return m_rcvd;}

protected:
    cfg::IoStatus read(unsigned regaddr, u32& rdval) override {
        return cfg::IOSTATUS_BUSERROR;  // Reads not supported.
    }

    cfg::IoStatus write(unsigned regaddr, u32 val) override {
        if (val >= CMD_RESET) {
            m_rcvd.clear();
        } else {
            char tmp = (char)(unsigned char)(val & 0xFF);
            m_rcvd += tmp;
        }
        return cfg::IOSTATUS_OK;
    }

    std::string m_rcvd;
};

TEST_CASE("cfgbus_text_lcd") {
    MockLcd lcd;
    cfg::TextLcd uut(&lcd, CFG_DEVADDR);
    cfg::LogToLcd log(&uut);

    SECTION("basic") {
        CHECK(lcd.get_str() == "");
        uut.write("OneString");
        CHECK(lcd.get_str() == "OneString");
        uut.clear();
        CHECK(lcd.get_str() == "");
        uut.write("Two");
        uut.write("Strings");
        CHECK(lcd.get_str() == "TwoStrings");
    }

    SECTION("emoji") {
        // Confirm that we skip over multi-byte UTF-8 codepoints.
        uut.write("Emoji\xF0\x9F\x98\xBA skipped");
        CHECK(lcd.get_str() == "Emoji skipped");
    }

    SECTION("log_debug") {
        satcat5::log::Log(satcat5::log::DEBUG, "Test1");
        CHECK(lcd.get_str() == "Dbg: Test1\n");
    }

    SECTION("log_info") {
        satcat5::log::Log(satcat5::log::INFO, "Test2");
        CHECK(lcd.get_str() == "Inf: Test2\n");
    }

    SECTION("log_warn") {
        satcat5::log::Log(satcat5::log::WARNING, "Test3");
        CHECK(lcd.get_str() == "Wrn: Test3\n");
    }

    SECTION("log_error") {
        satcat5::log::Log(satcat5::log::ERROR, "Test4");
        CHECK(lcd.get_str() == "Err: Test4\n");
    }
}
