//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Miscellaneous simulation and test helper functions

#pragma once

#include <hal_posix/posix_utils.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/ethernet.h>
#include <satcat5/polling.h>
#include <satcat5/timer.h>

// Macro for making a std::string from a byte-array.
// Note: Only works for locally defined constants.
#define SATCAT5_MAKE_STRING(x) (std::string(x, x + sizeof(x)))

namespace satcat5 {
    namespace test {
        // Write byte array and finalize.
        bool write(satcat5::io::Writeable* dst,
            unsigned nbytes, const u8* data);

        // Compare next frame to reference array.
        // Returns true on exact match, false otherwise.
        // Logs messages indicating each mismatch.
        bool read(satcat5::io::Readable* src,
            unsigned nbytes, const u8* data);

        // Timer object that simply returns a constant.
        // For test purposes, resolution is fixed at 16 ticks per microsecond.
        class ConstantTimer : public satcat5::util::GenericTimer
        {
        public:
            explicit ConstantTimer(u32 val);
            u32 now() override {return m_now;}

            const u32 m_now;
        };

        // Helper objects that count each event type.
        class CountAlways : public poll::Always {
        public:
            CountAlways() : m_count(0) {}
            virtual ~CountAlways() {}
            unsigned count() const {return m_count;}
            void poll_always() override {++m_count;}
        protected:
            unsigned m_count;
        };

        class CountOnDemand : public poll::OnDemand {
        public:
            CountOnDemand() : m_count(0) {}
            virtual ~CountOnDemand() {}
            unsigned count() const {return m_count;}
            void poll_demand() override {++m_count;}
        protected:
            unsigned m_count;
        };

        class CountTimer : public poll::Timer {
        public:
            CountTimer() : m_count(0) {}
            virtual ~CountTimer() {}
            unsigned count() const {return m_count;}
            void timer_event() override {++m_count;}
        protected:
            unsigned m_count;
        };

        // Helper object for counting notifications.
        class IoEventCounter : public satcat5::io::EventListener {
        public:
            IoEventCounter() : m_count(0) {}
            unsigned count() const {return m_count;}
        protected:
            void data_rcvd() {++m_count;}
            unsigned m_count;
        };

        // Log any Ethernet traffic of the designated type.
        class LogProtocol : public satcat5::eth::Protocol {
        public:
            LogProtocol(
                satcat5::eth::Dispatch* dispatch,
                const satcat5::eth::MacType& ethertype);
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
        };

        // Mockup for a memory-mapped ConfigBus.
        // (User should add methods to simulate device operation.)
        class MockConfigBusMmap : public satcat5::cfg::ConfigBusMmap {
        public:
            MockConfigBusMmap();
            // Clear all registers for all devices.
            void clear_all(u32 val = 0);
            // Clear all registers for the specified device-ID.
            void clear_dev(unsigned devaddr, u32 val = 0);
            // Make event-handler accessible (normally private)
            void irq_event();

        protected:
            // Simulated register-map for up to 256 devices.
            u32 m_regs[satcat5::cfg::MAX_TOTAL_REGS];
        };

        // Timekeeper object that always fires a timer interrupt.
        class TimerAlways : public satcat5::poll::Always {
        protected:
            void poll_always() override {
                satcat5::poll::timekeeper.request_poll();
            }
        };
    }
}
