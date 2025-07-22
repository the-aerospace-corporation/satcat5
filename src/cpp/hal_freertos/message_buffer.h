//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// PacketBuffer to MessageBuffer adapter.

#pragma once

extern "C" {
    #include <FreeRTOS.h>
    #include <message_buffer.h>
    #include <semphr.h>
};

#include <satcat5/eth_switch.h>
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace freertos {
        //! Copy data from a Readable source to a FreeRTOS MessageBuffer.
        class MessageCopy final : public satcat5::io::EventListener {
        public:
            MessageCopy(
                satcat5::io::Readable* src,
                MessageBufferHandle_t* msg_buff_handle,
                SemaphoreHandle_t* msg_buff_semphr
                );
            ~MessageCopy() SATCAT5_OPTIONAL_DTOR;
        protected:
            // Override io::EventListener handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Pointers to source, message buffer, and semaphore.
            satcat5::io::Readable* m_src;
            MessageBufferHandle_t* const m_handle;
            SemaphoreHandle_t* const m_mutex;
        };

        //! PacketBuffer to MessageBuffer adapter.
        //! This adapter allows SatCat5 to send bytes to other FreeRTOS tasks
        //! through a FreeRTOS MessageBuffer ("MessageBufferHandle_t").
        //! The adapter includes a semaphore for mutual exclusion.
        //! \see satcat5::freertos::StreamBuffer.
        class MessageBuffer : public satcat5::io::WriteableRedirect {
        public:
            //! Constructor requires a working buffer, plus handles
            //! for the FreeRTOS MessageBuffer and Semaphore.
            MessageBuffer(
                u8* txbuff, unsigned txbytes,
                MessageBufferHandle_t* msg_buff_handle,
                SemaphoreHandle_t* msg_buff_semphr);

        private:
            // Working buffer accumulates each packet.
            satcat5::io::PacketBuffer m_tx;

            // Copy complete packets to the FreeRTOS buffer.
            satcat5::freertos::MessageCopy m_copy;
        };

        //! SwitchPort to FreeRTOS MessageBuffer adapter.
        //! This adapter allows for a SatCat5 switch port to be directly
        //! readable and writable through a FreeRTOS MessageBuffer
        //! ("MessageBufferHandle_t").
        //! The adapter includes a semaphore for mutual exclusion.
        class MessageBufferPort : public satcat5::eth::SwitchPort {
        public:
            MessageBufferPort(
                satcat5::eth::SwitchCore* sw,
                MessageBufferHandle_t* msg_buff_handle,
                SemaphoreHandle_t* msg_buff_semphr);

        protected:
            // Copy complete packets to the FreeRTOS buffer.
            satcat5::freertos::MessageCopy m_copy;
        };
    }  // namespace freertos
}  // namespace satcat5
