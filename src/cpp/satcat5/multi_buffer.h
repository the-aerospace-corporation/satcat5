//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Multi-source / multi-sink packet buffer
//
//! \file
//! \details
//! The MultiBuffer class implements a multithreaded buffer for packet
//! data, with multiple source and sink ports that operate concurrently.
//! Each port is first-in / first-out, but the aggregate is non-blocking.
//! It is suitable for use in software-defined switches and routers.
//!
//! To write to the MultiBuffer, instantiate a MultiWriter and use the
//! usual io::Writeable API.  To read from the MultiBuffer, instantiate
//! a MultiReader and use the usual io::Readable API.  Each MultiBuffer
//! can have any number of attached read or write ports.
//!
//! By default, each written packet is sent to every attached read port.
//! Child classes can change this by overriding the "deliver" method.
//!
//! The MultiBuffer operates using a single large pool, allocated separately,
//! that is subdivided into many fine-grained "chunks" (typically ~60 bytes).
//! Internal allocators assign chunks to each port as they write incoming data.
//! A packet is a linked list of such chunks, along with a reference-counter
//! for write-once, read-many operations and garbage collection.
//!
//! Example supporting two read/write ports:
//! ```
//!      u8 raw_buffer[16384];
//!      MultiBuffer multi_buff(raw_buffer, sizeof(raw_buffer));
//!      MultiWriter port1_wr(&multi_buff);
//!      MultiWriter port2_wr(&multi_buff);
//!      MultiReaderSimple port1_rd(&multi_buff);
//!      MultiReaderSimple port2_rd(&multi_buff);
//! ```
//!

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/list.h>
#include <satcat5/types.h>

// Set default: Chunk size for internal allocator.
#ifndef SATCAT5_MBUFF_CHUNK
#define SATCAT5_MBUFF_CHUNK     (64 - sizeof(uintptr_t))
#endif

// Set default: Maximum bytes per packet.
#ifndef SATCAT5_MBUFF_PKTLEN
#define SATCAT5_MBUFF_PKTLEN    2048
#endif

// Set default: Maximum packets in the read queue.
#ifndef SATCAT5_MBUFF_RXPKT
#define SATCAT5_MBUFF_RXPKT     32
#endif

// Set default: Per-byte read timeout, in milliseconds.
#ifndef SATCAT5_MBUFF_TIMEOUT
#define SATCAT5_MBUFF_TIMEOUT   1500
#endif

// Set default: Reserved size for additional packet metadata.
#ifndef SATCAT5_MBUFF_USER
#define SATCAT5_MBUFF_USER      8
#endif

namespace satcat5 {
    namespace io {
        //! Data-structure representing a single fine-grained memory block.
        //! This is used internally, and is not intended for end-users.
        struct MultiChunk final {
        private:
            friend satcat5::util::ListCore;
            satcat5::io::MultiChunk* m_next;
        public:
            constexpr MultiChunk() : m_next(0), m_data{0} {}
            u8 m_data[SATCAT5_MBUFF_CHUNK];
        };

        //! A packet is a linked-list of memory blocks, plus metadata.
        //! The `m_user` field is for additional packet metadata; it is not
        //! used by MultiBuffer, MultiReader, or MultiWriter, but may be
        //! used safely by children of those classes as they see fit.
        //! \copydoc multi_buffer.h
        struct MultiPacket final {
        private:
            //! Linked list pointer used by MultiBuffer::m_rcvd_packets.
            //! Children of MultiReader should not reuse this field for
            //! packets that may use multicast modes (i.e., m_refct > 1).
            friend satcat5::util::ListCore;
            satcat5::io::MultiPacket* m_next;

        public:
            // Data for this packet should only be read by io::MultiReader.
            satcat5::util::List<satcat5::io::MultiChunk> m_chunks;
            unsigned m_length;                  //!< Packet length in bytes
            unsigned m_refct;                   //!< Reference counter
            u16 m_priority;                     //!< Packet priority
            u16 m_pcount;                       //!< Packet counter
            // Metadata for user extensions (see comment above).
            u32 m_user[SATCAT5_MBUFF_USER];     //!< Packet metadata

            //! Peek at the first chunk, up to SATCAT5_MBUFF_CHUNK bytes.
            satcat5::io::ArrayRead peek() const;

            //! Copy the packet contents to the specified destination.
            bool copy_to(satcat5::io::Writeable* wr);

            //! Barebones class for reading data from a MultiPacket. This is the
            //! parent for the "MultiReader", which adds queueing, lifecycle,
            //! and memory-management. Multiple concurrent "Reader" objects may
            //! point to each packet.
            //! \copydoc multi_buffer.h
            class Reader : public satcat5::io::Readable {
            public:
                //! Create a new Reader object.
                explicit Reader(satcat5::io::MultiPacket* pkt = 0);

                //! Get a pointer to the current packet, if active.
                inline satcat5::io::MultiPacket* get_packet() const
                    { return m_read_pkt; }

