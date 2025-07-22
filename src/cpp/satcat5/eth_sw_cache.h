//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// MAC-address cache plugin for the software-defined Ethernet switch

#pragma once

#include <satcat5/eth_plugin.h>
#include <satcat5/lru_cache.h>

namespace satcat5 {
    namespace eth {
        //! MAC-address cache plugin for the software-defined Ethernet switch.
        //!
        //! All Ethernet switches maintain a cache of recently used MAC
        //! addresses, noting the port associated with each address so that
        //! packets can be directed accordingly.  The switch cannot operate
        //! without this function, using this plugin or a near-equivalent.
        //!
        //! This class defines a SwitchCore plugin with a simple implementation
        //! of such a cache, with an LRU replacement policy.
        //! Configuration methods mimic eth::SwitchConfig.
        //! \see eth::SwitchCache, eth::SwitchCore.
        class SwitchCacheInner : satcat5::eth::PluginCore {
        public:
            //! Implement the required SwitchPlugin API.
            void query(satcat5::eth::PluginPacket& pkt) override;

            //! Enable or disable "miss-as-broadcast" flag for a specific port.
            //! Frames with an unknown destination (i.e., destination MAC not
            //! found in cache) are sent to every port with this flag.  This
            //! method sets the configuration for the specified port index.
            void set_miss_bcast(unsigned port_idx, bool enable);

            //! Enable or disable "miss-as-broadcast" flag for all ports.
            //! Frames with an unknown destination (i.e., destination MAC not
            //! found in cache) are sent to every port with this flag.  This
            //! method sets all ports in a single call. \see set_miss_bcast.
            inline void set_miss_mask(SATCAT5_PMASK_TYPE mask)
                { m_miss_mask = mask; }

            //! Identify which ports are currently in "miss-as-broadcast" mode.
            //! For format description, \see set_miss_mask.
            inline SATCAT5_PMASK_TYPE get_miss_mask() const
                { return m_miss_mask; }

            //! Read or manipulate the contents of the MAC-address table.
            //! All functions return true if successful, false otherwise.
            //! (These mimic the API provided by satcat5::eth::SwitchConfig)
            //!@{
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
            //!@}

        protected:
            //! Data structure for the internal cache.
            struct CacheEntry {
            public:
                u64 m_key;              // MAC address as u64
                unsigned m_port;        // Associated port index
            private:
                friend satcat5::util::LruCache<CacheEntry>;
                CacheEntry* m_next;     // Linked list of cache entries
            };

            //! Constructor accepts a child-allocated array for the cache.
            SwitchCacheInner(
                satcat5::eth::SwitchCore* sw,
                CacheEntry* array, unsigned size);

            //! Destination MAC-address lookup.
            SATCAT5_PMASK_TYPE destination_mask(const PluginPacket& pkt);

            // Internal configuration?
            bool m_learn;                       // Enable learning?
            SATCAT5_PMASK_TYPE m_miss_mask;     // Cache miss policy

            // Backing array and LRU cache for MAC addresses.
            CacheEntry* const m_array;
            const unsigned m_size;
            satcat5::util::LruCache<CacheEntry> m_cache;
        };

        //! Wrapper for SwitchCacheInner with the required working memory.
        //! Most users should instantiate this instead of SwitchCacheInner.
        template <unsigned SIZE = 64>
        class SwitchCache : public satcat5::eth::SwitchCacheInner {
        public:
            //! Link this cache to the designated SwitchCore.
            explicit SwitchCache(satcat5::eth::SwitchCore* sw)
                : SwitchCacheInner(sw, m_table, SIZE) {}
        protected:
            satcat5::eth::SwitchCacheInner::CacheEntry m_table[SIZE];
        };
    }
}
