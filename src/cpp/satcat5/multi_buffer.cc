//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/interrupts.h>
#include <satcat5/multi_buffer.h>
#include <satcat5/utils.h>

using satcat5::io::MultiBuffer;
using satcat5::io::MultiChunk;
using satcat5::io::MultiPacket;
using satcat5::io::MultiReader;
using satcat5::io::MultiReaderPriority;
using satcat5::io::MultiReaderSimple;
using satcat5::io::MultiWriter;
using satcat5::irq::AtomicLock;
using satcat5::util::ListCore;
using satcat5::util::min_unsigned;
using satcat5::util::modulo_add_uns;

// MultiPacket allocation is pulled from the same pool as chunk
// allocation, so we require the sizes to be compatible.
static_assert(sizeof(MultiPacket) <= sizeof(MultiChunk),
    "MultiChunk must be large enough to reinterpret as a MultiPacket.");

// Label for AtomicLock statistics tracking.
static const char* LBL_MBUFF = "MBUFF";

satcat5::io::ArrayRead MultiPacket::peek() const {
    unsigned max_peek = min_unsigned(SATCAT5_MBUFF_CHUNK, m_length);
    return satcat5::io::ArrayRead(m_chunks.head()->m_data, max_peek);
}

bool MultiPacket::copy_to(satcat5::io::Writeable* wr) const {
    MultiPacket::Reader rd(this);
    return rd.copy_and_finalize(wr);
}

MultiPacket::Reader::Reader(const MultiPacket* pkt)
    : m_read_pos(0)
    , m_read_rem(0)
    , m_read_pkt(0)
    , m_read_chunk(0)
{
    read_reset(pkt);
}

void MultiPacket::Reader::read_reset(const MultiPacket* packet) {
    // Reset read state and load the first chunk if applicable.
    m_read_pos = 0;
    m_read_pkt = packet;
    if (packet) {
        m_read_rem = packet->m_length;
        m_read_chunk = packet->m_chunks.head();
    } else {
        m_read_rem = 0;
        m_read_chunk = 0;
    }
}

unsigned MultiPacket::Reader::get_read_ready() const {
    // Remaining bytes in current packet.
    return m_read_rem;
}

bool MultiPacket::Reader::read_bytes(unsigned nbytes, void* dst) {
    // Read one chunk at a time until finished...
    if (nbytes > m_read_rem) return false;
    u8* dst8 = (u8*)dst;
    while (nbytes) {
        // Stop at end of request or end of chunk, whichever comes first.
        unsigned chunk = SATCAT5_MBUFF_CHUNK - m_read_pos;
        unsigned nread = min_unsigned(nbytes, chunk);
        if (dst8) memcpy(dst8, m_read_chunk->m_data + m_read_pos, nread);
        // Advance to the next chunk?
        if (nread == chunk) m_read_chunk = m_read_pkt->m_chunks.next(m_read_chunk);
        m_read_pos = modulo_add_uns(m_read_pos + nread, SATCAT5_MBUFF_CHUNK);
        // Increment the read/write position.
        if (dst8) dst8  += nread;
        nbytes          -= nread;
        m_read_rem      -= nread;
    }
    return true;
}

bool MultiPacket::Reader::read_consume(unsigned nbytes) {
    return read_bytes(nbytes, 0);
}

void MultiPacket::Reader::read_finalize() {
    read_reset(m_read_pkt);
}

u8 MultiPacket::Reader::read_next() {
    // Read a single byte from the current chunk.
    --m_read_rem;
    u8 temp = m_read_chunk->m_data[m_read_pos];
    // Advance to the next chunk if applicable.
    if (++m_read_pos >= SATCAT5_MBUFF_CHUNK) {
        m_read_chunk = m_read_pkt->m_chunks.next(m_read_chunk);
        m_read_pos = 0;
    }
    return temp;
}

MultiPacket::Overwriter::Overwriter(satcat5::io::MultiPacket* pkt)
    : m_write_pos(0)
    , m_write_rem(pkt->m_length)
    , m_write_tot(0)
    , m_write_chunk(pkt->m_chunks.head())
{
    // Nothing else to initialize.
}

unsigned MultiPacket::Overwriter::get_write_space() const {
    return m_write_rem;
}

