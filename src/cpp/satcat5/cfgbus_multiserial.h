//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Partial driver for the multipurpose serial peripheral

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace cfg {
        //! Partial driver for the multipurpose serial peripheral.
        //!
        //! This incomplete driver controls the "cfgbus_multiserial" block in
        //! transaction-based protocols, such as I2C and SPI.  It handles core
        //! functions such as interrupt servicing, and is designed to maintain
        //! good throughput, but requires additional logic to implement specific
        //! protocols. \see cfg::I2c, cfg::Spi.
        //!
        //! This driver should not be used for when "cfgbus_multiserial" is used
        //! in streaming mode. \see cfg::Uart.
        class MultiSerial
            : public    satcat5::cfg::Interrupt
            , protected satcat5::io::EventListener
            , public    satcat5::poll::OnDemand
        {
        public:
            //! How full is the transmit queue? (0-100%)
            inline u8 get_percent_full() const
                {return m_tx.get_percent_full();}

            //! Is the queue empty and the bus idle?
            inline bool idle() const
                {return m_cmd_queued == 0;}

        protected:
            //! Set all parameters for this Multiserial instance.
            //! (Only children should create or destroy base class.)
            MultiSerial(
                satcat5::cfg::ConfigBus* cfg,   // ConfigBus interface object
                unsigned devaddr,               // ConfigBus device address
                unsigned maxpkt,                // Maximum queued commands
                u8* txbuff, unsigned txsize,    // Command buffer (ptr + len)
                u8* rxbuff, unsigned rxsize);   // Reply buffer (ptr + len)
            ~MultiSerial() {}

            //! Is there enough space in the software queue?
            //! If it returns true, write each opcode and then call write_finish().
            bool write_check(
                unsigned ncmd,      // Number of opcodes in this transaction
                unsigned nread);    // Number of reads in this transaction

            //! Enqueue transaction after calling write_check().
            //! The child object must call write_check, then write each opcode
            //! to the queue (m_tx), then call write_finish.
            //! \returns The new command-index, to allow storage of additional
            //! metadata associated with this command.
            unsigned write_finish();

            //! Callback when each transaction is finished.
            //! The child object must reads N+1 bytes m_rx, where the first
            //! N bytes are reply data and the last byte is an error flag.
            //! \param cidx Command index (for child class to retrieve metadata).
            //! (Child MUST override this method.)
            virtual void read_done(unsigned cidx) = 0;

            // ConfigBus register map.
            static const unsigned REGADDR_IRQ;
            static const unsigned REGADDR_CFG;
            static const unsigned REGADDR_STATUS;
            static const unsigned REGADDR_DATA;

            // ConfigBus interface object.
            satcat5::cfg::Register m_ctrl;

            // Command and reply buffers
            satcat5::io::PacketBuffer m_tx; //!< Buffer for hardware commands
            satcat5::io::PacketBuffer m_rx; //!< Buffer for reply data

        private:
            // Internal event handlers
            void data_rcvd(satcat5::io::Readable* src) override;
            void irq_event();           // ConfigBus interrupt
            void poll_demand();         // Deferred interrupt

            // Internal state, not accessible to children.
            unsigned const m_cmd_max;   // Max queued commands
            unsigned m_cmd_cbidx;       // Index of next callback
            unsigned m_cmd_queued;      // Number of queued commands
            unsigned m_new_wralloc;     // Expected command length of new command
            unsigned m_new_rdalloc;     // Expected reply length for new command
            unsigned m_rdalloc;         // Unallocated space in reply buffer
            unsigned m_irq_wrrem;       // Remaining opcodes in current command
            unsigned m_irq_rdrem;       // Remaining reads in current command
        };
    }
}
