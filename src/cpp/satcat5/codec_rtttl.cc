//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/codec_rtttl.h>
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

using satcat5::io::Readable;
using satcat5::io::RtttlDecoder;
using satcat5::log::ToBeep;
using satcat5::util::optional;

// Convert BPM to whole-note duration, in milliseconds.
constexpr u32 bpm2msec(unsigned bpm) {
    return u32(60000 / bpm);
}

// Convert musical note (ABCDEFGH) to the offset within an active.
inline optional<int> char2note(char ch) {
    optional<int> result;
    if (ch == 'c' || ch == 'C') result = 0;     // Octave starts with 'C'.
    if (ch == 'd' || ch == 'D') result = 2;
    if (ch == 'e' || ch == 'E') result = 4;
    if (ch == 'f' || ch == 'F') result = 5;
    if (ch == 'g' || ch == 'G') result = 7;
    if (ch == 'a' || ch == 'A') result = 9;
    if (ch == 'b' || ch == 'B') result = 11;    // American notation
    if (ch == 'h' || ch == 'H') result = 11;    // European notation
    if (ch == 'p' || ch == 'P') result = -1;    // Rest / pause
    return result;
}

// Convert musical note to a fixed-point frequency scaling factor.
// (Factor is 2^16 times its frequency in Hz, or zero for silence.)
inline u32 note2freq(unsigned octave, int note) {
    // Table spans one octave: A4 = 440 Hz -> C0 = 16.35 Hz = 1071618 LSBs.
    static const unsigned TABLE[] = {
        1071618, 1135340, 1202851, 1274376, 1350154, 1430439,
        1515497, 1605613, 1701088, 1802240, 1909407, 2022946};
    if (note < 0 || note > 11) return 0;
    return TABLE[note] << octave;
}

// Thin wrapper for a null-terminated string input.
bool RtttlDecoder::play(const char* src) {
    satcat5::io::ArrayRead rd(src, strlen(src));
    return play(&rd);
}

// Reference: Two informal specifications of the RTTTL format.
//  http://merwin.bespin.org/t4a/specs/nokia_rtttl.txt
//  https://www.mobilefish.com/tutorials/rtttl/rtttl_quickguide_specification.html
// Note: This parser does not perform validation, but it has been written
//  defensively to avoid side-effects beyond data written to "m_spkr".
bool RtttlDecoder::play(Readable* src) {
    // Abort if there's already a song in the queue.
    if (m_queue.get_read_ready()) return false;

    // Set internal callback for deferred playback.
    // (Constructor is constexpr, so it's easier to do this now.)
    m_queue.set_callback(this);

    // Discard the "name" section:
    while (src->get_read_ready()) {
        if (src->read_u8() == ':') break;
    }

    // Read and decode the default-value section.
    // Notes with no duration use the default duration.
    // Notes with no octave use the default octave (4/5/6/7).
    // Beats-per-minute (BPM) sets the duration of a whole note.
    m_duration = 4;
    m_octave = 6;
    m_whole_note = bpm2msec(63);
    u32 accum = 0, index = 0;
    char varname = 0;
    while (src->get_read_ready()) {
        // Each segment looks like "o=4," ending in ',' or ':'.
        char ch = char(src->read_u8());
        if (ch == ',' || ch == ':') {
            // Store the variable we just parsed.
            if (varname == 'd') m_duration = accum;
            if (varname == 'o') m_octave = accum;
            if (varname == 'b') m_whole_note = bpm2msec(accum);
            // Reset parser state for next variable.
            accum = 0; index = 0;
            // End of section?
            if (ch == ':') break;
        } else if (ch == ' ' || ch == '\t') {
            // Ignore whitespace.
        } else if (++index == 1) {
            // First character is the variable name.
            varname = ch;
        } else if ('0' <= ch && ch <= '9') {
            // Parse decimal value.
            accum = 10*accum + u32(ch - '0');
        }
    }

    // Parse individual notes until the speaker command queue is full.
    // If there's more, copy it to the internal buffer. (See data_rcvd.)
    while (read_note(src)) {}
    bool done = !src->get_read_ready();
    return m_spkr->write_finalize()
        && (done || src->copy_and_finalize(&m_queue));
}

