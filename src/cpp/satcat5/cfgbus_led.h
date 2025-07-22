//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! ConfigBus-controlled PWM LEDs and animation functions.
//!
//!\details
//! The "cfgbus_led" block defines an array of PWM LEDs, where the average
//! brightness of each LED can be varied from 0-255.  This file defines a
//! driver for direct control of that block, as well as various animation
//! controllers for controlling one LED or a group of LEDs.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/list.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace cfg {
        //! Basic LED array with direct user control of each intensity value.
        //! \see cfgbus_led.h.
        class LedArray {
        public:
            //! Link this controller to a bank of PWM LEDs.
            LedArray(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned count);

            //! Number of LEDs in this bank?
            unsigned count() const {return m_count;}

            //! Get brightness of the Nth LED.
            u8 get(unsigned idx);
            //! Set brightness of the Nth LED.
            void set(unsigned idx, u8 brt);

        protected:
            satcat5::cfg::Register m_reg;   //!< Base control register
            const unsigned m_count;         //!< Number of LEDs
        };

        //! Single-LED controller for a network-activity light.
        //! Instantiate an LedActivity object for each LED, then control
        //! the group using an LedActivityCtrl object. \see cfgbus_led.h.
        class LedActivity {
        public:
            //! Link to a specific LED.
            LedActivity(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr,
                unsigned stats_idx, u8 brt = 128);

            //! Callback object for LedActivityCtrl.
            //! Parent refreshes network statistics @ ~30 Hz and calls
            //! this method to update each activity LED.
            void update(satcat5::cfg::NetworkStats* stats);

        private:
            friend satcat5::util::ListCore;
            satcat5::cfg::Register m_reg;   // Base control register
            const unsigned m_stats_idx;     // NetworkStats index
            const u8 m_brt;                 // Max LED brightness
            u8 m_state;                     // Recent activity state
            LedActivity* m_next;            // Linked list of other LEDs
        };

        //! Coordinate multiple LedActivity objects.
        class LedActivityCtrl : public satcat5::poll::Timer {
        public:
            //! Link this controller to an activity source.
            explicit LedActivityCtrl(
                satcat5::cfg::NetworkStats* stats,
                unsigned delay_msec = 33);  // Default speed = 30 fps

            //! Add an LedActivity object to this group.
            inline void add(LedActivity* led) {m_list.add(led);}

        private:
            void timer_event() override;    // Timer event handler

            satcat5::cfg::NetworkStats* const m_stats;
            satcat5::util::List<LedActivity> m_list;
        };

        //! Single-LED controller for a "Breathing" or "Wave" pattern.
        //! Instantiate an LedWave object for each LED, then control
        //! the group using an LedWaveCtrl object. \see cfgbus_led.h.
        class LedWave {
        public:
            //! Link to a specific LED.
            LedWave(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr, u8 m_brt = 128);

            //! Callback object for LedWaveCtrl.
            void update(u32 incr);

        private:
            friend satcat5::util::ListCore;
            satcat5::cfg::Register m_reg;   // Base control register
            const u8 m_brt;                 // Max LED brightness
            u32 m_phase;                    // Animation phase counter
            LedWave* m_next;                // Linked list of other LEDs
        };

        //! Coordinate multiple LedWave objects.
        class LedWaveCtrl : public satcat5::poll::Timer {
        public:
            LedWaveCtrl();

            //! Add an LedActivity object to this group.
            inline void add(LedWave* led) {m_list.add(led);}

            //! Animation controls.
            void start(unsigned delay=20);  //!< Start animation (default 50 fps)
            void stop();                    //!< Stop wave animation

        private:
            void timer_event() override;    // Timer event handler

            satcat5::util::List<LedWave> m_list;
            u32 m_incr;                     // Animation speed
        };
    }
}
