//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Multipurpose circular buffer
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/types.h>

// Default size is large enough for one full-size Ethernet frame + metadata.
#ifndef SATCAT5_DEFAULT_PKTBUFF
#define SATCAT5_DEFAULT_PKTBUFF     1600    // Buffer size in bytes
#endif

namespace satcat5 {
    namespace io {
        //! The PacketBuffer class is a wrapper for a circular buffer, with
        //! optional logic to support retention of frame/packet boundaries. It
        //! implements the "Readable" and "Writeable" interfaces so that it can
        //! be used with many other SatCat5 stream-processing tools.
        //!
        //! PacketBuffer also acts as a thread-safe barrier, e.g., for data that
        //! is written in the interrupt context and read in the general-use
        //! context, or vice-versa.  For performance reasons, these protections
        //! are applied at write_finalize() and read_finalize().  Users writing
        //! from multiple threads or reading from multiple threads should
        //! provide their own safety systems.
        //!
        //! To allow greater flexibility in memory allocation, the underlying
        //! working memory is NOT declared as part of this class.  Instead, its
        //! address and size are arguments to the constructor.
        //!
        //! Example unpacketized stream:
        //! ```
        //!      u8 raw_buffer[1024];
        //!      PacketBuffer pkt_buffer(raw_buffer, sizeof(raw_buffer));
        //! ```
        //!
        //! Example packetized stream (up to 16 queued packets):
        //! ```
        //!      u8 raw_buffer[1024];
        //!      PacketBuffer pkt_buffer(raw_buffer, sizeof(raw_buffer), 16);
        //! ```
        //!
        //! \see StreamBufferStatic, PacketBufferStatic for simplified
        //! wrappers with a built-in, statically-allocated working buffer.
        //! \see StreamBufferHeap, PacketBufferHeap for wrappers with a
        //! heap-allocated working buffer, if your system has a heap.
        //!
        //! io::Writeable methods are used as normal to construct a packet field
        //! by field. The packet is committed to the buffer during the call to
        //! write_finalize().  In the event of an overflow in the middle of this
        //! process, the incomplete partial frame is discarded via a call to
        //! write_abort().
        //!
        //! Maximum size of each frame is limited to the main buffer size or
        //! 64 kiB, whichever is smaller.
        class PacketBuffer
            : public satcat5::io::Writeable
            , public satcat5::io::Readable
        {
        public:
            //! Configure this object and link to the underlying working memory.
            //! Note: If max_pkt = 0, then packet boundaries are ignored.
            constexpr PacketBuffer(void* buff, unsigned nbytes, unsigned max_pkt=0)
                : m_buff(static_cast<u8*>(buff) + 2*max_pkt)
                , m_buff_size(nbytes - 2*max_pkt)
                , m_buff_rdidx(0)
                , m_buff_rdcount(0)
                , m_pkt_lbuff(static_cast<u16*>(buff))
                , m_pkt_maxct(max_pkt)
                , m_pkt_rdidx(0)
                , m_next_wrpos(0)
                , m_next_wrlen(0)
                , m_shared_rdavail(0)
                , m_shared_pktcount(0)
                {} // No further initialization required

            //! Reset buffer contents.
            void clear();

            //! Get overall buffer occupancy as percentage full (0-100%).
            u8 get_percent_full() const;

            //! Get number of bytes in a partial packet, or -1 on overflow.
            unsigned get_write_partial() const;

            // io::Writeable function implementations.
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
            void write_abort() override;
            bool write_finalize() override;

            //! Zero-copy write (zcw) mode, required for UART interface.
            //! * Create an AtomicLock object to ensure thread safety
            //!   (MANDATORY).
            //! * Call zcw_maxlen() to find maximum contiguous write length.
            //! * Call zcw_start() to get a pointer to that contiguous buffer.
            //! * Call zcw_write(N) once those bytes have been written.
            void zcw_write(unsigned nbytes);
            unsigned zcw_maxlen() const; //!< Max contiguous write length (ZCW).
            u8* zcw_start(); //!< Pointer to a contiguous buffer (ZCW).

            // io::Readable function implementations.
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
            void read_finalize() override;

            //! Peek `nbytes` into the circular buffer. Due to this circular
            //! buffer, packet data may not be contiguous. Use get_peek_ready()
            //! to find the longest available contiguous segment.
            //!
            //! \returns A pointer to packet data, or NULL if `nbytes >
            //! get_peek_ready()`.
            const u8* peek(unsigned nbytes) const;

            //! Find the longest available contiguous segment that can be
            //! requested by peek().
            unsigned get_peek_ready() const;

            //! Accessor for children that need to delete underlying buffer.
            //! Returned value matches pointer passed to the constructor.
            //! @{
            inline u8* get_buff_dtor() const {return (u8*)m_pkt_lbuff;}
            inline unsigned get_buff_size() const {return m_buff_size;}
            //! @}

        protected:
            // Internal functions required for Writeable and Readable APIs.
            void write_next(u8 data) override;
            void write_overflow() override;
            u8 read_next() override;
            bool can_read_internal(unsigned nbytes) const;
            void consume_internal(unsigned nbytes);

        private:
            //! State for the main circular buffer (read domain)
            //! @{
            u8* const m_buff;               // Pointer to backing array
            const unsigned m_buff_size;     // Size of backing array
            unsigned m_buff_rdidx;          // Current read position
            unsigned m_buff_rdcount;        // Count consumed bytes
            //! @}

            //! Store packet lengths in an auxiliary buffer (read domain)
            //! @{
            u16* const m_pkt_lbuff;         // Pointer to backing array
            const unsigned m_pkt_maxct;     // Size of backing array
            unsigned m_pkt_rdidx;           // Current read position
            //! @}

            //! Working state for writes (write domain)
            //! @{
            unsigned m_next_wrpos;          // Base position for writes
            unsigned m_next_wrlen;          // Working packet length
            //! @}

            //! Shared state is constant except for cross-domain events.
            //! @{
            volatile unsigned m_shared_rdavail;
            volatile unsigned m_shared_pktcount;
            //! @}
        };

