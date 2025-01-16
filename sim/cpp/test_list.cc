//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the linked-list template classes.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
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
    // Simulation infrastructure
    SATCAT5_TEST_START;

    // Unit under test
    satcat5::util::List<TestItem> list;
    TestItem a(1), b(2), c(3), d(4);

    CHECK(list.is_empty());

    SECTION("add_list") {
        satcat5::util::List<TestItem> list1, list2;
        list1.add(&a);
        list1.add(&b);
        list2.add(&c);
        list2.add(&d);
        CHECK(list1.len() == 2);
        CHECK(list2.len() == 2);
        list1.add_list(list2);
        CHECK(list1.len() == 4);
        CHECK(list2.len() == 0);
    }

    SECTION("add_safe") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        CHECK_FALSE(list.is_empty());
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

    SECTION("construct1") {
        satcat5::util::List<TestItem> list2(&a);
        CHECK(list2.len() == 1);
        list2.add(&b);
        CHECK(list2.len() == 2);
    }

    SECTION("get_index") {
        list.push_back(&a);
        list.push_back(&b);
        list.push_back(&c);
        CHECK(list.get_index(0) == &a);
        CHECK(list.get_index(1) == &b);
        CHECK(list.get_index(2) == &c);
        CHECK(list.get_index(3) == 0);
    }

    SECTION("has_loop3") {
        list.add(&a);
        list.add(&b);
        list.add(&c);
        CHECK_FALSE(list.is_empty());
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
        CHECK_FALSE(list.is_empty());
        CHECK(list.len() == 4);
        CHECK_FALSE(list.has_loop());
        list.add(&d);
        CHECK(list.has_loop());
    }

    SECTION("insert_after") {
        list.add(&a);
        list.add(&b);
        list.add(&d);
        CHECK(list.len() == 3);
        list.insert_after(&b, &c);
        CHECK(list.len() == 4);
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
        CHECK(list.len() == 3);
        list.remove(&b);
        CHECK_FALSE(list.contains(&b));
        CHECK_FALSE(list.is_empty());
        CHECK(list.len() == 2);
        list.reset();
        CHECK(list.len() == 0);
    }
}