void MultiPacket::Overwriter::write_bytes(unsigned nbytes, const void* src) {
    // Write one chunk at a time until finished...
    if (nbytes > m_write_rem) return;
    u8* src8 = (u8*)src;
    while (nbytes) {
        // Stop at end of request or end of chunk, whichever comes first.
        unsigned chunk = SATCAT5_MBUFF_CHUNK - m_write_pos;
        unsigned ncopy = min_unsigned(nbytes, chunk);
        memcpy(m_write_chunk->m_data + m_write_pos, src8, ncopy);
        // Advance to the next chunk?
        if (ncopy == chunk) m_write_chunk = ListCore::next(m_write_chunk);
        m_write_pos = modulo_add_uns(m_write_pos + ncopy, SATCAT5_MBUFF_CHUNK);
        // Increment the read/write position.
        src8        += ncopy;
        nbytes      -= ncopy;
        m_write_rem -= ncopy;
        m_write_tot += ncopy;
    }
}

void MultiPacket::Overwriter::write_next(u8 data) {
    // Write a single byte to the current chunk.
    --m_write_rem; ++m_write_tot;
    m_write_chunk->m_data[m_write_pos] = data;
    // Advance to the next chunk if applicable.
    if (++m_write_pos >= SATCAT5_MBUFF_CHUNK) {
        m_write_chunk = ListCore::next(m_write_chunk);
        m_write_pos = 0;
    }
}

MultiBuffer::MultiBuffer(u8* buff, unsigned nbytes)
    : m_free_bytes(0)
    , m_pcount(0)
    , m_free_chunks()
    , m_read_ports()
    , m_rcvd_packets()
{
    // Initialize the list of free sub-buffers.
    MultiChunk* temp = reinterpret_cast<MultiChunk*>(buff);
    while (nbytes >= sizeof(MultiChunk)) {
        m_free_chunks.add(temp);
        m_free_bytes += SATCAT5_MBUFF_CHUNK;
        ++temp; nbytes -= sizeof(MultiChunk);
    }
}

bool MultiBuffer::consistency() const {
    // Compare the list of free chunks against m_free_count.
    AtomicLock lock(LBL_MBUFF);
    if (m_free_chunks.has_loop()) return false;
    unsigned free_count = m_free_chunks.len() * SATCAT5_MBUFF_CHUNK;
    return free_count == m_free_bytes;
}

bool MultiBuffer::enqueue(MultiPacket* packet) {
    // Push new packet onto the thread-safe delivery queue.
    {
        AtomicLock lock(LBL_MBUFF);
        packet->m_pcount = ++m_pcount;
        m_rcvd_packets.push_back(packet);
    }
    // Calling deliver() directly is too much work for an ISR.
    // Instead, request deferred callback to poll_demand().
    request_poll();
    return true;
}

MultiPacket* MultiBuffer::dequeue() {
    // Pop next packet from the thread-safe delivery queue.
    AtomicLock lock(LBL_MBUFF);
    return m_rcvd_packets.pop_front();
}

void MultiBuffer::poll_demand() {
    // Delivery processing for each packet, using child's "deliver" method:
    //  * Result = 0: No outputs accepted the packet, discard it immediately.
    //  * Result = 1: Matches new_packet() default, take no further action.
    //      This code may be used safely if the packet has already been freed.
    //  * Result > 1: Multiple outputs accepted the packet, update m_refct.
    while (MultiPacket* pkt = dequeue()) {
        unsigned result = deliver(pkt);
        if (result == 0) free_packet(pkt);
        if (result > 1) pkt->m_refct = result;
    }
}

unsigned MultiBuffer::deliver(MultiPacket* packet) {
    // Attempt to deliver the new packet to every port.
    // (Most child classes will override this behavior.)
    unsigned count = 0;
    MultiReader* ptr = m_read_ports.head();
    while (ptr) {
        if (ptr->accept(packet)) ++count;
        ptr = m_read_ports.next(ptr);
    }
    return count;
}

MultiChunk* MultiBuffer::new_chunk() {
    // Pop the next item (if any) from the list of free buffers.
    AtomicLock lock(LBL_MBUFF);
    MultiChunk* tmp = m_free_chunks.pop_front();
    if (tmp) m_free_bytes -= SATCAT5_MBUFF_CHUNK;
    return tmp;
}

MultiPacket* MultiBuffer::new_packet() {
    // Request a free buffer, treating the pointer as a MultiPacket.
    // (Also pre-allocate the first chunk for the working buffer.)
    MultiPacket* pkt = reinterpret_cast<MultiPacket*>(new_chunk());
    if (pkt) {
        pkt->m_chunks.reset(new_chunk());
        pkt->m_length = 0;
        pkt->m_refct = 1;
        pkt->m_priority = 0;
        pkt->m_pcount = 0;
        memset(pkt->m_user, 0, sizeof(pkt->m_user));
    }
    return pkt;
}