        //! Packet buffer with statically-allocated working memory.
        //!
        //! This PacketBuffer wrapper retains packet boundaries using
        //! write_finalize(). Calling read_finalize() will discard any
        //! remaining bytes in the current packet, then advance to the
        //! next packet for subsequent reads.  The maximum number of
        //! queued packets is set by the constructor, defaulting to 32.
        //!
        //! The working buffer is statically allocated. For a heap-allocated
        //! equivalent, \see PacketBufferHeap (if your system has a heap).
        //!
        //! Optional template parameter specifies buffer size.  If user does
        //! not specify a size, use SATCAT5_DEFAULT_PKTBUFF = 1600 bytes.
        template<unsigned SIZE = SATCAT5_DEFAULT_PKTBUFF>
        class PacketBufferStatic final : public satcat5::io::PacketBuffer {
        public:
            //! Link the parent object to the statically allocated buffer.
            //! Note: PacketBufferStatic(0) is the same as StreamBufferStatic.
            explicit PacketBufferStatic(unsigned max_pkt = 32)
                : PacketBuffer(m_raw, SIZE, max_pkt), m_raw{} {}
        private:
            u8 m_raw[SIZE];
        };

        //! Stream buffer with statically-allocated working memory.
        //!
        //! This PacketBuffer wrapper does NOT retain packet boundaries;
        //! bytes are written and read as a single contiguous stream.
        //! Calls to write_finalize() are used for staging only, to minimize
        //! thread-synchronization overhead.  When reading, data is consumed
        //! without regard for packet boundaries.  Calls to read_finalize()
        //! will discard all queued bytes and are never required.
        //!
        //! The working buffer is statically allocated. For a heap-allocated
        //! equivalent, \see StreamBufferHeap (if your system has a heap).
        //!
        //! Optional template parameter specifies buffer size.  If user does
        //! not specify a size, use SATCAT5_DEFAULT_PKTBUFF = 1600 bytes.
        template<unsigned SIZE = SATCAT5_DEFAULT_PKTBUFF>
        class StreamBufferStatic final : public satcat5::io::PacketBuffer {
        public:
            //! Link the parent object to the statically allocated buffer.
            StreamBufferStatic()
                : PacketBuffer(m_raw, SIZE, 0), m_raw{} {}
        private:
            u8 m_raw[SIZE];
        };
    }
}
