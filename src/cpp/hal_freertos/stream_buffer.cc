//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_freertos/stream_buffer.h>

#ifndef SATCAT5_FREERTOS_STRM_BUF_SEMPHR_TIMEOUT_MS
#define SATCAT5_FREERTOS_STRM_BUF_SEMPHR_TIMEOUT_MS     1
#endif

#ifndef SATCAT5_FREERTOS_STRM_BUFF_SEND_TIMEOUT_MS
#define SATCAT5_FREERTOS_STRM_BUFF_SEND_TIMEOUT_MS      1
#endif

using satcat5::freertos::StreamBuffer;

StreamBuffer::StreamBuffer(
        u8* txbuff,
        unsigned txbytes,
        StreamBufferHandle_t* stream_buff_handle,
        SemaphoreHandle_t* stream_buff_semphr)
    : satcat5::io::WriteableRedirect(&m_tx)
    , m_tx(txbuff, txbytes, 0)
    , m_handle(stream_buff_handle)
    , m_semphr(stream_buff_semphr)
    , m_status(0)
{
    // Set Callback
    m_tx.set_callback(this);
}

void StreamBuffer::data_rcvd(satcat5::io::Readable* src)
{
    // Check TX Ready Bytes & Transfer
    while (u32 txbytes = m_tx.get_peek_ready())
    {
        // Take Semaphore
        m_status = xSemaphoreTake(
            *m_semphr,
            pdMS_TO_TICKS(SATCAT5_FREERTOS_STRM_BUF_SEMPHR_TIMEOUT_MS));

        // Error Guard
        if (!m_status) break;

        // Send to Message Buffer
        m_status = xStreamBufferSend(
            *m_handle,
            m_tx.peek(txbytes),
            txbytes,
            pdMS_TO_TICKS(SATCAT5_FREERTOS_STRM_BUFF_SEND_TIMEOUT_MS));

        // Release Semaphore
        xSemaphoreGive(*m_semphr);

        // Error Guard
        if (!m_status) break;

        // Consume Bytes
        m_tx.read_consume(txbytes);
    }
}

//////////////////////////////////////////////////////////////////////////