void MultiBuffer::free_packet(MultiPacket* packet) {
    // Count the number of buffers we're about to return.
    unsigned count = 1 + packet->m_chunks.len();
    // Thread-safe return of each chunk and the object itself.
    AtomicLock lock(LBL_MBUFF);
    m_free_bytes += count * SATCAT5_MBUFF_CHUNK;
    m_free_chunks.add_list(packet->m_chunks);
    m_free_chunks.add(reinterpret_cast<MultiChunk*>(packet));
}

MultiReader::MultiReader(MultiBuffer* src)
    : Reader(0)
    , m_src(src)
    , m_next(0)
    , m_port_enable(true)
    , m_read_timeout(SATCAT5_MBUFF_TIMEOUT)
{
    // Add ourselves to the list of active ports.
    m_src->m_read_ports.add(this);
}

#if SATCAT5_ALLOW_DELETION
MultiReader::~MultiReader() {
    // Cleanup the active packet and the list of active ports.
    // Note: Child destructor is called first and MUST clean up its own
    //  working queue, because it is no longer safe to call child methods.
    if (get_packet()) pkt_free(get_packet());
    m_src->m_read_ports.remove(this);
}
#endif

bool MultiReader::accept(MultiPacket* packet) {
    // Default accepts all packets unless this port is disabled or full.
    bool ok = m_port_enable && pkt_push(packet);
    // If we were previously idle, load the packet and request follow-up.
    if (ok && !get_packet()) {
        pkt_init(pkt_pop());
        request_poll();
    }
    return ok;
}

void MultiReader::flush() {
    // Discard all queued packets.
    while (get_packet()) read_finalize();
}

void MultiReader::read_finalize() {
    // Cleanup current packet and start the next one.
    // (Ignore this request if there is no active packet.)
    if (get_packet()) {
        pkt_free(get_packet());
        pkt_init(pkt_pop());
    }
}

void MultiReader::pkt_init(MultiPacket* packet) {
    // Reset read state, then restart or cancel the watchdog timer.
    read_reset(packet);
    if (packet) {
        timer_once(m_read_timeout);
    } else {
        timer_stop();
    }
}

void MultiReader::pkt_free(MultiPacket* packet) {
    // Decrement reference counter, free when it reaches zero.
    if (--(packet->m_refct) == 0) m_src->free_packet(packet);
}

void MultiReader::timer_event() {
    // Watchdog timeout, discard all packets to prevent resource hogging.
    // (The most likely cause is a UART port that's stuck or disconnected.)
    flush();
}

MultiReaderSimple::MultiReaderSimple(MultiBuffer* src)
    : MultiReader(src)
    , m_queue_rdidx(0)
    , m_queue_count(0)
    , m_queue{0}
{
    // Nothing else to initialize.
}

#if SATCAT5_ALLOW_DELETION
MultiReaderSimple::~MultiReaderSimple() {
    // Free any packets still waiting in the queue.
    while (auto pkt = pkt_pop()) pkt_free(pkt);
}
#endif

bool MultiReaderSimple::pkt_push(MultiPacket* packet) {
    AtomicLock lock(LBL_MBUFF);
    // Is this port able to accept new data?
    if (m_queue_count >= SATCAT5_MBUFF_RXPKT) return false;
    // Push the new pointer onto the circular buffer.
    unsigned wridx = modulo_add_uns(m_queue_rdidx + m_queue_count, SATCAT5_MBUFF_RXPKT);
    m_queue[wridx] = packet;
    ++m_queue_count;
    return true;
}

MultiPacket* MultiReaderSimple::pkt_pop() {
    AtomicLock lock(LBL_MBUFF);
    // Pop first element unless the queue is empty.
    if (m_queue_count == 0) return 0;
    MultiPacket* next = m_queue[m_queue_rdidx];
    // Update the circular buffer state.
    m_queue_rdidx = modulo_add_uns(m_queue_rdidx + 1, SATCAT5_MBUFF_RXPKT);
    --m_queue_count;
    return next;
}

MultiReaderPriority::MultiReaderPriority(MultiBuffer* src)
    : MultiReader(src)
    , m_heap_count(0)
    , m_heap{0}
{
    // Nothing else to initialize.
}

#if SATCAT5_ALLOW_DELETION
MultiReaderPriority::~MultiReaderPriority() {
    // Free any packets still waiting in the queue.
    while (auto pkt = pkt_pop()) pkt_free(pkt);
}
#endif

