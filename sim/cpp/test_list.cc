//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the linked-list template classes.

#include <hal_test/catch.hpp>
#include <satcat5/list.h>

// Generic linked-list object for testing ListCore and List.
class TestItem {
public:
    friend satcat5::util::ListCore;
    explicit TestItem(unsigned val) : m_next(0), m_value(val) {}

private:
    TestItem* m_next;
    unsigned m_value;
};

TEST_CASE("list.h") {
    satcat5::util::List<TestItem> list;
    TestItem a(1), b(2), c(3), d(4);

    SECTION("add_safe") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        CHECK(list.len() == 3);
        list.add_safe(&b);
        CHECK(list.len() == 3);
        list.add_safe(&d);
        CHECK(list.len() == 4);
    }

    SECTION("contains") {
        list.add(&a);
        list.add(&c);
        CHECK(list.contains(&a));
        CHECK_FALSE(list.contains(&b));
        CHECK(list.contains(&c));
        CHECK_FALSE(list.contains(&d));
    }

    SECTION("has_loop3") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        CHECK(list.len() == 3);
        CHECK_FALSE(list.has_loop());
        list.add(&b);
        CHECK(list.has_loop());
    }

    SECTION("has_loop4") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        list.add(&d);
        CHECK(list.len() == 4);
        CHECK_FALSE(list.has_loop());
        list.add(&d);
        CHECK(list.has_loop());
    }

    SECTION("push_back") {
        list.push_back(&a);
        list.push_back(&b);
        CHECK(list.pop_front() == &a);
        CHECK(list.pop_front() == &b);
        CHECK(list.pop_front() == 0);
    }

    SECTION("push_front") {
        list.push_front(&a);
        list.push_front(&b);
        CHECK(list.pop_front() == &b);
        CHECK(list.pop_front() == &a);
        CHECK(list.pop_front() == 0);
    }

    SECTION("remove") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        CHECK(list.contains(&b));
        list.remove(&b);
        CHECK_FALSE(list.contains(&b));
    }
}
