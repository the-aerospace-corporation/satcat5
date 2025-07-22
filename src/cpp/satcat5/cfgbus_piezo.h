//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus-controlled piezoelectric buzzer

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/polling.h>

// Default buffer size for queued notes.
#ifndef SATCAT5_PIEZO_BUFFER
#define SATCAT5_PIEZO_BUFFER 32
#endif

namespace satcat5 {
    namespace cfg {
        //! ConfigBus-controlled piezoelectric buzzer.
        //! This class controls the HDL block defined in "cfgbus_piezo.vhd".
        //! It plays back a queue of musical notes, where each note is defined
        //! by a paired duration and frequency. \see io::RtttlDecoder
        class Piezo
            : public satcat5::io::EventListener
            , public satcat5::poll::Timer
        {
        public:
            //! Link this object to the "cfgbus_piezo" control register.
            Piezo(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr = 0);

            //! Silence playback and flush internal queue.
            void flush();

            //! Access the internal playback buffer for writing commands.
            //! Each single-note command is a duration (u16, milliseconds)
            //! followed by a frequency (u32, see "cfgbus_piezo.vhd").
            inline satcat5::io::Writeable* queue() { return &m_queue; }

        protected:
            // Internal event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void timer_event() override;
            void wait();

            // Internal state
            satcat5::cfg::Register m_reg;           //!< Base control register
            satcat5::io::PacketBuffer m_queue;      //!< Playback queue
            u8 m_raw[SATCAT5_PIEZO_BUFFER];         //!< Raw working buffer
        };
    }
}
