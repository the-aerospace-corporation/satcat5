//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

/// Enable CBOR features?
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_decode.h>
#endif

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
        bool read(satcat5::io::Readable* src,
            const std::string& ref);

        // Write random bytes and finalize.
        bool write_random(satcat5::io::Writeable* dst, unsigned nbytes);

        // Check if two streams are equal.
        bool read_equal(
            satcat5::io::Readable* src1,
            satcat5::io::Readable* src2);

        // A simple CBOR decoder for use in unit tests.
        class CborParser {
        public:
            // Copy received message to local buffer.
            explicit CborParser(satcat5::io::Readable* src, bool verbose=false);

            // Attempt to fetch top-level QCBOR item for the given key.
            #if SATCAT5_CBOR_ENABLE
            QCBORItem get(const char* key) const;
            QCBORItem get(u32 key) const;
            #endif

        protected:
            u8 m_dat[2048];
            unsigned m_len;
        };

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

        // Generate a random block of data that can be read repeatedly.
        class RandomSource : satcat5::io::ReadableRedirect {
        public:
            explicit RandomSource(unsigned len);
            ~RandomSource();
            satcat5::io::Readable* read();
        protected:
            const unsigned m_len;
            u8* const m_buff;
            satcat5::io::ArrayRead m_read;
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
