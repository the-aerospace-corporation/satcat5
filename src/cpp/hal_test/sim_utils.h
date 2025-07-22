//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Miscellaneous simulation and test helper functions.
//!
//!\details
//! This file contains a variety of "small" utilities used in simulations
//! and unit tests.  Anything that requires more than a few lines of code
//! should generally be moved into its own file.

#pragma once

#include <hal_posix/posix_utils.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/ethernet.h>
#include <satcat5/interrupts.h>
#include <satcat5/ip_stack.h>
#include <satcat5/log.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_source.h>
#include <satcat5/timeref.h>
#include <string>

// Enable CBOR features?
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_decode.h>
#endif

//! Macro for making a std::string from a byte-array.
//! Note: Only works for locally defined constants.
#define SATCAT5_MAKE_STRING(x) (std::string(x, x + sizeof(x)))

//! Boilerplate for configuring each unit test.
//! Includes a hard-reset of SatCat5 global variables and enables log::ToConsole.
//! An error in this macro indicates the *previous* test didn't exit cleanly.
#define SATCAT5_TEST_START \
    CHECK(satcat5::irq::pre_test_reset()); \
    CHECK(satcat5::log::pre_test_reset()); \
    CHECK(satcat5::poll::pre_test_reset()); \
    CHECK(satcat5::test::pre_test_reset()); \
    satcat5::log::ToConsole log;

namespace satcat5 {
    namespace test {
        //! Reset the global PRNG state used for rand_*(), below.
        bool pre_test_reset();

        //! Reproducible PRNG used for unit tests.
        //!@{
        u8  rand_u8();
        u32 rand_u32();
        u64 rand_u64();
        //!@}

        //! Generate a unique filename for storing unit-test results.
        //! In most cases, the "pre" argument should be set to __FILE__.
        //! Output is "simulations/[pre]_[###].[ext]".
        //! (Where ### is a sequential counter for each unique "pre" value.)
        std::string sim_filename(const char* pre, const char* ext);

        //! Write byte array and finalize.
        //!@{
        bool write(satcat5::io::Writeable* dst,
            unsigned nbytes, const u8* data);
        bool write(satcat5::io::Writeable* dst,
            const std::string& dat);
        //!@}

        //! Compare next frame to reference array.
        //! Returns true on exact match, false otherwise.
        //! Logs messages indicating each mismatch.
        //!@{
        bool read(satcat5::io::Readable* src,
            unsigned nbytes, const u8* data);
        bool read(satcat5::io::Readable* src,
            const std::string& ref);
        bool read(satcat5::io::ArrayRead src,
            const std::string& ref);
        //!@}

        //! Write random bytes, without finalizing. \see write_random_final
        void write_random_bytes(satcat5::io::Writeable* dst, unsigned nbytes);
        //! Write random bytes and finalize. \see write_random_bytes
        bool write_random_final(satcat5::io::Writeable* dst, unsigned nbytes);

        //! Check if two streams are equal.
        bool read_equal(
            satcat5::io::Readable* src1,
            satcat5::io::Readable* src2);

        //! A simple CBOR decoder for use in unit tests.
        class CborParser {
        public:
            //! Copy received message to local buffer.
            explicit CborParser(satcat5::io::Readable* src, bool verbose=false);

            //! Attempt to fetch top-level QCBOR item for the given key.
            //!@{
            #if SATCAT5_CBOR_ENABLE
            QCBORItem get(const char* key) const;
            QCBORItem get(u32 key) const;
            #endif
            //!@}

        protected:
            u8 m_dat[2048];
            unsigned m_len;
        };

        //! Base object for counting specific callback or event types.
        //! Provides accessors for the internal counter `m_count`.  The child
        //! object inherits from the callback type of interest and manipulates
        //! the counter directly.
        class CountHelper {
        public:
            //! Returns the current counter value.
            unsigned count() const {return m_count;}
            //! Reset the counter to zero.
            void count_reset() {m_count = 0;}
        protected:
            //! Constructor is only accessible to the child object.
            CountHelper() : m_count(0) {}
            ~CountHelper() {}
            unsigned m_count;
        };

        //! Count calls to `poll_always()`. \see poll::Always
        class CountAlways final
            : public CountHelper, public satcat5::poll::Always {
        public:
            CountAlways() {}
            void poll_always() override {++m_count;}
        };

        //! Count calls to `arp_event()`. \see eth::ArpListener
        class CountArpResponse final
            : public CountHelper, public satcat5::eth::ArpListener {
        public:
            explicit CountArpResponse(satcat5::ip::Dispatch* iface)
                : m_arp(&iface->m_arp) {m_arp->add(this);}
            virtual ~CountArpResponse() {m_arp->remove(this);}
        protected:
            void arp_event(const satcat5::eth::MacAddr& mac, const satcat5::ip::Addr& ip) override {++m_count;}
            void gateway_change(const satcat5::ip::Addr& dstaddr, const satcat5::ip::Addr& gateway) override {}
            satcat5::eth::ProtoArp* const m_arp;
        };

        //! Count calls to `poll_demand()`. \see poll::OnDemand
        class CountOnDemand final
            : public CountHelper, public satcat5::poll::OnDemand {
        public:
            CountOnDemand() {}
        protected:
            void poll_demand() override {++m_count;}
        };

