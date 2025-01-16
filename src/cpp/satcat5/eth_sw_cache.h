//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// MAC-address cache plugin for the software-defined Ethernet switch
//
// All Ethernet switches maintain a cache of recently used MAC addresses,
// noting the port associated with each address so that packets can be
// directed accordingly.  This file defines a SwitchCore plugin with a
// simple implementation of such a cache.
//

#pragma once

#include <satcat5/eth_switch.h>
#include <satcat5/lru_cache.h>

namespace satcat5 {
    namespace eth {
        // MAC-address lookup using a SatCat5 LRU-Cache.
        // Configuration methods mimic the eth::SwitchConfig API.
        // (See also: SwitchCache template, defined below.)
        class SwitchCacheInner : satcat5::eth::SwitchPlugin {
        public:
            // Implement the required SwitchPlugin API.
            bool query(PacketMeta& pkt) override;

            // Enable or disable "miss-as-broadcast" flag on the specified port
            // index.  Frames with an unknown destination (i.e., destination
            // MAC not found in cache) are sent to every port with this flag.
            void set_miss_bcast(unsigned port_idx, bool enable);

            // Identify which ports are currently in "miss-as-broadcast" mode.
            inline SATCAT5_PMASK_TYPE get_miss_mask() { return m_miss_mask; }

            // Read or manipulate the contents of the MAC-address table.
            // All functions return true if successful, false otherwise.
            // (These mimic the API provided by satcat5::eth::SwitchConfig)
            inline unsigned mactbl_size() const         // Read maximum table length
                { return m_size; }
            bool mactbl_read(                           // Read Nth entry from table
                unsigned tbl_idx,                       // Table index to be read
                unsigned& port_idx,                     // Resulting port index
                satcat5::eth::MacAddr& mac_addr);       // Resulting MAC address
            bool mactbl_write(                          // Write new entry to table
                unsigned port_idx,                      // New port index
                const satcat5::eth::MacAddr& mac_addr); // New MAC address
            inline bool mactbl_clear()                  // Clear table contents
                { m_cache.clear(); return true; }
            inline bool mactbl_learn(bool enable)       // Enable automatic learning?
                { m_learn = enable; return true; }

        protected:
            // Data structure for the internal cache.
            struct CacheEntry {
            public:
                u64 m_key;              // MAC address as u64
                unsigned m_port;        // Associated port index
            private:
                friend satcat5::util::LruCache<CacheEntry>;
                CacheEntry* m_next;     // Linked list of cache entries
            };

            // Constructor accepts a child-allocated array for the cache.
            SwitchCacheInner(
                satcat5::eth::SwitchCore* sw,
                CacheEntry* array, unsigned size);

            // Destination MAC-address lookup.
            SATCAT5_PMASK_TYPE destination_mask(const PacketMeta& pkt);

            // Internal configuration?
            bool m_learn;                       // Enable learning?
            SATCAT5_PMASK_TYPE m_miss_mask;     // Cache miss policy

            // Backing array and LRU cache for MAC addresses.
            CacheEntry* const m_array;
            const unsigned m_size;
            satcat5::util::LruCache<CacheEntry> m_cache;
        };

        // Wrapper for SwitchCacheInner with the required working memory.
        // (Most users should instantiate this instead of SwitchCacheInner.)
        template <unsigned SIZE = 64>
        class SwitchCache : public satcat5::eth::SwitchCacheInner {
        public:
            explicit SwitchCache(satcat5::eth::SwitchCore* sw)
                : SwitchCacheInner(sw, m_table, SIZE) {}
        protected:
            satcat5::eth::SwitchCacheInner::CacheEntry m_table[SIZE];
        };
    }
}
