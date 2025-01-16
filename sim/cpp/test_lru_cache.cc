//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the least-recently-used (LRU) cache template

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/lru_cache.h>

// Generic linked-list object for testing LruCache.
struct TestItem {
public:
    TestItem() : m_key(0), m_next(0) {}
    unsigned m_key;
private:
    friend satcat5::util::LruCache<TestItem>;
    TestItem* m_next;
};

TEST_CASE("lru_cache") {
    // Simulation infrastructure
    SATCAT5_TEST_START;

    constexpr unsigned CACHE_SIZE = 4;
    TestItem array[CACHE_SIZE];
    satcat5::util::LruCache<TestItem> lru(array, CACHE_SIZE);

    CHECK(lru.is_empty());
    CHECK(lru.len() == 0);

    // Fixed test sequence with a variety of edge-cases.
    SECTION("fixed") {
        // Add items until full.
        auto a = lru.query(1);
        auto b = lru.query(2);
        auto c = lru.query(3);
        auto d = lru.query(4);
        // Check each one is unique.
        CHECK_FALSE(lru.is_empty());
        CHECK(lru.len() == 4);
        CHECK(a != 0);
        CHECK(a != b);
        CHECK(a != c);
        CHECK(a != d);
        CHECK(b != 0);
        CHECK(b != c);
        CHECK(b != d);
        CHECK(c != 0);
        CHECK(c != d);
        CHECK(d != 0);
        // Make a few read-only queries.
        CHECK(lru.find(1) == a);
        CHECK(lru.find(2) == b);
        CHECK(lru.find(3) == c);
        CHECK(lru.find(4) == d);
        CHECK(lru.find(5) == 0);
        // Query a repeat (#2)
        auto e = lru.query(2);
        CHECK(lru.len() == 4);
        CHECK(b == e);
        // Query a new value (#5), evicting the oldest (#1)
        auto f = lru.query(5);
        CHECK(lru.len() == 4);
        CHECK(f == a);
        // Clear the list and query the same item twice (#6).
        lru.clear();
        CHECK(lru.is_empty());
        CHECK(lru.len() == 0);
        auto g = lru.query(6);
        auto h = lru.query(6);
        CHECK_FALSE(lru.is_empty());
        CHECK(lru.len() == 1);
        CHECK(g != 0);
        CHECK(g == h);
    }

    // Make a series of 10k random queries with about 50% miss rate.
    SECTION("random") {
        for (unsigned a = 0 ; a < 10000 ; ++a) {
            CHECK(lru.query(satcat5::test::rand_u32() % 8));
        }
    }
}