bool MultiReaderPriority::consistency() const {
    // Each node is a binary-tree heap is greater than its immediate children.
    // (This is necessary and sufficient to show the entire tree is correct.)
    for (unsigned a = 0 ; a < m_heap_count ; ++a) {
        u32 pa = offset_priority(a);
        u32 pl = offset_priority(2*a + 1);
        u32 pr = offset_priority(2*a + 2);
        if (pa < pl || pa < pr) return false;
    }
    return true;
}

bool MultiReaderPriority::pkt_push(MultiPacket* packet) {
    AtomicLock lock(LBL_MBUFF);
    // Is this port able to accept new data?
    if (m_heap_count >= SATCAT5_MBUFF_RXPKT) return false;
    // Push the new pointer onto the end of the heap.
    unsigned idx = m_heap_count++;
    m_heap[idx] = packet;
    // Swap elements as needed to restore binary-tree sort.
    // https://en.wikipedia.org/wiki/Binary_heap#Insert
    while (idx > 0) {
        unsigned parent = (idx - 1) / 2;
        if (offset_priority(parent) >= offset_priority(idx)) break;
        idx = swap_index(idx, parent);
    }
    return true;
}

MultiPacket* MultiReaderPriority::pkt_pop() {
    AtomicLock lock(LBL_MBUFF);
    // Pop root element unless the heap is empty.
    if (m_heap_count == 0) return 0;
    MultiPacket* next = m_heap[0];
    // Move last remaining element to the root of the tree.
    m_heap[0] = m_heap[--m_heap_count];
    // Swap elements as needed to restore binary-tree sort.
    // https://en.wikipedia.org/wiki/Binary_heap#Extract
    unsigned idx = 0;
    while (idx < m_heap_count) {
        unsigned ll = 2*idx + 1;                // Index of left child
        unsigned rr = 2*idx + 2;                // Index of right child
        unsigned pi = offset_priority(idx);
        unsigned pl = offset_priority(ll);
        unsigned pr = offset_priority(rr);
        if ((pi > pl) && (pi > pr)) break;      // Stop once sorted
        idx = swap_index(idx, pl >= pr ? ll : rr);
    }
    return next;
}

u32 MultiReaderPriority::offset_priority(unsigned idx) const {
    // Calculate effective packet priority, with tiebreaker by age.
    // Note: Difference in u16 pcount values will wrap correctly, unless
    //  a low priority packet is stuck behind 32k high-priority packets.
    if (idx >= m_heap_count) return 0;  // No such element?
    u32 age = (m_src->get_pcount() - m_heap[idx]->m_pcount) & 0x7FFF;
    u32 pri = m_heap[idx]->m_priority;
    return 65536 * pri + age + 1;
}


unsigned MultiReaderPriority::swap_index(unsigned prev, unsigned next) {
    MultiPacket* tmp = m_heap[prev];
    m_heap[prev] = m_heap[next];
    m_heap[next] = tmp;
    return next;
}

MultiWriter::MultiWriter(MultiBuffer* dst)
    : m_dst(dst)
    , m_write_pkt(0)
    , m_write_tail(0)
    , m_write_pos(0)
    , m_write_len(0)
    , m_write_maxlen(SATCAT5_MBUFF_PKTLEN)
    , m_write_timeout(SATCAT5_MBUFF_TIMEOUT)
{
    // Nothing else to initialize.
}

#if SATCAT5_ALLOW_DELETION
MultiWriter::~MultiWriter() {
    // Cleanup any work in progress.
    if (m_write_pkt) m_dst->free_packet(m_write_pkt);
}
#endif

void MultiWriter::set_priority(u16 priority) {
    if (m_write_pkt) m_write_pkt->m_priority = priority;
}

unsigned MultiWriter::get_write_space() const {
    // Remaining space may be limited by policy or by buffer space.
    if (m_write_len >= m_write_maxlen) return 0;
    unsigned pkrem = m_write_maxlen - m_write_len;
    unsigned alloc = m_dst->m_free_bytes;
    if (m_write_tail) alloc += SATCAT5_MBUFF_CHUNK - m_write_pos;
    return min_unsigned(pkrem, alloc);
}

