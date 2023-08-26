//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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
#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/ethernet.h>
#include <satcat5/ip_stack.h>
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

        class CountArpResponse : public satcat5::eth::ArpListener {
        public:
            explicit CountArpResponse(satcat5::ip::Dispatch* iface)
                : m_arp(&iface->m_arp), m_count(0) {m_arp->add(this);}
            ~CountArpResponse() {m_arp->remove(this);}
            unsigned count() const {return m_count;}
        protected:
            void arp_event(const satcat5::eth::MacAddr& mac, const satcat5::ip::Addr& ip) override {++m_count;}
            void gateway_change(const satcat5::ip::Addr& dstaddr, const satcat5::ip::Addr& gateway) override {}
            satcat5::eth::ProtoArp* const m_arp;
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

        class CountPingResponse : public satcat5::ip::PingListener {
        public:
            explicit CountPingResponse(satcat5::ip::Dispatch* iface)
                : m_icmp(&iface->m_icmp), m_count(0) {m_icmp->add(this);}
            ~CountPingResponse() {m_icmp->remove(this);}
            unsigned count() const {return m_count;}
        protected:
            void ping_event(const satcat5::ip::Addr& from, u32 elapsed_usec) {++m_count;}
            satcat5::ip::ProtoIcmp* const m_icmp;
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

        // Dummy implementation of net::Address that writes data to a buffer.
        class DebugAddress : public satcat5::net::Address
        {
            // Received-data buffer is directly accessible.
            satcat5::io::PacketBufferHeap m_rx;

            // Implement the minimum required API.
            satcat5::net::Dispatch* iface() const override
                { return 0; }
            satcat5::io::Writeable* open_write(unsigned len) override
                { m_rx.write_abort(); return &m_rx; }
            void close() override
                { m_rx.write_finalize(); }
            bool ready() const
                { return true; }
        };

        // Accelerated version of PosixTimer is 256x real-time.
        class FastPosixTimer : public satcat5::util::GenericTimer {
        public:
            FastPosixTimer() : satcat5::util::GenericTimer(1) {}
            u32 now() override {return m_timer.now() << 8;}
        protected:
            satcat5::util::PosixTimer m_timer;
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

        // Mockup for a ConfigBus interrupt register.
        class MockInterrupt : public satcat5::cfg::Interrupt {
        public:
            // No associated register, assumes interrupt has fired.
            explicit MockInterrupt(satcat5::cfg::ConfigBus* cfg);

            // Poll the designated register to see if interrupt flag is set.
            MockInterrupt(satcat5::cfg::ConfigBus* cfg, unsigned regaddr);

            // Number of callback events for this interrupt?
            unsigned count() const {return m_count;}

            // Trigger a virtual interrupt.
            void fire();

        protected:
            void irq_event() override {++m_count;}

            satcat5::cfg::ConfigBus* const m_cfg;
            unsigned m_count;
            unsigned m_regaddr;
        };

        // Measure various statistics of a discrete-time series.
        class Statistics {
        public:
            Statistics();
            void add(double x);     // Add a new data point
            double mean() const;    // Mean of all data points
            double msq() const;     // Mean-square
            double rms() const;     // Root-mean-square
            double std() const;     // Standard deviation
            double var() const;     // Variance
            double min() const;     // Minimum over all inputs
            double max() const;     // Maximum over all inputs
        protected:
            unsigned m_count;       // Number of data points
            double m_sum;           // Sum of inputs
            double m_sumsq;         // Sum of squares
            double m_min;           // Running minimum
            double m_max;           // Running maximum
        };

        // Timekeeper object that always fires a timer interrupt.
        class TimerAlways : public satcat5::poll::Always {
        public:
            void sim_wait(unsigned dly_msec);
        protected:
            void poll_always() override {
                satcat5::poll::timekeeper.request_poll();
            }
        };
    }
}