                //! Reset read state for the designated packet.
                void read_reset(satcat5::io::MultiPacket* pkt);

                // Implement the io::Readable API.
                unsigned get_read_ready() const override;
                bool read_bytes(unsigned nbytes, void* dst) override;
                bool read_consume(unsigned nbytes) override;
                void read_finalize() override;

            protected:
                // Implement the io::Readable API.
                u8 read_next() override;

            private:
                //! Current read state.
                //! @{
                unsigned m_read_pos;
                unsigned m_read_rem;
                satcat5::io::MultiPacket* m_read_pkt;
                satcat5::io::MultiChunk* m_read_chunk;
                //! @}
            };
        };

        //! A multi-source, multi-sink packet buffer.
        //! \copydoc multi_buffer.h
        class MultiBuffer : satcat5::poll::OnDemand {
        public:
            //! Configure this object and link to the working buffer.
            MultiBuffer(u8* buff, unsigned nbytes);

            //! Internal consistency self-test (Optional).
            bool consistency() const;

            //! Query remaining buffer capacity.
            inline unsigned get_free_bytes() const
                { return m_free_bytes; }

            //! Current value of the packet counter.
            inline u16 get_pcount()
                { return m_pcount; }

            //! Optional debug interface gets a carbon copy of each packet.
            void set_debug(satcat5::io::Writeable* debug)
                { m_debug = debug; }

            //! Queue an incoming packet for deferred processing.
            //! Note: This method SHOULD only be called from MultiWriter or its
            //! children. This method is public only for to allow flexibility
            //! in mutual "friend" inheritance rules.
            bool enqueue(satcat5::io::MultiPacket* packet);

            //! Immediately free memory associated with this packet.
            //! This is usually called by MultiReader::read_finalize().
            void free_packet(satcat5::io::MultiPacket* packet);

        protected:
            //! Event handler for deferred packet delivery.
            satcat5::io::MultiPacket* dequeue();
            void poll_demand() override;

            //! Deliver a complete packet to any number of output port(s).
            //! Default implementation broadcasts the packet to every port.
            //! Users MAY override this function to adjust this behavior.
            //! \returns The number of ports that accept the incoming packet.
            virtual unsigned deliver(satcat5::io::MultiPacket* packet);

            //! Memory allocation.
            //! @{
            satcat5::io::MultiChunk* new_chunk();
            satcat5::io::MultiPacket* new_packet();
            //! @}

            // Internal state.
            //! @{
            friend satcat5::io::MultiReader;
            friend satcat5::io::MultiWriter;
            unsigned m_free_bytes;
            u16 m_pcount;
            satcat5::io::Writeable* m_debug;
            satcat5::util::List<satcat5::io::MultiChunk> m_free_chunks;
            satcat5::util::List<satcat5::io::MultiReader> m_read_ports;
            satcat5::util::List<satcat5::io::MultiPacket> m_rcvd_packets;
            //! @}
        };

        //! A port for reading from a MultiBuffer object.
        //! \copydoc multi_buffer.h
        class MultiReader
            : public satcat5::io::MultiPacket::Reader
            , public satcat5::poll::Timer
        {
        public:
            //! Accept a packet from the source buffer?
            //! Default accepts all packets unless this port is disabled or
            //! full.
            //!
            //! Child classes MAY override this method to adjust this policy,
            //! apply filters, or to implement an additional pre-buffer. Child
            //! classes that accept(...) a packet  MUST eventually call either
            //! pkt_push(...) or pkt_free(...) to avoid memory leaks.
            //!
            //! Note: This method SHOULD only be called from MultiBuffer or its
            //! children. This method is public only for to allow flexibility in
            //! mutual "friend" inheritance rules.
            virtual bool accept(satcat5::io::MultiPacket* packet);

            //! Enable or disable this port.
            //! Disabled ports reject all incoming packets.
            void set_port_enable(bool enable)
                { m_port_enable = enable; }

            //! Update the watchdog timeout.
            //! The watchdog is reset each time a byte is read; if data is
            //! available, but nothing is is read, then the Reader discards
            //! everything in the queue.
            inline void set_timeout(unsigned timeout_msec)
                { m_read_timeout = timeout_msec; }

            // Override the basic read_finalize() behavior.
            void read_finalize() override;

        protected:
            //! Constructor and destructor are only accessible to children.
            explicit MultiReader(satcat5::io::MultiBuffer* src);
            ~MultiReader() SATCAT5_OPTIONAL_DTOR;

            //! Push a packet onto the end of a queue or similar data structure.
            //! Child classes MUST implement this method.
            virtual bool pkt_push(satcat5::io::MultiPacket* packet) = 0;

            //! Choose the next packet to start reading, or NULL to stop.
            //! Child classes MUST implement this method.
            virtual satcat5::io::MultiPacket* pkt_pop() = 0;

            //! Helper function for starting a new packet, or NULL to stop.
            void pkt_init(satcat5::io::MultiPacket* packet);

            //! Decrement reference count, free when it reaches zero.
            void pkt_free(satcat5::io::MultiPacket* packet);

            //! Timeouts help prevent resource-hogging.
            void timer_event() override;

            //! Pointer to the source buffer.
            satcat5::io::MultiBuffer* const m_src;

            //! MultiBuffer requires a linked list of attached Readers.
            //! @{
            friend satcat5::util::ListCore;
            satcat5::io::MultiReader* m_next;
            //! @}

            //! Internal state.
            //! @{
            bool m_port_enable;
            unsigned m_read_timeout;
            //! @}
        };

