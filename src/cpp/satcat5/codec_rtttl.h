//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Ring Tone Text Transfer Language (RTTTL) interpreter

#pragma once

#include <satcat5/log.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/polling.h>

// Default buffer size for a queued song.
#ifndef SATCAT5_RTTTL_BUFFER
#define SATCAT5_RTTTL_BUFFER 256
#endif

namespace satcat5 {
    namespace io {
        //! Ring Tone Text Transfer Language (RTTTL) interpreter.
        //! RTTTL is a compact plaintext format for monophonic music,
        //! originally used for Nokia mobile-phone ringtones, e.g.:
        //! ```
        //! Beethoven:d=4,o=5,b=160:c,e,c,g,c,c6,8b,8a,8g,8a,8g,8f,8e,8f,8e,8d,c,e,g,e,c6,g.
        //! ```
        //! See also: [This interactive RTTTL editor](https://rtttl.skully.tech/).
        //!
        //! This class accepts RTTTL input and emits "notes" as duration and
        //! rate pairs, encoded as consecutive u16 + u32 values.  Duration is
        //! measured in milliseconds. Rate zero indicates silence; otherwise it
        //! sets phase-increment per clock cycle as used in "cfgbus_piezo.vhd",
        //! i.e., `rate = round(2^32 * freq_hz / refclk_hz)`.
        class RtttlDecoder : public satcat5::io::EventListener {
        public:
            //! Link this decoder to a playback device.
            //! \param spkr Is the buffer for the playback device.
            //! \param refclk_hz Is the reference clock frequency, in Hz.
            constexpr RtttlDecoder(satcat5::io::Writeable* spkr, u64 refclk_hz)
                : m_spkr(spkr)
                , m_scale((1ull << 48) / refclk_hz)
                , m_duration(0)
                , m_octave(0)
                , m_whole_note(0)
                , m_queue(m_raw, sizeof(m_raw), 0)
                , m_raw{}
                {} // Nothing else to initialize

            //! If playback is in progress, halt immediately.
            inline void flush()
                { m_queue.clear(); }

            //! Decode and play the specified song (string input).
            //! \returns True if the entire sequence was enqueued for playback.
            bool play(const char* src);

            //! Decode and play the specified song (stream input).
            //! \returns True if the entire sequence was enqueued for playback.
            bool play(satcat5::io::Readable* src);

        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            bool read_note(satcat5::io::Readable* src);

            satcat5::io::Writeable* const m_spkr;   //!< Output device
            const u64 m_scale;                      //!< Frequency conversion
            u32 m_duration;                         //!< Default note duration
            u32 m_octave;                           //!< Default octave
            u32 m_whole_note;                       //!< Duration of whole note
            satcat5::io::PacketBuffer m_queue;      //!< Playback queue
            u8 m_raw[SATCAT5_RTTTL_BUFFER];         //!< Raw working buffer
        };

        //! Example: Opening bars from Beethoven's 5th symphony.
        constexpr char RTTTL_BEETHOVEN[] =
            "5thSymph:d=16,o=5,b=100:"\
            "g,g,g,4d#,4p,f,f,f,4d,4p,g,g,g,d#,g#,g#,g#,g,d#6,d#6,d#6,4c6,8p";

        //! Example: Truncated "Haunted House" from Wikipedia.
        constexpr char RTTTL_HAUNTED[] =
            "HauntHouse: d=4,o=5,b=108: 2a4, 2e, 2d#, 2b4, 2a4, 2c, 2d, 2a#4, 2e.";

        //! Example: The classic Nokia jingle.
        constexpr char RTTTL_NOKIA[] =
            "Nokia:d=4,o=5,b=225:8e6,8d6,f#,g#,8c#6,8b,d,e,8b,8a,c#,e,2a";

        //! Example: A famous song by Rick Astley.
        constexpr char RTTTL_RICK[] =
            "Rick:d=8,o=4,b=225:g,a,c5,a,4e5,p,4e5,p,4.d5,4.p,g,a,c5,a,"\
            "4d5,p,4d5,p,4c5,b,4.a,g,a,c5,a,2c5,4d5,4b,4a,4.g,2d5,2.c5";

        //! Example: A happy startup jingle.
        constexpr char RTTTL_STARTUP[] =
            "Circles:d=16,o=6,b=180:a,a5,c,e,8a";
    }

    namespace log {
        //! Respond to log messages by playing a few musical notes.
        //! This class implements the log::EventHandler API, so it receives
        //! notifications for each Log message.  For each such notification,
        //! it plays a short sequence of notes based on the message priority.
        //! A short cooldown mitigates excessive noise from rapid logging.
        class ToBeep
            : public satcat5::log::EventHandler
            , protected satcat5::poll::Timer {
        public:
            //! Constructor binds this object to an RTTTL decoder.
            explicit ToBeep(satcat5::io::RtttlDecoder* codec);

            //! Callback for each formatted Log message.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

            //! Set minimum time between beeps.
            //! Cooldown of zero disables beeps entirely.
            inline void set_cooldown(unsigned msec) { m_cooldown = msec; }

        protected:
            //! End-of-cooldown callback does nothing.
            void timer_event() override {}

            // Internal state.
            satcat5::io::RtttlDecoder* const m_codec;
            unsigned m_cooldown;
            bool m_enable;
        };
    }
}