void RtttlDecoder::data_rcvd(satcat5::io::Readable* src) {
    // RTTTL data is more compact than the unpacked speaker commands,
    // so parse more notes to keep the speaker's working buffer full.
    unsigned count = 0;
    while (read_note(src)) {++count;}
    if (count) m_spkr->write_finalize();
}

bool RtttlDecoder::read_note(Readable* src) {
    // Are we able to proceed with the next note?
    if (src->get_read_ready() == 0) return false;
    if (m_spkr->get_write_space() < 12) return false;

    // Read and decode one note from the comma-delimited list.
    // e.g., "32p,a,a,4a,a,a,4a,a,c6,f.,16g,2a,a#,a#,a#.,16a#"
    // Each command consists of [duration] note [scale] [dot]:
    //  duration = Optional duration. "4" = Quarter note (1/4) etc.
    //  note     = Offset within each octave 'a', 'a#', 'b', etc.
    //             (Sharp notes indicated by '#', no flats.)
    //  scale    = Optional octave number (4/5/6/7)
    //  dot      = Optional '.' indicating 1.5x duration.
    u32 duration = m_duration;  // Default duration, may override later.
    u32 dot = 2;                // Dot factor = 2/2 or 3/2.
    int note = -1;              // Offset within octave, or -1 for pause.
    u32 accum = 0;              // Accumulator for ASCII numbers.
    while (src->get_read_ready()) {
        // Each command ends in a comma or end-of-input.
        char ch = char(src->read_u8());
        if (ch == ',') {
            break;
        } else if ('0' <= ch && ch <= '9') {
            // Parse decimal value.
            accum = 10*accum + unsigned(ch - '0');
        } else if (ch == '#') {
            // Offset sharp notes by +1.
            ++note;
        } else if (ch == '.') {
            // Enable 1.5x duration factor.
            dot = 3;
        } else if (char2note(ch).has_value()) {
            // Store note value (ABCDEFGH or P) and duration, if present.
            note = char2note(ch).value();
            if (accum) duration = accum;
            accum = 0;
        }
    }

    // Calculate duration and frequency.
    u32 octave = accum ? accum : m_octave;
    u16 msec = u16((m_whole_note * dot) / (2 * duration));
    u64 freq = note2freq(octave, note);
    if (freq) {
        // Leave a short gap between notes (15/16 on, 1/16 off)
        // Mostly required for consecutive notes of same pitch.
        static constexpr u64 HALF_LSB = (1ull << 31);
        u32 rate = u32((m_scale * freq + HALF_LSB) >> 32);
        u16 gap = msec / 16;
        m_spkr->write_u16(msec - gap);
        m_spkr->write_u32(rate);
        m_spkr->write_u16(gap);
        m_spkr->write_u32(0);
    } else {
        // No gap required for pauses.
        m_spkr->write_u16(msec);
        m_spkr->write_u32(0);
    }
    return true;
}

static inline const char* beep_code(s8 val) {
    // Choose a sequence based on log-message priority.
    if (val >= satcat5::log::CRITICAL)
        return "sos:d=16,o=6,b=100:f,f,f,p,8f,8f,8f,p,f,f,f";
    else if (val >= satcat5::log::ERROR)
        return "err:d=32,o=6,b=100:f,d,e,d";
    else if (val >= satcat5::log::WARNING)
        return "wrn:d=32,o=6,b=100:f,d,c";
    else if (val >= satcat5::log::INFO)
        return "inf:d=32,o=6,b=100:e,f";
    else
        return nullptr;
}

ToBeep::ToBeep(satcat5::io::RtttlDecoder* codec)
    : m_codec(codec), m_cooldown(500) {}

void ToBeep::log_event(s8 priority, unsigned nbytes, const char* msg) {
    // Ignore messages if we're disabled or still on cooldown.
    if (timer_remaining() || !m_cooldown) return;

    // Otherwise, choose a beep-code and play if applicable.
    const char* beep = beep_code(priority);
    if (beep) {
        m_codec->play(beep);
        timer_once(m_cooldown);
    }
}
