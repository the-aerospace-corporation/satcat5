//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simulated MultiSerial controller.

#pragma once

#include <deque>
#include <satcat5/cfgbus_multiserial.h>

namespace satcat5 {
    namespace test {
        // Command flags for load_refcmd
        extern const u8 MST_ERROR;  //!< Sets error flag
        extern const u8 MST_READ;   //!< Triggers read
        extern const u8 MST_START;  //!< Clears error flag

        //! Simulated Multi-Serial controller.
        //! This class emulates a ConfigBus interface for the multipurpose
        //! serial-data controller defined in "cfgbus_multiserial", which
        //! is used for the I2C, SPI, and UART peripherals.
        //!
        //! This simulation responds to individual register reads and writes,
        //! to test the control software for each block.  Outputs can then be
        //! compared against expectations for unit testing of device drivers.
        //!
        //! The "read" data is always a simple counter.
        class MultiSerial : public satcat5::cfg::ConfigBus {
        public:
            //! Create the simulated MultiSerial device.
            //! Optionally set the maximum command queue depth.
            explicit MultiSerial(unsigned cmd_max = 32);

            //! Load next expected command into queue.
            void load_refcmd(u16 next, u8 flags = 0);

            //! Poll event-handlers and advance simulation.
            void poll();

            //! Did we execute the full command sequence?
            bool done() const {return m_cmd_ref.empty();}

            //! Last written configuration word (REGADDR = 2).
            u32 get_cfg() const {return m_config;}

            //! Force the BUSY flag to help reach certain edge-cases.
            void force_busy(bool busy) {m_busy = busy;}

            //! Simulate a delayed reply with of N bytes.
            //! (Prompt replies should set the MST_READ flag.)
            void reply_rcvd(unsigned count);

        protected:
            // Basic read and write operations (for ConfigBus API).
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& rdval) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

            // Internal simulation timestep.
            void step();

            // Queue of actual and expected write commands.
            std::deque<u16> m_cmd_fifo;     // Commands waiting in queue
            std::deque<u16> m_cmd_ref;      // Expected value of each command
            std::deque<u8>  m_cmd_flags;    // Other action & event flags

            // Other internal state
            const unsigned  m_cmd_max;      // Size of command queue
            unsigned        m_cmd_idx;      // Index of next command
            u32             m_config;       // Last written configuration word
            bool            m_busy;         // Forced busy flag
            bool            m_error;        // Error flag (I2C NoAck, etc.)
            bool            m_irq;          // Interrupt pending?
            u8              m_rd_count;     // Read-data counter (0-255 repeating)
            unsigned        m_rd_ready;     // Number of read bytes in queue
        };
    }
}
