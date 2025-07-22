//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// PacketBuffer to StreamBuffer adapter.

#pragma once

extern "C"{
    #include <FreeRTOS.h>
    #include <stream_buffer.h>
    #include <semphr.h>
};

#include <satcat5/io_writeable.h>
#include <satcat5/io_readable.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace freertos {
        //! PacketBuffer to StreamBuffer adapter.
        //! This class allows SatCat5 to send bytes to other FreeRTOS tasks
        //! through a FreeRTOS StreamBuffer ("StreamBufferHandle_t").
        //! The adapter includes a semaphore for mutual exclusion.
        //! \see satcat5::freertos::MessageBuffer.
        class StreamBuffer
            : public    satcat5::io::WriteableRedirect
            , protected satcat5::io::EventListener {
        public:
            //! Constructor requires a working buffer, plus handles
            //! for the FreeRTOS StreamBuffer and Semaphore.
            explicit StreamBuffer(
                u8* txbuff,
                unsigned txbytes,
                StreamBufferHandle_t* stream_buff_handle,
                SemaphoreHandle_t* stream_buff_semphr);

        private:
            // Event Handler
            void data_rcvd(satcat5::io::Readable* src);

            // Transmit Data
            satcat5::io::PacketBuffer m_tx;

            // Stream Buffer & Semaphore
            StreamBufferHandle_t* const m_handle;
            SemaphoreHandle_t* const m_semphr;

            // Status
            BaseType_t m_status;
        };
    }  // namespace freertos
}  // namespace satcat5
