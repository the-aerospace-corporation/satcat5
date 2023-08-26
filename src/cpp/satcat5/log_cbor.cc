//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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

#include <satcat5/datetime.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/log_cbor.h>
#include <satcat5/udp_dispatch.h>

// Start of conditional compilation...
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_decode.h>
#include <qcbor/qcbor_encode.h>
using satcat5::log::FromCbor;
using satcat5::log::ToCbor;
using satcat5::net::Type;

// Set the size of the working buffer.
#ifndef SATCAT5_QCBOR_BUFFER
#define SATCAT5_QCBOR_BUFFER 1500
#endif

FromCbor::FromCbor(
        satcat5::net::Dispatch* src,
        satcat5::net::Type filter)
    : satcat5::net::Protocol(filter)
    , m_src(src)
{
    // Register our incoming message handler.
    m_src->add(this);
}

#if SATCAT5_ALLOW_DELETION
FromCbor::~FromCbor()
{
    // Unregister our incoming message handler.
    m_src->remove(this);
}
#endif

inline bool int_or_null(const QCBORItem& item)
{
    return item.uDataType == QCBOR_TYPE_NULL
        || item.uDataType == QCBOR_TYPE_INT64;
}

void FromCbor::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // Working buffer and QCBOR decoder state.
    u8 buff[SATCAT5_QCBOR_BUFFER];
    QCBORDecodeContext cbor;
    QCBORItem item;
    int errcode = 0;
    s8 priority = 0;

    // Read the frame contents, discarding oversize messages.
    unsigned plen = src.get_read_ready();
    if (plen > SATCAT5_QCBOR_BUFFER) return;
    if (!src.read_bytes(plen, buff)) return;

    // Open a QCBOR parser object.
    QCBORDecode_Init(&cbor, {buff, plen}, QCBOR_DECODE_MODE_NORMAL);

    // First item should be the argument array.
    // (Silently discard any messages that don't match expected format.)
    errcode = QCBORDecode_GetNext(&cbor, &item);
    if (errcode || item.uDataType != QCBOR_TYPE_ARRAY) return;

    // Within that context, read the message parameters...
    // (Silently discard any messages that don't match expected format.)
    errcode = QCBORDecode_GetNext(&cbor, &item);    // Payload-ID
    if (errcode || !int_or_null(item)) return;
    errcode = QCBORDecode_GetNext(&cbor, &item);    // GPS time-of-week
    if (errcode || !int_or_null(item)) return;
    errcode = QCBORDecode_GetNext(&cbor, &item);    // Priority code
    if (errcode || item.uDataType != QCBOR_TYPE_INT64) return;
    errcode = QCBOR_Int64ToInt8(item.val.int64, &priority);
    if (errcode) return;
    if (priority < m_min_priority) return;  // Ignore if priority is below minimum level
    errcode = QCBORDecode_GetNext(&cbor, &item);    // Message string
    if (errcode || item.uDataType != QCBOR_TYPE_TEXT_STRING) return;

    // Success! Relay message contents to the local log.
    // Note: String is NOT null-terminated, so length is required.
    satcat5::log::Log(priority, item.val.string.ptr, item.val.string.len);
}

ToCbor::ToCbor(satcat5::datetime::Clock* clk, satcat5::net::Address* dst)
    : m_clk(clk), m_dst(dst)
{
    // Nothing else to initialize.
}

void ToCbor::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    if (priority < m_min_priority) return;  // Ignore if priority is below minimum level

    // Before we do any work, check if the destination address is set.
    if (!m_dst->ready()) return;

    // Allocate a fixed-size working buffer.
    u8 buff[SATCAT5_QCBOR_BUFFER];

    // Construct the CBOR data structure.
    QCBOREncodeContext cbor;
    QCBOREncode_Init(&cbor, UsefulBuf_FROM_BYTE_ARRAY(buff));
    QCBOREncode_OpenArray(&cbor);
    QCBOREncode_AddNULL(&cbor);                     // Payload type
    if (m_clk) {                                    // Timestamp
        auto now = satcat5::datetime::to_gps(m_clk->now());
        QCBOREncode_AddInt64(&cbor, now.tow);
    } else {
        QCBOREncode_AddInt64(&cbor, -1);
    }
    QCBOREncode_AddInt64(&cbor, priority);          // Priority
    QCBOREncode_AddText(&cbor, {msg, nbytes});      // Message
    QCBOREncode_CloseArray(&cbor);

    // Generate the final encoded message.
    UsefulBufC encoded;
    QCBORError error = QCBOREncode_Finish(&cbor, &encoded);
    if (error) return;

    // Write data to the network interface.
    m_dst->write_packet(encoded.len, encoded.ptr);
}

satcat5::eth::LogFromCbor::LogFromCbor(
        satcat5::eth::Dispatch* iface,
        const satcat5::eth::MacType& typ)
    : satcat5::log::FromCbor(iface, Type(typ.value))
{
    // No other initialization required.
}

satcat5::eth::LogToCbor::LogToCbor(
        satcat5::datetime::Clock* clk,
        satcat5::eth::Dispatch* eth,
        const satcat5::eth::MacType& typ)
    : satcat5::eth::AddressContainer(eth)
    , satcat5::log::ToCbor(clk, &m_addr)
{
    // Default to broadcast mode.
    connect(satcat5::eth::MACADDR_BROADCAST, typ);
}

satcat5::udp::LogFromCbor::LogFromCbor(
        satcat5::udp::Dispatch* iface,
        const satcat5::udp::Port& port)
    : satcat5::log::FromCbor(iface, Type(port.value))
{
    // No other initialization required.
}

satcat5::udp::LogToCbor::LogToCbor(
        satcat5::datetime::Clock* clk,
        satcat5::udp::Dispatch* udp,
        const satcat5::udp::Port& dstport)
    : satcat5::udp::AddressContainer(udp)
    , satcat5::log::ToCbor(clk, &m_addr)
{
    // Default to broadcast mode.
    connect(satcat5::ip::ADDR_BROADCAST, dstport);
}

#endif // SATCAT5_CBOR_ENABLE
