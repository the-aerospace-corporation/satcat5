//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! General-purpose ConfigBus emulator utilities.
//!
//!\details
//! This file has seeveral utilities for emulating a ConfigBus host interface,
//! allowing a driver under test to read and write control registers.
//!
//! The classes defined here are flexible enough to emulate most simple
//! devices.  However, more complex devices may need custom logic derived
//! directly from cfg::ConfigBus. \see test::MultiSerial for one example.

#pragma once

#include <deque>
#include <map>
#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace test {
        //! Simulation of a single ConfigBus register.
        //! \see sim_cfgbus.h
        //! Each register write is saved for later inspection by the test
        //! script (i.e., write_count, write_next).  Each register read
        //! depends on mode; it may echo the most recent write, read a
        //! single fixed value, or pull from a pre-populated queue.
        class CfgRegister : public satcat5::cfg::ConfigBus {
        public:
            //! Constructor for a single register.
            //! For safety checking, registers cannot be read by default.
            //! Call read_default_* to set the appropriate mode.
            CfgRegister();

            //! Set default value for reads when the queue is empty.
            //! The simulated register includes a queue of expected reads.
            //! \see read_push, read_count, read_queue.
            //! These methods set the behavior when that queue is empty:
            //! * read_default_none(): Report an error, then return zero.
            //! * read_default_echo(): Returns the last written value.
            //! * read_default(...): Returns the user-specified value.
            //!@{
            void read_default_none();
            void read_default_echo();
            void read_default(u32 val);
            //!@}

            // Cumulative read/write statistics.
            unsigned read_count() const;    //!< Total reads from this register.
            unsigned write_count() const;   //!< Total writes to this register.

            //! Queue up a read for this register.
            //! The read queue is populated by the mock or test infrastructure.
            //! Reads are pulled from the queue until it is empty, then follow
            //! the "default" policy set by the various "read_default" methods.
            //! \see read_default_none, read_default_echo, read_default
            void read_push(u32 val);
            //! Number of queued responses. \see read_push.
            unsigned read_queue() const;

            //! Pop one value from the recent write queue.
            //! Each write to the register is added to an queue, which can
            //! then be queried to verify that the written value is correct.
            u32 write_pop();
            //!< Number of queued write values. \see write_pop.
            unsigned write_queue() const;

            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& rdval) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

        protected:
            // Queue of past write values and future read values.
            std::deque<u32> m_queue_rd;
            std::deque<u32> m_queue_wr;

            // Configure this register's read-response mode.
            enum class ReadMode {UNSAFE, STRICT, ECHO, CONSTANT};
            ReadMode m_rd_mode;
            u32 m_rd_dval;

            // Count total reads and writes.
            unsigned m_rd_count;
            unsigned m_wr_count;
        };

        //! Simulated bank of ConfigBus registers.
        //! This class wraps an array of CfgRegister objects, representing
        //! a ConfigBus "device-address" spanning up to 1024 registers.
        //! It provides accessors for configuring individual registers, or
        //! for configuring all registers at once. \see CfgRegister.
        class CfgDevice : public satcat5::cfg::ConfigBus {
        public:
            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& val) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

            //! Accessor for each simulated register.
            satcat5::test::CfgRegister& operator[](unsigned idx) {return reg[idx];}

            //! Make the "irq_poll" method accessible.
            void irq_poll() {satcat5::cfg::ConfigBus::irq_poll();}

            //! Set read mode for all contained registers.
            //! \see CfgRegister::read_default.
            //!@{
            void read_default_none();   // Read when empty = error
            void read_default_echo();   // Read when empty = last written
            void read_default(u32 val); // Read when empty = value
            //!@}

        protected:
            // Bank of underlying registers.
            satcat5::test::CfgRegister reg[satcat5::cfg::REGS_PER_DEVICE];
        };

        //! Simulated ConfigBus address space with many devices.
        //! This class wraps a set of ConfigBus objects, each representing
        //! a single ConfigBus device address. \see CfgDevice.
        class CfgSpace : public satcat5::cfg::ConfigBus {
        public:
            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& val) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

            //! Make the "irq_poll" method accessible.
            void irq_poll() {satcat5::cfg::ConfigBus::irq_poll();}

            //! Register a handler for a specific device address.
            void add_device(unsigned devaddr, satcat5::cfg::ConfigBus& cfg);

            //! Access the designated device handler, by device-address.
            satcat5::cfg::ConfigBus& get_device(unsigned devaddr);

        protected:
            // Handler for undefined registers.
            satcat5::test::CfgRegister m_undef;
            // Bank of underlying registers.
            std::map<unsigned, satcat5::cfg::ConfigBus&> m_devs;
        };
    }
}