        //! A variant of MultiReader with a simple first-in, first-out queue.
        //! \copydoc multi_buffer.h
        class MultiReaderSimple : public satcat5::io::MultiReader {
        public:
            //! Create this port and link it to the source buffer.
            explicit MultiReaderSimple(satcat5::io::MultiBuffer* src);
            ~MultiReaderSimple() SATCAT5_OPTIONAL_DTOR;

            //! Can this object accept new packets? Required for testing.
            inline bool can_accept() const
                { return m_queue_count < SATCAT5_MBUFF_RXPKT; }

        protected:
            //! Implement the push() and pop() methods.
            //! @{
            bool pkt_push(satcat5::io::MultiPacket* pkt) override;
            satcat5::io::MultiPacket* pkt_pop() override;
            //! @}

        private:
            //! Queue based on a circular buffer.
            //! This has O(1) push and O(1) pop.
            //! @{
            unsigned m_queue_rdidx;
            unsigned m_queue_count;
            satcat5::io::MultiPacket* m_queue[SATCAT5_MBUFF_RXPKT];
            //! @}
        };

        //! A variant of MultiReader that follows priority ordering.
        //! \copydoc multi_buffer.h
        class MultiReaderPriority : public satcat5::io::MultiReader {
        public:
            //! Create this port and link it to the source buffer.
            explicit MultiReaderPriority(satcat5::io::MultiBuffer* src);
            ~MultiReaderPriority() SATCAT5_OPTIONAL_DTOR;

            //! Can this object accept new packets? Required for testing.
            inline bool can_accept() const
                { return m_heap_count < SATCAT5_MBUFF_RXPKT; }

            //! Internal consistency self-test (Optional).
            bool consistency() const;

        protected:
            //! Implement the push() and pop() methods.
            //! @{
            bool pkt_push(satcat5::io::MultiPacket* pkt) override;
            satcat5::io::MultiPacket* pkt_pop() override;
            //! @}

        private:
            //! Return modified priority, with tie-breaker using packet count.
            u32 offset_priority(unsigned idx) const;

            //! Swap two elements and return the new index.
            unsigned swap_index(unsigned prev, unsigned next);

            //! Binary heap sorted by increasing priority.
            //! This has O(log(n)) push and O(log(n)) pop.
            //! @{
            unsigned m_heap_count;
            satcat5::io::MultiPacket* m_heap[SATCAT5_MBUFF_RXPKT];
            //! @}
        };

        //! A port for writing to a MultiBuffer object.
        //! \copydoc multi_buffer.h
        class MultiWriter
            : public satcat5::io::Writeable
            , public satcat5::poll::Timer
        {
        public:
            //! Create this port and link it to the destination buffer.
            explicit MultiWriter(satcat5::io::MultiBuffer* dst);
            ~MultiWriter() SATCAT5_OPTIONAL_DTOR;

            //! Update the maximum allowed packet length.
            //! (Longer packets are terminated to avoid resource hogging.)
            inline void set_max_packet(unsigned max_bytes)
                { m_write_maxlen = max_bytes; }

            //! Set priority of the current packet.
            void set_priority(u16 priority);

            //! Update the watchdog timeout. The watchdog is reset each time a
            //! byte is written; if a partial packet is not finalized or aborted
            //! within the time limit, then it is dicarded.
            inline void set_timeout(unsigned timeout_msec)
                { m_write_timeout = timeout_msec; }

            //! Get current write length.
            inline unsigned get_write_partial() const {return m_write_len;}

            // Implement the io::Writeable API.
            // TODO: Also implement the "ZCW" API from PacketBuffer?
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
            void write_abort() override;
            bool write_finalize() override;

        protected:
            //! Timeouts help prevent resource-hogging.
            void timer_event() override;

            // Implement the io::Writeable API.
            void write_next(u8 data) override;
            void write_overflow() override;

            //! Open a new packet or allocate additional buffers.
            //! \returns The number of bytes that can be written.
            unsigned write_prep();

            //! Pointer to the destination buffer.
            satcat5::io::MultiBuffer* const m_dst;

            //! Current write state.
            //! @{
            satcat5::io::MultiPacket* m_write_pkt;
            satcat5::io::MultiChunk* m_write_tail;
            unsigned m_write_pos;
            unsigned m_write_len;
            unsigned m_write_maxlen;
            unsigned m_write_timeout;
            //! @}
        };
    }
}
