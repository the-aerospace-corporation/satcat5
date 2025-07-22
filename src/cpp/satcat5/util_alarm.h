//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Alarm system with multiple duration/threshold limits.

#pragma once

#include <satcat5/timeref.h>

// Maximum number of threshold/duration pairs.
#ifndef SATCAT5_MAX_ALARMS
#define SATCAT5_MAX_ALARMS 3
#endif

namespace satcat5 {
    namespace util {
        //! Alarm system with multiple duration/threshold limits.
        //! This alarm system accepts a series of measurements over time,
        //! comparing each new measurement against a set of duration and
        //! threshold limits (i.e., value exceeds X for more than Y msec).
        //! For example, a set of duration/threshold limits can be set
        //! fast & slow maximum current thresholds for a current-breaker.
        class Alarm {
        public:
            //! Constructor sets the default instantaneous limit.
            Alarm();

            //! Clear all duration/threshold limits.
            void limit_clear();

            //! Add a new duration/threshold pair.
            //! An alarm sounds if time-series measurements to `next` exceed
            //! the provided value for at least the provided duration.
            //!
            //! For example, a limit of (0, 20) sounds the alarm instantly
            //! if the input is ever 21 or higher.  A limit of (10, 15)
            //! sounds the alarm if incoming measurements are 16 or higher
            //! for at least 10 consecutive milliseconds.
            //!
            //! \param duration Maximum safe duration in milliseconds.
            //! \param value Maximum safe value in arbitrary units.
            //! \return True if the duration/threshold was added successfully.
            bool limit_add(u32 duration, u32 value);

            //! Push a new time-series measurement.
            //! This method returns a sample-by-sample alarm flag.  Exceeding
            //! any duration/threshold limit also sets the sticky alarm flag.
            //! \param value New measurement value in arbitrary units.
            //! \return True if the new value exceeds a duration/threshold limit.
            bool push_next(u32 value);

            //! Clear the `sticky_alarm` flag.
            inline void sticky_clear() { m_sticky = 0; }

            //! Has an alarm been triggered?
            //! The sticky alarm flag is set by the `push` method and remains
            //! set until the user explicitly calls `sticky_clear`.
            inline bool sticky_alarm() const { return m_sticky > 0; }

            //! Query the most recent value provided to `push_next`.
            inline u32 value() const { return m_value; }

        protected:
            satcat5::util::TimeVal m_tref;          //!< Previous measurement timestamp.
            u32 m_alarms;                           //!< Number of active limit pairs.
            u32 m_sticky;                           //!< Sticky alarm flag.
            u32 m_value;                            //!< Most recent measurement value.
            u32 m_max_time[SATCAT5_MAX_ALARMS];     //!< Per-limit duration threshold.
            u32 m_max_value[SATCAT5_MAX_ALARMS];    //!< Per-limit value threshold.
            u32 m_exceeded[SATCAT5_MAX_ALARMS];     //!< Per-limit exceeded counter
        };
    }
}
