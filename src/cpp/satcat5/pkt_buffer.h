//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Multipurpose circular buffer
//
// The PacketBuffer class is a wrapper for a circular buffer, with optional
// logic to support retention of frame/packet boundaries.  It implements the
// "Readable" and "Writeable" interfaces so that it can be used with many
// other SatCat5 stream-processing tools.
//
// PacketBuffer also acts as a thread-safe barrier, e.g., for data that is
// written in the interrupt context and read in the general-use context, or
// vice-versa.  For performance reasons, these protections are applied at
// write_finalize() and read_finalize().  Users writing from multiple threads
// or reading from multiple threads should provide their own safety systems.
//
// To allow greater flexibility in memory allocation, the underlying working
// memory is NOT declared as part of this class.  Instead, its address and
// size are arguments to the constructor.
//
// Example unpacketized stream:
//      u8 raw_buffer[1024];
//      PacketBuffer pkt_buffer(raw_buffer, sizeof(raw_buffer));
//
// Example packetized stream (up to 16 queued packets):
//      u8 raw_buffer[1024];
//      PacketBuffer pkt_buffer(raw_buffer, sizeof(raw_buffer), 16);
//
// In typical usage, a user calls write_xx methods to construct a packet
// field by field, then calls write_finalize().  In the event of an overflow
// in the middle of this process, the incomplete partial frame is discarded.
// The user can also trigger this manually by calling write_abort().
//
// Maximum size of each frame is limited to the main buffer size or 64 kiB,
// whichever is smaller.
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        class PacketBuffer
            : public satcat5::io::Writeable
            , public satcat5::io::Readable
        {
        public:
            // Configure this object and link to the underlying working memory.
            // Note: If max_pkt = 0, then packet boundaries are ignored.
            PacketBuffer(u8* buff, unsigned nbytes, unsigned max_pkt=0);

            // Reset buffer contents.
            void clear();

            // Packet-oriented writes.  (See also: "Writeable" class in io_buffer.h)
            // Note: PacketBuffer defines several additional methods.
            u8 get_percent_full() const;        // Overall occupancy (0-100%)
            unsigned get_write_space() const override;  // Max bytes safe to write
            unsigned get_write_partial() const; // Bytes in partial packet (or -1 on overflow)
            void write_bytes(unsigned nbytes, const void* src) override;
            void write_abort() override;        // Revert partially written packet
            bool write_finalize() override;     // Returns true if successful, false on overflow

            // Zero-copy write mode is required for UART interface.
            // * Create an AtomicLock object to ensure thread safety (MANDATORY).
            // * Call zcw_maxlen() to find maximum contiguous write length.
            // * Call zcw_start() to get a pointer to that contiguous buffer.
            // * Call zcw_write(N) once those bytes have been written.
            unsigned zcw_maxlen() const;
            u8* zcw_start();
            void zcw_write(unsigned nbytes);

            // Read data from the buffer.
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
            void read_finalize() override;

            // Due to circular buffer, packet data may not be contiguous.
            // Use get_peek_ready() to find the longest available contiguous segment.
            // Requests that exceed this length will return NULL.
            unsigned get_peek_ready() const;
            const u8* peek(unsigned nbytes) const;

            // Accessor for children that need to delete underlying buffer.
            // (Returned value matches pointer passed to the constructor.)
            inline u8* get_buff_dtor() const {return (u8*)m_pkt_lbuff;}

        protected:
            // Internal functions required for Writeable and Readable API.
            void write_next(u8 data) override;
            void write_overflow() override;
            u8 read_next() override;
            bool can_read_internal(unsigned nbytes) const;
            void consume_internal(unsigned nbytes);

        private:
            // State for the main circular buffer (read domain)
            u8* const m_buff;               // Pointer to backing array
            const unsigned m_buff_size;     // Size of backing array
            unsigned m_buff_rdidx;          // Current read position
            unsigned m_buff_rdcount;        // Count consumed bytes

            // Store packet lengths in an auxiliary buffer (read domain)
            u16* const m_pkt_lbuff;         // Pointer to backing array
            const unsigned m_pkt_maxct;     // Size of backing array
            unsigned m_pkt_rdidx;           // Current read position

            // Working state for writes (write domain)
            unsigned m_next_wrpos;          // Base position for writes
            unsigned m_next_wrlen;          // Working packet length

            // Shared state is constant except for cross-domain events.
            volatile unsigned m_shared_rdavail;
            volatile unsigned m_shared_pktcount;
        };
    }
}
