//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_freertos/message_buffer.h>
#include <satcat5/utils.h>

// User-adjustable constants
#ifndef SATCAT5_FREERTOS_MSG_BUF_SEMPHR_TIMEOUT_MS
    #define SATCAT5_FREERTOS_MSG_BUF_SEMPHR_TIMEOUT_MS  1
#endif

#ifndef SATCAT5_FREERTOS_MSG_BUFF_SEND_TIMEOUT_MS
    #define SATCAT5_FREERTOS_MSG_BUFF_SEND_TIMEOUT_MS   1
#endif

#ifndef SATCAT5_MESSAGEBUFFER_BUFFSIZE
    #define SATCAT5_MESSAGEBUFFER_BUFFSIZE    1600
#endif

using satcat5::freertos::MessageBuffer;
using satcat5::freertos::MessageBufferPort;
using satcat5::freertos::MessageCopy;
using satcat5::util::min_unsigned;

MessageCopy::MessageCopy(
        satcat5::io::Readable* src,
        MessageBufferHandle_t* msg_buff_handle,
        SemaphoreHandle_t* msg_buff_mutex)
    : m_src(src)
    , m_handle(msg_buff_handle)
    , m_mutex(msg_buff_mutex)
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
MessageCopy::~MessageCopy() {
    if (m_src) m_src->set_callback(nullptr);
}
#endif

void MessageCopy::data_unlink(satcat5::io::Readable* src){
    m_src = 0;
}

void MessageCopy::data_rcvd(satcat5::io::Readable* src) {
    // Check TX Ready Bytes & Transfer
    u8 tmp[SATCAT5_MESSAGEBUFFER_BUFFSIZE];
    while (unsigned rx_bytes = src->get_read_ready()) {
        // Copy data from source to temporary buffer.
        rx_bytes = min_unsigned(rx_bytes, SATCAT5_MESSAGEBUFFER_BUFFSIZE);
        src->read_bytes(rx_bytes, tmp);
        src->read_finalize();

        // Take Semaphore
        BaseType_t status = xSemaphoreTake(
            *m_mutex,
            pdMS_TO_TICKS(SATCAT5_FREERTOS_MSG_BUF_SEMPHR_TIMEOUT_MS));
        if (!status) break;

        // Send to Message Buffer
        status = xMessageBufferSend(
            *m_handle,
            tmp,
            rx_bytes,
            pdMS_TO_TICKS(SATCAT5_FREERTOS_MSG_BUFF_SEND_TIMEOUT_MS));

        // Release Semaphore
        xSemaphoreGive(*m_mutex);
        if (!status) break;
    }
}

MessageBuffer::MessageBuffer(
        u8* txbuff, unsigned txbytes,
        MessageBufferHandle_t* msg_buff_handle,
        SemaphoreHandle_t* msg_buff_mutex)
    : satcat5::io::WriteableRedirect(&m_tx)
    , m_tx(txbuff, txbytes, 32)
    , m_copy(&m_tx, msg_buff_handle, msg_buff_mutex)
{
    // Nothing else to initialize.
}

MessageBufferPort::MessageBufferPort(
        satcat5::eth::SwitchCore* sw,
        MessageBufferHandle_t* msg_buff_handle,
        SemaphoreHandle_t* msg_buff_mutex)
    : SwitchPort(sw, this)
    , m_copy(&m_egress, msg_buff_handle, msg_buff_mutex)
{
    // Nothing else to initialize.
}
