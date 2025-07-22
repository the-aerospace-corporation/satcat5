//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Template class implementing a least-recently-used (LRU) cache

#pragma once

namespace satcat5 {
    namespace util {
        //! Template class implementing a least-recently-used (LRU) cache.
        //!
        //! The "LruCache" template defines a searchable key-value store with a
        //! fixed maximum size.  Querying a given key returns a pointer to the
        //! stored key if it exists, or a newly-created entry otherwise.
        //! If necessary, the oldest entry is evicted to make room.
        //!
        //! The requirements for items using these this template are:
        //!  * The object MUST declare itself as a friend of satcat5::util::LruCache.
        //!    e.g., "friend satcat5::util::LruCache<MyClassName>;"
        //!  * The object MUST be a "plain-old-data" class or struct with:
        //!      * Member "m_next" as a pointer to the same type of object.
        //!      * Member "m_key" as any type implementing operator= and operator==.
        //!      * Note: Both "m_next" and "m_key" MUST NOT be declared as const.
        //!  * The object MUST initialize the m_next pointer to zero.
        //!  * The m_next pointer SHOULD generally be marked as "private".
        //!    (The object SHOULD NOT access the pointer except through LruCache.)
        //!
        //! Internally, the class uses a singly-linked list of key-value pairs.
        //! For simplicity, search is performed linearly by checking each entry.
        //! The list is maintained in most-recently-used order, overwriting the tail
        //! as needed when eviction is required.
        template <class T> class LruCache {
        public:
            //! Given a backing array, initialize an empty cache.
            LruCache(T* array, unsigned count) : m_free(array), m_list(0) {
                // Set pointers to create a linked list of free elements.
                // Everything else is don't-care.
                for (unsigned a = 0 ; a < count-1 ; ++a) {
                    array[a].m_next = array + a + 1;
                }
                array[count-1].m_next = 0;
            }

            //! Reset this cache to the empty state.
            void clear() {
                while (m_list) {
                    T* item = m_list;
                    m_list = item->m_next;
                    item->m_next = m_free;
                    m_free = item;
                }
            }

            //! Is this an empty list?
            inline bool is_empty() const {
                return !m_list;
            }

            //! Count the number of stored items.
            unsigned len() const {
                unsigned count = 0;
                const T* item = m_list;
                while (item) {
                    ++count;
                    item = item->m_next;
                }
                return count;
            }

            //! Query the cache without modifying its contents.
            //! Returns null pointer if no match is found.
            T* find(const decltype(T::m_key)& key) {
                T* ptr = m_list;
                while (ptr && !(ptr->m_key == key)) {
                    ptr = ptr->m_next;
                }
                return ptr;
            }

            //! Query the cache, updating the recently-used list.
            //! Returns a new or existing entry matching the given key.
            //! If the cache is full, evicts the oldest entry to make room.
            T* query(const decltype(T::m_key)& key) {
                // Handling for special cases.
                if (!m_list) {
                    // Push first item onto an empty list.
                    m_free->m_key = key;
                    return update(0, m_free);
                } else if (m_list->m_key == key) {
                    // Match on first item is an LRU no-op.
                    return m_list;
                }
                // Iterate over the list, from second item to the tail...
                T** ptr = &m_list->m_next;
                while (*ptr) {
                    if ((*ptr)->m_key == key) return update(ptr, *ptr);
                    if ((*ptr)->m_next) ptr = &((*ptr)->m_next);
                    else break;
                }
                // Reached end of list without finding a match.
                if (m_free) {
                    // Create a new entry.
                    m_free->m_key = key;
                    return update(0, m_free);
                } else {
                    // Otherwise, evict by overwriting the tail.
                    (*ptr)->m_key = key;
                    return update(ptr, *ptr);
                }
            }

        private:
            // Found a match? Given a pointer to the previous element,
            // reinsert the matching element at the head of the list.
            T* update(T** prev, T* item) {
                if (item == m_free) m_free = m_free->m_next;
                if (prev) *prev = (*prev)->m_next;
                item->m_next = m_list;
                m_list = item;
                return item;
            }

            T* m_free;          // Linked-list of unused slots.
            T* m_list;          // Linked-list in most-recently-used order.
        };
    }
};
