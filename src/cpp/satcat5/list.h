//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Templated functions for manipulating singly-linked lists.
//
// Several SatCat5 classes use singly-linked lists.  To reduce code
// duplication, we define the "ListCore" function templates for:
//  * Adding an item to the head of a list.
//  * Checking if an item is already contained in a list.
//  * Counting the number of items in a list.
//  * Removing an item from any point in a list.
//
// These functions are required for safe initialization of certain global
// variables, such as those found in satcat5/interrupts.cc.  However, most
// other users should use the simplified "List" wrapper class.
//
// The requirements for items using these either format are:
//  * The object MUST declare itself as a friend of satcat5::util::ListCore.
//  * The object MUST be a class or struct with a member named "m_next"
//    that is a pointer to the same type of object.
//  * The pointer SHOULD generally be marked as "private" or "protected".
//  * The object MUST NOT add itself to a list more than once.
//  * The object MUST remove itself from any list if it is destroyed.
//
// Caller is responsible for calling AtomicLock if required.
//

#pragma once

namespace satcat5 {
    namespace util {
        class ListCore {
        public:
            template <class T> static inline
            void add(T*& list, T* item) {
                // Put the new item at the head of the list.
                item->m_next = list;
                list = item;
            }

            template <class T> static inline
            void add_safe(T*& list, T* item) {
                // Check if list already contains item before adding.
                if (!satcat5::util::ListCore::contains(list, item))
                    satcat5::util::ListCore::add(list, item);
            }

            template <class T> static inline
            bool contains(const T* list, const T* item) {
                // Scan the list, looking for the item in question.
                const T* ptr = list;
                while (ptr) {
                    if (ptr == item) return true;
                    ptr = ptr->m_next;
                }
                return false;
            }

            template <class T> static inline
            unsigned len(const T* list) {
                // Traverse the linked list to count its length.
                unsigned count = 0;
                const T* ptr = list;
                while (ptr) {
                    ++count;
                    ptr = ptr->m_next;
                }
                return count;
            }

            template <class T> static inline
            T* next(const T* item) {
                // Fetch pointer to the next item (often private)
                return item->m_next;
            }

            template <class T> static inline
            void remove(T*& list, T* item) {
                if (list == item) {
                    // Special case for the head of list.
                    list = item->m_next;
                } else {
                    // Otherwise, scan the list...
                    T* ptr = list;
                    while (ptr) {
                        if (ptr->m_next == item) {
                            ptr->m_next = item->m_next;
                            break;
                        } else {
                            ptr = ptr->m_next;
                        }
                    }
                }
            }
        };

        template <class T> class List final {
        public:
            List() : m_head(0) {}   // Constructor = Empty list
            ~List() {}              // No action required

            T* head() const {return m_head;}

            inline void add(T* item)
                {satcat5::util::ListCore::add(m_head, item);}
            inline void add_safe(T* item)
                {satcat5::util::ListCore::add_safe(m_head, item);}
            inline bool contains(const T* item)
                {return satcat5::util::ListCore::contains(m_head, item);}
            inline unsigned len() const
                {return satcat5::util::ListCore::len(m_head);}
            inline T* next(const T* item) const
                {return satcat5::util::ListCore::next(item);}
            inline void remove(T* item)
                {satcat5::util::ListCore::remove(m_head, item);}

        protected:
            T* m_head;  // Pointer to first item, zero if empty.
        };
    }
};
