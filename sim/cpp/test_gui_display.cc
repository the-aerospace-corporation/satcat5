//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for the gui::Display and gui::Canvas API

#include <vector>
#include <hal_posix/file_display.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/gui_display.h>

using satcat5::gui::AEROLOGO_ICON16;
using satcat5::gui::AEROLOGO_ICON32;
using satcat5::gui::CAT_SIT;
using satcat5::gui::PAW_ICON8;
using satcat5::gui::SATCAT5_ICON8;
using satcat5::gui::SATCAT5_ICON16;

bool set_default_colors(satcat5::gui::Canvas& uut) {
    return uut.color_fg('*') && uut.color_bg(' ');
}

void test_sequence(satcat5::gui::Canvas& uut) {
    // Sanity check on the display size.
    CHECK(uut.width()  >= 80);
    CHECK(uut.height() >= 40);
    CHECK(set_default_colors(uut));

    // Draw some icons.
    CHECK(uut.cursor(0, 0));
    CHECK(uut.draw_icon(&SATCAT5_ICON8, 2));
    CHECK(uut.cursor(0, 20));
    CHECK(uut.draw_icon(&SATCAT5_ICON16, 1));
    CHECK(uut.cursor(0, 40));
    CHECK(uut.draw_icon(CAT_SIT + 0, 1));
    CHECK(uut.draw_icon(CAT_SIT + 1, 1));
    CHECK(uut.cursor(0, 72));
    CHECK(uut.draw_icon(&PAW_ICON8, 1));
    CHECK(uut.cursor(8, 72));
    CHECK(uut.draw_icon(&PAW_ICON8, 1));

    // Draw a horizontal line.
    CHECK(uut.cursor(17, 0));
    CHECK(uut.draw_rect(2, 80, true));

    // Draw some black-on-white text.
    CHECK(uut.cursor(20, 0));
    CHECK(uut.draw_text("Test msg") == 8);

    // Draw some white-on-black text.
    // (An extra line helps with legibility.)
    CHECK(uut.color_fg(' '));
    CHECK(uut.color_bg('*'));
    CHECK(uut.cursor(29, 0));
    CHECK(uut.draw_rect(1, 64, false));
    CHECK(uut.cursor(30, 0));
    CHECK(uut.draw_text("Inverted") == 8);

    // Scrolling does nothing, but test anyway.
    CHECK(uut.scroll(42));
}

TEST_CASE("GuiDisplay") {
    SATCAT5_TEST_START; // Simulation infrastructure

    // Create the display object under test.
    std::string filename = satcat5::test::sim_filename(__FILE__, "txt");
    satcat5::gui::FileDisplay fd(filename.c_str());

    // Test using buffered mode.
    SECTION("buffered") {
        u8 buffer[2048];
        satcat5::gui::Canvas canvas(&fd, buffer, sizeof(buffer));
        test_sequence(canvas);
        satcat5::poll::service_all();
    }

    // Test using immediate mode.
    SECTION("immediate") {
        satcat5::gui::Canvas canvas(&fd);
        test_sequence(canvas);
    }

    // Test handling of multi-line messages.
    SECTION("multiline") {
        satcat5::gui::Canvas canvas(&fd);
        CHECK(set_default_colors(canvas));
        CHECK(canvas.draw_text("deleteme") == 8);
        CHECK(canvas.cursor(0, 0));
        CHECK(canvas.draw_text("wrap\n\tfor\nnewline") == 24);
    }

    SECTION("wraparound") {
        satcat5::gui::Canvas canvas(&fd);
        CHECK(set_default_colors(canvas));
        CHECK(canvas.draw_text("Long message with wraparound.") == 24);
    }

    // Various tests with larger fonts and icons.
    SECTION("font16") {
        // Make a "font" by repeating a 16x16 icon many times.
        std::vector<satcat5::gui::Icon16x16> vec(128, AEROLOGO_ICON16);
        satcat5::gui::Font16x16 TEST_FONT(vec.data());
        // Use that font to draw on the test canvas.
        satcat5::gui::Canvas canvas(&fd);
        CHECK(set_default_colors(canvas));
        CHECK(canvas.draw_text("AERO", TEST_FONT) == 16);
    }

    SECTION("font32") {
        // Make a "font" by repeating a 32x32 icon many times.
        std::vector<satcat5::gui::Icon32x32> vec(128, AEROLOGO_ICON32);
        satcat5::gui::Font32x32 TEST_FONT(vec.data());
        // Use that font to draw on the test canvas.
        satcat5::gui::Canvas canvas(&fd);
        CHECK(set_default_colors(canvas));
        CHECK(canvas.draw_text("AA", TEST_FONT) == 32);
    }

    SECTION("icon32") {
        // Simple test of a single 32x32 icon.
        satcat5::gui::Canvas canvas(&fd);
        CHECK(set_default_colors(canvas));
        CHECK(canvas.draw_icon(&AEROLOGO_ICON32));
    }

    // Test decoding of an invalid DrawCmd object.
    SECTION("badcmd") {
        satcat5::gui::DrawCmd badcmd(123, 0, {.count = 999});
        CHECK_FALSE(badcmd.rc(42, 42));
        CHECK(badcmd.height() == 0);
        CHECK(badcmd.width() == 0);
    }

    // Test the "clear" command.
    SECTION("clear") {
        satcat5::gui::Canvas canvas(&fd);
        canvas.clear('X');
    }

    // Test the logging functionality.
    SECTION("log") {
        log.disable();  // Disable log-to-console for this test.
        satcat5::gui::Canvas canvas(&fd);
        satcat5::gui::LogToDisplay uut(&canvas, fd.LOG_COLORS);
        satcat5::log::Log(satcat5::log::DEBUG,      "Dbg");
        satcat5::log::Log(satcat5::log::INFO,       "Inf");
        satcat5::log::Log(satcat5::log::WARNING,    "Wrn");
        satcat5::log::Log(satcat5::log::ERROR,      "Err");
    }
}
