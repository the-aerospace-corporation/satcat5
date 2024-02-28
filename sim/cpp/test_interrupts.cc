//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the generic Interrupt Controller

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/interrupts.h>
#include <unistd.h>

class SlowInterruptHandler : public satcat5::irq::Handler {
public:
    SlowInterruptHandler(satcat5::irq::Controller* ctrl, int irq)
        : satcat5::irq::Handler("MockHandler", irq) {}

protected:
    void irq_event() override {
        usleep(1000);
    }
};

class MockInterruptHandler : public satcat5::irq::Handler {
public:
    MockInterruptHandler(satcat5::irq::Controller* ctrl, int irq)
        : satcat5::irq::Handler("MockHandler", irq)
        , m_ctrl(ctrl)
        , m_count(0)
    {
        // Nothing else to initialize.
    }

    virtual ~MockInterruptHandler() {}

    unsigned count() const {return m_count;}

protected:
    void irq_event() override {
        CHECK(m_ctrl->is_irq_context());
        CHECK(m_ctrl->is_irq_or_locked());
        ++m_count;
    }
    satcat5::irq::Controller* const m_ctrl;
    unsigned m_count;
};

class MockInterruptController : public satcat5::irq::Controller {
public:
    MockInterruptController()
        : m_paused(false)
        , m_count(0)
    {
        // Nothing else to initialize.
    }

    unsigned count() const {return m_count;}

    void trigger(satcat5::irq::Handler* obj) {
        interrupt_static(obj);
    }

protected:
    void irq_pause() override {
        CHECK_FALSE(m_paused);
        m_paused = true;    // Never call this twice in a row
    }

    void irq_resume() override {
        CHECK(m_paused);
        m_paused = false;   // Never call this twice in a row
    }

    void irq_register(satcat5::irq::Handler* obj) override {
        ++m_count;
    }

    void irq_unregister(satcat5::irq::Handler* obj) override {
        CHECK(m_count > 0);
        --m_count;
    }

    bool m_paused;
    unsigned m_count;
};

TEST_CASE("interrupts") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Use system time for statistics monitoring.
    satcat5::util::PosixTimer timer;

    // Unit under test: One controller and two handlers.
    MockInterruptController ctrl;
    MockInterruptHandler irq1(&ctrl, 1);
    MockInterruptHandler irq2(&ctrl, 2);

    // Check initial state.
    CHECK(ctrl.count() == 0);
    CHECK_FALSE(ctrl.is_initialized());
    CHECK_FALSE(ctrl.is_irq_context());
    CHECK_FALSE(ctrl.is_irq_or_locked());

    // Initialize interrupt system.
    ctrl.init(&timer);
    CHECK(ctrl.count() == 2);
    CHECK(ctrl.is_initialized());
    CHECK_FALSE(ctrl.is_irq_context());
    CHECK_FALSE(ctrl.is_irq_or_locked());

    SECTION("lock") {
        // Enter and exit a critical section.
        REQUIRE(ctrl.is_initialized());
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
        {
            satcat5::irq::AtomicLock lock("LockTest");
            CHECK_FALSE(ctrl.is_irq_context());
            CHECK(ctrl.is_irq_or_locked());
        }
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
    }

    SECTION("lock2") {
        // Enter and exit a nested critical section.
        REQUIRE(ctrl.is_initialized());
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
        {
            satcat5::irq::AtomicLock lock1("Lock1");
            CHECK_FALSE(ctrl.is_irq_context());
            CHECK(ctrl.is_irq_or_locked());
            {
                satcat5::irq::AtomicLock lock2("Lock2");
                CHECK_FALSE(ctrl.is_irq_context());
                CHECK(ctrl.is_irq_or_locked());
            }
            CHECK_FALSE(ctrl.is_irq_context());
            CHECK(ctrl.is_irq_or_locked());
        }
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
    }

    SECTION("interrupt") {
        // Trigger each interrupt a few times.
        REQUIRE(ctrl.is_initialized());
        CHECK(irq1.count() == 0);
        CHECK(irq2.count() == 0);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq2);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq2);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq1);
        CHECK(irq1.count() == 5);
        CHECK(irq2.count() == 2);
    }

    SECTION("early-unregister") {
        // Create and destroy an InterruptHandler while system is running.
        unsigned before = ctrl.count();
        {
            MockInterruptHandler irq3(&ctrl, 3);
            CHECK(ctrl.count() == before + 1);
        }
        CHECK(ctrl.count() == before);
    }

    SECTION("random-unregister") {
        // Unregister InterruptHandlers in psuedorandom order.
        MockInterruptHandler* irq3 = new MockInterruptHandler(&ctrl, 3);
        MockInterruptHandler* irq4 = new MockInterruptHandler(&ctrl, 4);
        MockInterruptHandler* irq5 = new MockInterruptHandler(&ctrl, 5);
        delete irq4;
        delete irq3;
        delete irq5;
    }

    SECTION("adapter") {
        satcat5::test::CountOnDemand ctr;
        satcat5::irq::Adapter uut("Adapter", 3, &ctr);
        CHECK(ctr.count() == 0);    // Check initial state
        ctrl.trigger(&uut);
        CHECK(ctr.count() == 0);    // Queued but not called
        satcat5::poll::service();
        CHECK(ctr.count() == 1);    // Deferred interrupt
    }

    SECTION("shared") {
        // Register three children under a single shared umbrella.
        satcat5::irq::Shared uut("Shared", 3);
        MockInterruptHandler irq3a(&ctrl, satcat5::irq::IRQ_NONE);
        MockInterruptHandler irq3b(&ctrl, satcat5::irq::IRQ_NONE);
        MockInterruptHandler irq3c(&ctrl, satcat5::irq::IRQ_NONE);
        // Trigger the shared interrupt a few times during registration.
        ctrl.trigger(&uut);
        uut.add(&irq3a);
        ctrl.trigger(&uut);
        uut.add(&irq3b);
        ctrl.trigger(&uut);
        uut.add(&irq3c);
        ctrl.trigger(&uut);
        // Confirm expected event counts.
        CHECK(irq3a.count() == 3);
        CHECK(irq3b.count() == 2);
        CHECK(irq3c.count() == 1);
    }

    SECTION("slow-interrupt") {
        // Very slow interrupt handler, to make sure max_irqtime is updated.
        SlowInterruptHandler irq3(&ctrl, 3);
        ctrl.trigger(&irq3);
    }

    // Cleanup.
    ctrl.stop();
    REQUIRE(ctrl.count() == 0);
}

