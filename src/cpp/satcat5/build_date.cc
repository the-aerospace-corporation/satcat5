//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/build_date.h>

// Convert month to a number:
#define BUILD_MONTH_IS_JAN (__DATE__[0] == 'J' && __DATE__[1] == 'a' && __DATE__[2] == 'n')
#define BUILD_MONTH_IS_FEB (__DATE__[0] == 'F')
#define BUILD_MONTH_IS_MAR (__DATE__[0] == 'M' && __DATE__[1] == 'a' && __DATE__[2] == 'r')
#define BUILD_MONTH_IS_APR (__DATE__[0] == 'A' && __DATE__[1] == 'p')
#define BUILD_MONTH_IS_MAY (__DATE__[0] == 'M' && __DATE__[1] == 'a' && __DATE__[2] == 'y')
#define BUILD_MONTH_IS_JUN (__DATE__[0] == 'J' && __DATE__[1] == 'u' && __DATE__[2] == 'n')
#define BUILD_MONTH_IS_JUL (__DATE__[0] == 'J' && __DATE__[1] == 'u' && __DATE__[2] == 'l')
#define BUILD_MONTH_IS_AUG (__DATE__[0] == 'A' && __DATE__[1] == 'u')
#define BUILD_MONTH_IS_SEP (__DATE__[0] == 'S')
#define BUILD_MONTH_IS_OCT (__DATE__[0] == 'O')
#define BUILD_MONTH_IS_NOV (__DATE__[0] == 'N')
#define BUILD_MONTH_IS_DEC (__DATE__[0] == 'D')

static constexpr unsigned BUILD_MONTH_IDX =
        (BUILD_MONTH_IS_JAN) ? 0x01 :
        (BUILD_MONTH_IS_FEB) ? 0x02 :
        (BUILD_MONTH_IS_MAR) ? 0x03 :
        (BUILD_MONTH_IS_APR) ? 0x04 :
        (BUILD_MONTH_IS_MAY) ? 0x05 :
        (BUILD_MONTH_IS_JUN) ? 0x06 :
        (BUILD_MONTH_IS_JUL) ? 0x07 :
        (BUILD_MONTH_IS_AUG) ? 0x08 :
        (BUILD_MONTH_IS_SEP) ? 0x09 :
        (BUILD_MONTH_IS_OCT) ? 0x0A :
        (BUILD_MONTH_IS_NOV) ? 0x0B :
        (BUILD_MONTH_IS_DEC) ? 0x0C : 0xFF;

static constexpr char space2zero(char c) {
    return (c == ' ') ? '0' : c;
}

static constexpr u32 char2int(char c) {
    return (u32)(space2zero(c) - '0');
}

// Calculate software build date as a 32-bit integer, 0xYYMMDDHH.
u32 satcat5::get_sw_build_code()
{
    constexpr u32 yy = 10 * char2int(__DATE__[9]) + char2int(__DATE__[10]);
    constexpr u32 mm = BUILD_MONTH_IDX;
    constexpr u32 dd = 10 * char2int(__DATE__[4]) + char2int(__DATE__[5]);
    constexpr u32 hh = 10 * char2int(__TIME__[0]) + char2int(__TIME__[1]);
    return (yy << 24) | (mm << 16) | (dd << 8) | hh;
}

// Construct ISO8601 date and time and return pointer to result.
// e.g., "2020-12-31T17:56:09" (Build date is local time, no time-zone identifier.)
static constexpr char iso8601[] = {
    __DATE__[7],    // Year (YYYY)
    __DATE__[8],
    __DATE__[9],
    __DATE__[10],
    '-',            // Month (MM)
    (BUILD_MONTH_IDX / 10) + '0',
    (BUILD_MONTH_IDX % 10) + '0',
    '-',            // Day (DD)
    space2zero(__DATE__[4]),
    __DATE__[5],
    'T',            // Time (HH:MM:SS)
    __TIME__[0],
    __TIME__[1],
    ':',
    __TIME__[3],
    __TIME__[4],
    ':',
    __TIME__[6],
    __TIME__[7],
};

const char* satcat5::get_sw_build_string()
{
    return iso8601;
}
