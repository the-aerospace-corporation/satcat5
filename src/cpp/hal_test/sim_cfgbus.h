//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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
// General-purpose ConfigBus emulator
//
// This block emulates a ConfigBus host interface, allowing a driver under
// test to read and write control registers.  It is flexible enough to
// emulate many simple devices; more complex devices usually need custom
// logic.  (Refer to "sim_multiserial.h" for an example of the latter.)
//
// Each register write is saved for later inspection by the test script
// (i.e., write_count, write_next).  Each register read is pulled from a
// pre-populated queue, usually filled before the test starts.  In both
// cases, each register has a separate queue.
//

#pragma once

#include <deque>
#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace test {
        // Simulated register.
        class CfgRegister : public satcat5::cfg::ConfigBus {
        public:
            // For safety checking, registers cannot be read by default.
            // Call read_default_* to set the appropriate mode.
            CfgRegister();

            // Set default value for reads when the queue is empty.
            void read_default_none();       // Read when empty = error
            void read_default_echo();       // Read when empty = last written
            void read_default(u32 val);     // Read when empty = value

            // Queue up a read for this register.
            // The read queue is populated by the mock or test infrastructure.
            // Reads are pulled from the queue until it is empty, then follow
            // the "default" policy set by the various methods above.
            void read_push(u32 val);        // Enqueue next read-response
            unsigned read_count() const;    // Total reads from this register
            unsigned read_queue() const;    // Number of queued responses

            // Query the queue of write commands.
            // Each write to the register is added to this queue, which can
            // then be queried to verify that the written value is correct.)
            unsigned write_count() const;   // Total writes to this register
            unsigned write_queue() const;   // Number of queued write values
            u32 write_pop();                // Pop next write value from queue

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

        // Simulated bank of registers.
        class CfgDevice : public satcat5::cfg::ConfigBus {
        public:
            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& val) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

            // Accessor for each simulated register.
            satcat5::test::CfgRegister& operator[](unsigned idx) {return reg[idx];}

            // Make the "irq_poll" method accessible.
            void irq_poll() {satcat5::cfg::ConfigBus::irq_poll();}

            // Set read mode for all contained registers.
            void read_default_none();   // Read when empty = error
            void read_default_echo();   // Read when empty = last written
            void read_default(u32 val); // Read when empty = value

        protected:
            // Bank of underlying registers.
            satcat5::test::CfgRegister reg[satcat5::cfg::REGS_PER_DEVICE];
        };
    }
}
