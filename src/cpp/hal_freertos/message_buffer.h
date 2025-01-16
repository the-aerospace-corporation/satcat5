//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// PacketBuffer -> Message Buffer Implementation. This allows SatCat OS to
// write bytes to other FreeRTOS tasks via Message Buffers. This includes
// a semaphore for mutual exclusion.

#pragma once

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// FreeRTOS
extern "C"{
    #include <FreeRTOS.h>
    #include <message_buffer.h>
    #include <semphr.h>
};

// SatCat
#include <satcat5/io_writeable.h>
#include <satcat5/io_readable.h>
#include <satcat5/pkt_buffer.h>

//////////////////////////////////////////////////////////////////////////
// Class
//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace freertos {
        class MessageBuffer
        : public    satcat5::io::WriteableRedirect
        , protected satcat5::io::EventListener {
            public:
            // Constructor
            explicit MessageBuffer(
                u8* txbuff,
                unsigned txbytes,
                MessageBufferHandle_t* msg_buff_handle,
                SemaphoreHandle_t* msg_buff_semphr);

            private:
            // Event Handler
            void data_rcvd(satcat5::io::Readable* src);

            // Transmit Data
            satcat5::io::PacketBuffer m_tx;

            // Message Buffer & Semaphore
            MessageBufferHandle_t* const m_handle;
            SemaphoreHandle_t* const m_semphr;

            // Status
            BaseType_t m_status;
        };
    }  // namespace freertos
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
