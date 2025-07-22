//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Templated functions for manipulating singly-linked lists.
//!
//!\details
//! Several SatCat5 classes use singly-linked lists.  To reduce code
//! duplication, we define the "ListCore" function templates for:
//!  * Adding an item to the head of a list.
//!  * Checking if an item is already contained in a list.
//!  * Counting the number of items in a list.
//!  * Removing an item from any point in a list.
//!
//! These functions are required for safe initialization of certain global
//! variables, such as those found in satcat5/interrupts.cc.  However, most
//! other users should use the simplified "List" wrapper class.
//!
//! The requirements for items using these either format are:
//!  * The object MUST declare itself as a friend of satcat5::util::ListCore.
//!  * The object MUST be a class or struct with a member named "m_next"
//!    that is a pointer to the same type of object.
//!  * The object MUST initialize the pointer to zero. It MUST NOT otherwise
//!    access the pointer except through SatCat5 ListCore or List functions.
//!  * The object MUST NOT add itself to more than one list using a given
//!    "m_next" pointer.  Objects MAY safely inherit more than one "m_next"
//!    pointer from different parents.
//!  * The pointer SHOULD generally be marked as "private".
//!    This reduces the chance of namespace conflicts (see previous item).
//!  * The object MUST NOT add itself to a given list more than once.
//!  * If the object's constructor adds itself to a list, then the object's
//!    destructor SHOULD remove itself from that list.
//!
//! Caller is responsible for calling AtomicLock if required.

#pragma once

namespace satcat5 {
    namespace util {
        //! Helper functions for manipulating singly-linked lists.
        //! \see list.h, util::List.
        //!
        //! This class defines a set of template functions for manipulating
        //! singly-linked lists.  They are packaged into a single class to
        //! make it easier to "friend" the entire group.
        //!
        //! Most users should instantiate and use the util::List class, rather
        //! than calling these functions directly.  The base class is provided
        //! for edge-cases that must use bare pointers, such as the global
        //! linked lists used in "polling.h".
        class ListCore {
        public:
            //! Add new item to front or back, whichever is simpler.
            template <class T> static inline
            void add(T*& list, T* item) {
                satcat5::util::ListCore::push_front(list, item);
            }

            //! Add each item from "list2" onto "list1", destroying "list2".
            //! Items are pushed to the front or back in any convenient order.
            template <class T> static inline
            void add_list(T*& list1, T*& list2) {
                while (T* item = satcat5::util::ListCore::pop_front(list2)) {
                    satcat5::util::ListCore::add(list1, item);
                }
            }

            //! Check if list already contains item before adding.
            //! Adding the same item twice can create an infinite loop.
            template <class T> static inline
            void add_safe(T*& list, T* item) {
                if (!satcat5::util::ListCore::contains(list, item))
                    satcat5::util::ListCore::add(list, item);
            }

            //! Scan the list, looking for the item in question.
            template <class T> static inline
            bool contains(const T* list, const T* item) {
                const T* ptr = list;
                while (ptr) {
                    if (ptr == item) return true;
                    ptr = ptr->m_next;
                }
                return false;
            }

            //! Find the link pointing to the designated item.
            //! \returns A reference to "m_next" in the previous list
            //! item, a reference to the head-of-list pointer, or NULL.
            template <class T> static inline
            T** find_ptr(T** list, const T* item) {
                T** ptr = list;
                while (1) {
                    if (*ptr == item) return ptr;   // Found a match?
                    if (*ptr == 0) return 0;        // End of list?
                    ptr = &((*ptr)->m_next);
                }
            }

            //! Fetch the Nth item from the linked list.
            //! \returns null pointer if index >= length.
            template <class T> static inline
            T* get_index(T* list, unsigned idx) {
                T* ptr = list;
                while (ptr && idx--) {
                    ptr = ptr->m_next;
                }
                return ptr;
            }