void MultiWriter::write_bytes(unsigned nbytes, const void* src) {
    // Reset the watchdog timer.
    timer_once(m_write_timeout);
    // Abort writes that cannot be completed.
    if (nbytes > get_write_space()) {write_overflow(); return;}
    // Write one chunk at a time until finished...
    const u8* src8 = (const u8*)src;
    while (nbytes) {
        // Are we able to write at least one more byte?
        unsigned chunk = write_prep();
        if (!chunk) break;
        // Stop at end of request or end of chunk, whichever comes first.
        unsigned nwrite = min_unsigned(nbytes, chunk);
        memcpy(m_write_tail->m_data + m_write_pos, src8, nwrite);
        // Increment the write position.
        nbytes      -= nwrite;
        src8        += nwrite;
        m_write_pos += nwrite;
        m_write_len += nwrite;
    }
    // Unable to complete requested write?
    if (nbytes) write_overflow();
}

void MultiWriter::timer_event() {
    // Watchdog timeout waiting for a partial packet.
    // (The most likely cause is a UART port that's stuck or disconnected.)
    write_abort();
}

void MultiWriter::write_abort() {
    // Free any open buffers and return to the idle state.
    if (m_write_pkt) m_dst->free_packet(m_write_pkt);
    timer_stop();
    m_write_pkt  = 0;
    m_write_tail = 0;
    m_write_pos  = 0;
    m_write_len  = 0;
}

bool MultiWriter::write_finalize() {
    // Deliver valid packets to the MultiBuffer for processing.
    // (This calls MultiBuffer::deliver() or an override of that method.)
    MultiPacket* pkt = prepare_pkt();
    return pkt && m_dst->enqueue(pkt);
}

bool MultiWriter::write_bypass(MultiReader* dst) {
    // Attempt delivery directly to the specified MultiReader.
    // (This does NOT pass through MultiBuffer::deliver().)
    MultiPacket* pkt = prepare_pkt();
    bool rcvd = pkt && dst->accept(pkt);
    // If the attempt failed, free associated memory.
    if (pkt && !rcvd) m_dst->free_packet(pkt);
    return rcvd;
}

void MultiWriter::write_next(u8 data) {
    // Reset the watchdog timer.
    timer_once(m_write_timeout);
    // Do we need to allocate additional memory?
    if (write_prep()) {
        // Write a single byte.
        m_write_tail->m_data[m_write_pos] = data;
        ++m_write_pos;
        ++m_write_len;
    } else {
        // Note: This should be reachable only through interrupt race
        // conditions, which are difficult to reproduce in unit tests.
        write_overflow(); // GCOVR_EXCL_LINE
    }
}

void MultiWriter::write_overflow() {
    // Flag the current packet as undeliverable, and free the working buffer.
    // Continued writes are discarded until write_finalize() or write_abort().
    m_write_len = UINT_MAX;
    if (m_write_pkt) {
        m_dst->free_packet(m_write_pkt);
        m_write_pkt = 0;
        m_write_tail = 0;
    }
}

unsigned MultiWriter::write_prep() {
    if (m_write_len >= m_write_maxlen) {
        // Overflow state, abort immediately.
        // Note: This should be reachable only through interrupt race
        // conditions, which are difficult to reproduce in unit tests.
        return 0;   // GCOVR_EXCL_LINE
    } else if (!m_write_pkt) {
        // Attempt to open a new packet.
        m_write_len = 0;
        m_write_pos = 0;
        m_write_pkt = m_dst->new_packet();
        if (!m_write_pkt) return 0;
        // Update pointer to the first/last/only allocated chunk.
        // If new_packet() wasn't able to allocate one, abort.
        m_write_tail = m_write_pkt->m_chunks.head();
        if (!m_write_tail) return 0;
    } else if (m_write_pos >= SATCAT5_MBUFF_CHUNK) {
        // Attempt to allocate another chunk.
        MultiChunk* tmp = m_dst->new_chunk();
        if (!tmp) return 0;
        // Add the new chunk to the end of the linked list.
        // We know the tail, so insert_after() is faster than push_back().
        m_write_pos = 0;
        m_write_pkt->m_chunks.insert_after(m_write_tail, tmp);
        m_write_tail = tmp;
    }
    return SATCAT5_MBUFF_CHUNK - m_write_pos;
}

satcat5::io::MultiPacket* MultiWriter::prepare_pkt() {
    MultiPacket* tmp = nullptr;
    if (m_write_pkt && m_write_len < UINT_MAX) {
        // Return value is the active packet.
        tmp           = m_write_pkt;
        tmp->m_length = m_write_len;
        // Reset internal state.
        timer_stop();
        m_write_pkt  = 0;
        m_write_tail = 0;
        m_write_pos  = 0;
        m_write_len  = 0;
    } else {
        // Reset to a known-good state.
        write_abort();
    }
    return tmp;
}