        //! Count calls to `ping_event()`. \see ip::PingListener
        class CountPingResponse final
            : public CountHelper, public satcat5::ip::PingListener {
        public:
            explicit CountPingResponse(satcat5::ip::Dispatch* iface)
                : m_icmp(&iface->m_icmp) {m_icmp->add(this);}
            virtual ~CountPingResponse() {m_icmp->remove(this);}
        protected:
            void ping_event(const satcat5::ip::Addr& from, u32 elapsed_usec) {++m_count;}
            satcat5::ip::ProtoIcmp* const m_icmp;
        };

        //! Count calls to `ptp_ready()`. \see ptp::Callback
        class CountPtpCallback final
            : public CountHelper, public satcat5::ptp::Callback {
        public:
            CountPtpCallback(satcat5::ptp::Source* src) : Callback(src) {}
            void ptp_ready(const satcat5::ptp::Measurement& data) override {++m_count;}
        };

        //! Count calls to `timer_event()`. \see poll::Timer
        class CountTimer final
            : public CountHelper, public satcat5::poll::Timer {
        public:
            CountTimer() {}
            void timer_event() override {++m_count;}
        };

        //! Dummy implementation of net::Address that writes data to a buffer.
        class DebugAddress : public satcat5::net::Address {
            //! Received-data buffer is directly accessible.
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

        //! Accelerated version of PosixTimer is 256x real-time.
        //! This is typically used to resolve long timeouts in a reasonable
        //! amount of elapsed simulation time. \see TimerSimulation.
        class FastPosixTimer : public satcat5::util::TimeRef {
        public:
            FastPosixTimer() : satcat5::util::TimeRef(1000000) {}
            u32 raw() override { return m_timer.raw() << 8; }
        protected:
            satcat5::util::PosixTimer m_timer;
        };

        //! Count calls to `data_rcvd()`. \see io::EventListener
        class IoEventCounter final
            : public CountHelper, public satcat5::io::EventListener {
        public:
            IoEventCounter() {}
        protected:
            void data_rcvd(satcat5::io::Readable* src) {++m_count;}
        };

        //! Log any received Ethernet traffic of the designated type.
        class LogProtocol : public satcat5::eth::Protocol {
        public:
            //! Attach this object to an Ethernet interface and set filter.
            LogProtocol(
                satcat5::eth::Dispatch* dispatch,
                const satcat5::eth::MacType& ethertype);
            // Required API from eth::Protocol.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
        };

        //! Mockup for a memory-mapped ConfigBus.
        //! This mocks out the memory-map interface only; the child class
        //! or end-user must add behaviors to simulate device operation.
        class MockConfigBusMmap : public satcat5::cfg::ConfigBusMmap {
        public:
            //! Create this mock interface.
            MockConfigBusMmap();
            //! Clear all registers for all devices.
            void clear_all(u32 val = 0);
            //! Clear all registers for the specified device-ID.
            void clear_dev(unsigned devaddr, u32 val = 0);
            //! Make event-handler accessible (normally private)
            void irq_event();

        protected:
            //! Simulated register-map for up to 256 devices.
            u32 m_regs[satcat5::cfg::MAX_TOTAL_REGS];
        };

        //! Mockup for a ConfigBus interrupt register.
        class MockInterrupt : public CountHelper, public satcat5::cfg::Interrupt {
        public:
            //! No associated register, assumes interrupt has fired.
            explicit MockInterrupt(satcat5::cfg::ConfigBus* cfg);

            //! Poll the designated register to see if interrupt flag is set.
            MockInterrupt(satcat5::cfg::ConfigBus* cfg, unsigned regaddr);

            //! Trigger a virtual interrupt.
            void fire();

        protected:
            void irq_event() override {++m_count;}

            satcat5::cfg::ConfigBus* const m_cfg;
            unsigned m_regaddr;
        };

        //! Readable source for a pseudorandom block of data.
        class RandomSource
            : public satcat5::util::HeapAllocator
            , public satcat5::io::ArrayRead {
        public:
            //! Generate a pseudorandom block of data.
            explicit RandomSource(unsigned len);
            //! Prepare to read or re-read data from start of block.
            satcat5::io::Readable* read();
            //! Length of the internal block.
            inline unsigned len() const {return m_len;}
            //! Issue the `read_notify` / `data_rcvd` callback.
            inline void notify() {read_notify();}
            //! Raw access to the underlying buffer.
            inline const u8* raw() const {return m_buffptr;}
        protected:
            const unsigned m_len;
        };

        //! Measure various statistics of a discrete-time series.
        class Statistics {
        public:
            Statistics();           //!< Create an empty dataset.
            void add(double x);     //!< Add a new data point
            double mean() const;    //!< Mean of all data points
            double msq() const;     //!< Mean-square
            double rms() const;     //!< Root-mean-square
            double std() const;     //!< Standard deviation
            double var() const;     //!< Variance
            double min() const;     //!< Minimum over all inputs
            double max() const;     //!< Maximum over all inputs
        protected:
            unsigned m_count;       //!< Number of data points
            double m_sum;           //!< Sum of inputs
            double m_sumsq;         //!< Sum of squares
            double m_min;           //!< Running minimum
            double m_max;           //!< Running maximum
        };

        //! Timekeeper object for granular simulation of elapsed time.
        class TimerSimulation : public satcat5::util::TimeRef {
        public:
            // Implement the TimeRef API.
            TimerSimulation();
            ~TimerSimulation();
            u32 raw() override;

            //! Step forward one millisecond.
            void sim_step();
            //! Step forward N milliseconds.
            void sim_wait(unsigned dly_msec);

        protected:
            u32 m_tref, m_tnow;
        };
    }
}