            //! Check if the linked list loops back on itself, using the
            //! two-pointer "tortoise and hare" algorithm.
            template <class T> static inline
            bool has_loop(const T* list) {
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

            //! Insert a new item just after the designated position.
            template <class T> static inline
            void insert_after(T* where, T* item) {
                if (where && item) {
                    item->m_next = where->m_next;
                    where->m_next = item;
                }
            }

            //! Traverse the linked list to count its length.
            template <class T> static inline
            unsigned len(const T* list) {
                unsigned count = 0;
                const T* ptr = list;
                while (ptr) {
                    ++count;
                    ptr = ptr->m_next;
                }
                return count;
            }

            //! Fetch pointer to the next item.
            //! This may be required for access to private member variables.
            template <class T> static inline
            T* next(const T* item) {
                return item->m_next;
            }

            //! Remove the item at the head of the list.
            template <class T> static inline
            T* pop_front(T*& list) {
                if (!list) return 0;
                T* item = list;
                list = item->m_next;
                item->m_next = 0;
                return item;
            }

            //! Add a new item at the head of the list.
            template <class T> static inline
            void push_front(T*& list, T* item) {
                item->m_next = list;
                list = item;
            }

            //! Add a new item at the tail of the list.
            template <class T> static inline
            void push_back(T*& list, T* item) {
                T** ptr = satcat5::util::ListCore::find_ptr<T>(&list, 0);
                *ptr = item;
                item->m_next = 0;
            }

            //! Remove the designated item from the list.
            template <class T> static inline
            void remove(T*& list, T* item) {
                T** ptr = satcat5::util::ListCore::find_ptr<T>(&list, item);
                if (ptr) *ptr = item->m_next;
                item->m_next = 0;
            }

            //! Discard list contents and reset to empty or a single item.
            template <class T> static inline
            void reset(T*& list, T* item) {
                list = item;
                if (item) item->m_next = 0;
            }

            //! Check if a list contains exactly the specified item.
            //! If it does not, call `reset` to forcibly enter that state.
            //! \returns True if a reset() was required.
            //! (Unit testing only, not recommended for production.)
            template <class T> static inline
            bool pre_test_reset(T*& list, T* item) {
                bool adj = (list != item) || (item && list->m_next);
                if (adj) reset(list, item);
                return adj;
            }
        };

        //! Templated linked-list class.
        //! \see list.h, util::ListCore.
        //! This class implements a singly-linked list of objects.
        template <class T> class List final {
        public:
            constexpr List()
                : m_head(0) {}      //!< Construct an empty list.
            constexpr explicit List(T* item)
                : m_head(item) {}   //!< Construct list with one item.
            ~List() {}              //!< Destructor requires no action.

            T* head() const {return m_head;}

            //! Add new item to front or back, whichever is simpler.
            inline void add(T* item)
                {satcat5::util::ListCore::add(m_head, item);}

            //! Add each item from "list2" onto "list1", destroying "list2".
            //! Items are pushed to the front or back in any convenient order.
            inline void add_list(satcat5::util::List<T>& other)
                {satcat5::util::ListCore::add_list(m_head, other.m_head);}

            //! Check if list already contains item before adding.
            //! Adding the same item twice can create an infinite loop.
            inline void add_safe(T* item)
                {satcat5::util::ListCore::add_safe(m_head, item);}

            //! Scan the list, looking for the item in question.
            inline bool contains(const T* item) const
                {return satcat5::util::ListCore::contains(m_head, item);}

            //! Fetch the Nth item from the linked list.
            //! \returns null pointer if index >= length.
            inline T* get_index(unsigned idx)
                {return satcat5::util::ListCore::get_index(m_head, idx);}

            //! Check if the linked list loops back on itself, using the
            //! two-pointer "tortoise and hare" algorithm.
            inline bool has_loop() const
                {return satcat5::util::ListCore::has_loop(m_head);}

            //! Insert a new item just after the designated position.
            inline void insert_after(T* where, T* item)
                {satcat5::util::ListCore::insert_after(where, item);}

            //! Is this list empty?
            inline bool is_empty() const
                {return m_head == 0;}

            //! Traverse the linked list to count its length.
            inline unsigned len() const
                {return satcat5::util::ListCore::len(m_head);}

            //! Fetch pointer to the next item.
            inline T* next(const T* item) const
                {return satcat5::util::ListCore::next(item);}

            //! Remove the item at the head of the list.
            inline T* pop_front()
                {return satcat5::util::ListCore::pop_front(m_head);}

            //! Add a new item at the head of the list.
            inline void push_front(T* item)
                {satcat5::util::ListCore::push_front(m_head, item);}

            //! Add a new item at the tail of the list.
            inline void push_back(T* item)
                {satcat5::util::ListCore::push_back(m_head, item);}

            //! Remove the designated item from the list.
            inline void remove(T* item)
                {satcat5::util::ListCore::remove(m_head, item);}

            //! Discard list contents and reset to empty or a single item.
            inline void reset(T* item = 0)
                {return satcat5::util::ListCore::reset(m_head, item);}

        protected:
            T* m_head;  //!< Pointer to first item, zero if empty.
        };
    }
};