TEST_CASE("interrupts-null-timer") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Unit under test: One controller and two handlers.
    MockInterruptController ctrl;
    MockInterruptHandler irq1(&ctrl, 1);
    MockInterruptHandler irq2(&ctrl, 2);

    // Initialize interrupt system, without a timer.
    ctrl.init(0);
    CHECK(ctrl.count() == 2);
    CHECK(ctrl.is_initialized());
    CHECK_FALSE(ctrl.is_irq_context());
    CHECK_FALSE(ctrl.is_irq_or_locked());

    SECTION("lock") {
        // Enter and exit a critical section.
        REQUIRE(ctrl.is_initialized());
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
        {
            satcat5::irq::AtomicLock lock("LockTest");
            CHECK_FALSE(ctrl.is_irq_context());
            CHECK(ctrl.is_irq_or_locked());
        }
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
    }

    SECTION("interrupt") {
        // Trigger each interrupt a few times.
        REQUIRE(ctrl.is_initialized());
        CHECK(irq1.count() == 0);
        CHECK(irq2.count() == 0);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq2);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq2);
        ctrl.trigger(&irq1);
        ctrl.trigger(&irq1);
        CHECK(irq1.count() == 5);
        CHECK(irq2.count() == 2);
    }

    // Cleanup.
    ctrl.stop();
}

TEST_CASE("ControllerNull") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Use system time for statistics monitoring.
    satcat5::util::PosixTimer timer;

    // Unit under test: One controller and two handlers.
    satcat5::irq::ControllerNull ctrl(&timer);
    MockInterruptHandler irq1(&ctrl, 1);
    MockInterruptHandler irq2(&ctrl, 2);

    // Initialize interrupt system.
    CHECK(ctrl.is_initialized());
    CHECK_FALSE(ctrl.is_irq_context());
    CHECK_FALSE(ctrl.is_irq_or_locked());

    SECTION("lock") {
        // Enter and exit a critical section.
        REQUIRE(ctrl.is_initialized());
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
        {
            satcat5::irq::AtomicLock lock("LockTest");
            CHECK_FALSE(ctrl.is_irq_context());
            CHECK(ctrl.is_irq_or_locked());
        }
        CHECK_FALSE(ctrl.is_irq_context());
        CHECK_FALSE(ctrl.is_irq_or_locked());
    }

    SECTION("interrupt") {
        // Trigger each interrupt a few times.
        REQUIRE(ctrl.is_initialized());
        CHECK(irq1.count() == 0);
        CHECK(irq2.count() == 0);
        ctrl.service_all();
        ctrl.service_one(&irq1);
        ctrl.service_one(&irq2);
        CHECK(irq1.count() == 2);
        CHECK(irq2.count() == 2);
    }

    // Cleanup.
    ctrl.stop();
}

