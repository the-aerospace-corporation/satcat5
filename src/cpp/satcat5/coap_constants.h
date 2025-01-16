//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Constants relating to the Constrained Applications Protocol (CoAP)
//
// This file defines useful constants for working with the Constrained
// Applications Protocol (CoAP) defined in IETF RFC-7252:
//  https://www.rfc-editor.org/rfc/rfc7252
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace coap {
        // Message header VERSION and TYPE fields (Section 3)
        constexpr u8
            PAYLOAD_MARKER = 255,   // Payload marker
            TYPE_CON = 0x00,        // Confirmable
            TYPE_NON = 0x10,        // Non-confirmable
            TYPE_ACK = 0x20,        // Acknowledgement
            TYPE_RST = 0x30,        // Reset
            VERSION1 = (1 << 6);    // Version 1 (RFC7252)

        // Message header CODE field (Section 12.1):
        struct Code {
            u8 value;                           // Raw value.

            // Constructors.
            explicit constexpr Code(u8 val)
                : value(val) {}                 // Create x.yy from raw byte
            constexpr Code(u8 x, u8 yy)
                : value((x << 5) | yy) {}       // Create x.yy from x and yy
            constexpr Code(const Code& other)
                : value(other.value) {}         // Copy constructor
            Code& operator=(const Code& other)
                { value = other.value; return *this; } // Assignment operator

            // Basic accessors.
            constexpr u8 category() const
                { return (value >> 5) & 0x7; }  // Return the "x" from x.yy
            constexpr u8 subtype() const
                { return (value & 0x1F); }      // Return the "yy" from x.yy

            // Comparison operators.
            bool operator==(const Code& other) const
                { return (value == other.value); }
            bool operator!=(const Code& other) const
                { return (value != other.value); }

            // Category tests:
            //  0.00      = Empty (may be request or response)
            //  0.01-0.31 = Request
            //  2.00-2.31 = Success
            //  4.00-4.31 = Client error
            //  5.00-5.31 = Server error
            constexpr bool is_empty() const
                { return (value == 0); }
            constexpr bool is_request() const
                { return (category() == 0); }
            constexpr bool is_success() const
                { return (category() == 2); }
            constexpr bool is_error() const
                { return (category() == 4) || (category() == 5); }
            constexpr bool is_response() const
                { return is_empty() || is_success() || is_error(); }
        };

        constexpr Code                  // Request codes (Section 12.1.1)
            CODE_EMPTY          (0,0),  // 0.00 Empty message
            CODE_GET            (0,1),  // 0.01 GET request
            CODE_POST           (0,2),  // 0.02 POST request
            CODE_PUT            (0,3),  // 0.03 PUT request
            CODE_DELETE         (0,4);  // 0.04 DEL request
        constexpr Code                  // Response codes (Section 12.1.2)
            CODE_CREATED        (2,1),  // 2.01 Created
            CODE_DELETED        (2,2),  // 2.02 Deleted
            CODE_VALID          (2,3),  // 2.03 Valid
            CODE_CHANGED        (2,4),  // 2.04 Changed
            CODE_CONTENT        (2,5),  // 2.05 Content
            CODE_BAD_REQUEST    (4,0),  // 4.00 Bad Request
            CODE_UNAUTHORIZED   (4,1),  // 4.01 Unauthorized
            CODE_BAD_OPTION     (4,2),  // 4.02 Bad Option
            CODE_FORBIDDEN      (4,3),  // 4.03 Forbidden
            CODE_NOT_FOUND      (4,4),  // 4.04 Not Found
            CODE_BAD_METHOD     (4,5),  // 4.05 Method Not Allowed
            CODE_NOT_ACCEPT     (4,6),  // 4.06 Not Acceptable
            CODE_PRECND_FAIL    (4,12), // 4.12 Precondition Failed
            CODE_TOO_LARGE      (4,13), // 4.13 Request Entity Too Large
            CODE_BAD_FORMAT     (4,15), // 4.15 Unsupported Content-Format
            CODE_SERVER_ERROR   (5,0),  // 5.00 Internal Server Error
            CODE_NOT_IMPL       (5,1),  // 5.01 Not Implemented
            CODE_BAD_GATEWAY    (5,2),  // 5.02 Bad Gateway
            CODE_UNAVAILABLE    (5,3),  // 5.03 Service Unavailable
            CODE_GATE_TIMEOUT   (5,4),  // 5.04 Gateway Timeout
            CODE_NO_PROXY       (5,5);  // 5.05 Proxying Not Supported

        // Option numbers (Section 12.2)
        constexpr u16
            OPTION_IF_MATCH     = 1,    // If-Match
            OPTION_URI_HOST     = 3,    // Uri-Host
            OPTION_ETAG         = 4,    // ETag
            OPTION_IF_NONE      = 5,    // If-None-Match
            OPTION_URI_PORT     = 7,    // Uri-Port
            OPTION_LOC_PATH     = 8,    // Location-Path
            OPTION_URI_PATH     = 11,   // Uri-Path
            OPTION_FORMAT       = 12,   // Content-Format
            OPTION_MAX_AGE      = 14,   // Max-Age
            OPTION_URI_QUERY    = 15,   // Uri-Query
            OPTION_ACCEPT       = 17,   // Accept
            OPTION_LOC_QUERY    = 20,   // Location-Query
            OPTION_BLOCK2       = 23,   // Block transfer (RFC7959)
            OPTION_BLOCK1       = 27,   // Block transfer (RFC7959)
            OPTION_PROXY_URI    = 35,   // Proxy-Uri
            OPTION_PROXY_SCH    = 39,   // Proxy-Scheme
            OPTION_SIZE1        = 60;   // Size1

        // Content-format codes (Section 12.3)
        // (These are used with OPTION_FORMAT and OPTION_ACCEPT.)
        constexpr u16                   // Equivalent MIME specifier:
            FORMAT_TEXT         = 0,    // text/plain;charset=utf-8
            FORMAT_LINK         = 40,   // application/link-format
            FORMAT_XML          = 41,   // application/xml
            FORMAT_BYTES        = 42,   // application/octet-stream
            FORMAT_EXI          = 47,   // application/exi
            FORMAT_JSON         = 50,   // application/json
            FORMAT_CBOR         = 60,   // application/cbor (RFC8949)
            FORMAT_CBOR_SEQ     = 63;   // application/cbor-seq (RFC8742)
    }
}
