//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
//  * If the object's constructor adds itself to a list, then the object's
//    destructor SHOULD remove itself from that list.
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
                // Add new item to front or back, whichever is simpler.
                satcat5::util::ListCore::push_front(list, item);
            }

            template <class T> static inline
            void add_safe(T*& list, T* item) {
                // Check if list already contains item before adding.
                // (Adding the same item twice can create an infinite loop.)
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
            T** find_ptr(T** list, const T* item) {
                // Find the link pointing to the designated item.
                // (i.e., Usually points to the previous item in the list.)
                T** ptr = list;
                while (1) {
                    if (*ptr == item) return ptr;   // Found a match?
                    if (*ptr == 0) return 0;        // End of list?
                    ptr = &((*ptr)->m_next);
                }
            }

            template <class T> static inline
            bool has_loop(const T* list) {
                // Check if the linked list loops back on itself, using the
                // two-pointer "tortoise and hare" algorithm.
                if (!list) return false;    // Empty list has no loops.
                const T* slow = list;
                const T* fast = list->m_next;
                while (fast && fast->m_next) {
                    if (slow == fast || slow == fast->m_next) return true;
                    slow = slow->m_next;
                    fast = fast->m_next->m_next;
                }
                return false;               // Reached end with no loops.
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
            T* pop_front(T*& list) {
                // Remove the item at the head of the list.
                if (!list) return 0;
                T* item = list;
                list = item->m_next;
                item->m_next = 0;
                return item;
            }

            template <class T> static inline
            void push_front(T*& list, T* item) {
                // Add a new item at the head of the list.
                item->m_next = list;
                list = item;
            }

            template <class T> static inline
            void push_back(T*& list, T* item) {
                // Add a new item at the tail of the list.
                T** ptr = satcat5::util::ListCore::find_ptr<T>(&list, 0);
                *ptr = item;
                item->m_next = 0;
            }

            template <class T> static inline
            void remove(T*& list, T* item) {
                // Remove the designated item from the list.
                T** ptr = satcat5::util::ListCore::find_ptr<T>(&list, item);
                if (ptr) *ptr = item->m_next;
                item->m_next = 0;
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
            inline bool contains(const T* item) const
                {return satcat5::util::ListCore::contains(m_head, item);}
            inline bool has_loop() const
                {return satcat5::util::ListCore::has_loop(m_head);}
            inline unsigned len() const
                {return satcat5::util::ListCore::len(m_head);}
            inline T* next(const T* item) const
                {return satcat5::util::ListCore::next(item);}
            inline T* pop_front()
                {return satcat5::util::ListCore::pop_front(m_head);}
            inline void push_front(T* item)
                {satcat5::util::ListCore::push_front(m_head, item);}
            inline void push_back(T* item)
                {satcat5::util::ListCore::push_back(m_head, item);}
            inline void remove(T* item)
                {satcat5::util::ListCore::remove(m_head, item);}

        protected:
            T* m_head;  // Pointer to first item, zero if empty.
        };
    }
};
