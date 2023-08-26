//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
// Test cases for the PTP time-tracking filter

#include <fstream>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/uint_wide.h>
#include <satcat5/utils.h>

using satcat5::net::Address;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::Time;
using satcat5::ptp::TrackingClock;
using satcat5::ptp::TrackingClockDebug;
using satcat5::ptp::TrackingCoeff;
using satcat5::ptp::TrackingController;
using satcat5::ptp::TrackingDither;
using satcat5::test::Statistics;
using satcat5::util::round_s64;
using satcat5::util::round_u64;
using satcat5::util::uint128_t;
using satcat5::util::UINT128_ZERO;

// Simulated clock mimics operatin of "ptp_realtime.vhd"
class SimulatedClock : public TrackingClock {
public:
    // 1 LSB = 2^-40 nanoseconds = 2^-24 subns
    // (This matches the default for ptp_counter_gen and ptp_realtime.)
    static constexpr u64 TICKS_PER_SUBNS = (1ull << 24);
    static constexpr double TICKS_PER_SEC =
        double(TICKS_PER_SUBNS) * double(SUBNS_PER_SEC);

    SimulatedClock(double nominal_hz, double actual_hz)
        : m_scale_nominal(nominal_hz / TICKS_PER_SEC)
        , m_rate_actual(actual_hz)
        , m_nco_rate(round_s64(TICKS_PER_SEC / nominal_hz))
        , m_nco_offset(0)
        , m_nco_accum(UINT128_ZERO)
        , m_count_coarse(0)
        , m_rtc(0) {}

    // Report the number of coarse adjustments.
    unsigned num_coarse() const { return m_count_coarse; }

    // Mean of all inputs to clock_rate(...)
    double mean() { return m_stats.mean(); }

    // Accessor for the current real-time-clock (RTC) state.
    Time now() const { return m_rtc; }

    // Implement the required TrackingClock API.
    Time clock_adjust(const Time& amount) override
        { m_rtc += amount; ++m_count_coarse; return Time(0); }
    void clock_rate(s64 offset) override
        { m_nco_offset = offset; m_stats.add(offset); }
    double clock_offset_ppm() const
        { return m_nco_offset * ref_scale() * 1e6; }
    double ref_scale() const
        { return m_scale_nominal; }

    // Advance simulation by X seconds.
    void run(const Time& dt) {
        // Advance the NCO in discrete steps.
        double dt_secs = dt.delta_subns() / double(SUBNS_PER_SEC);
        u64 num_clocks = round_u64(dt_secs * m_rate_actual);
        // Increment internal counter at full precision.
        const uint128_t incr(num_clocks);
        const uint128_t rate(u64(m_nco_rate + m_nco_offset));
        m_nco_accum += incr * rate;
        // Internal resolution is higher than RTC; retain leftovers.
        const uint128_t scale(TICKS_PER_SUBNS);
        m_rtc += Time(s64(m_nco_accum / scale));
        m_nco_accum = m_nco_accum % scale;
    }

private:
    const double m_scale_nominal;
    const double m_rate_actual;
    const s64 m_nco_rate;
    s64 m_nco_offset;
    uint128_t m_nco_accum;
    unsigned m_count_coarse;
    Time m_rtc;
    Statistics m_stats;
};

// Scenario parameters for each simulation:
struct SimScenario {
    double tmax_sec;        // Simulation duration (sec)
    double t0_sec;          // Initial time-offset (sec)
    double tau_sec;         // Filter time-constant (sec)
    double nominal_hz;      // Nominal oscillator frequency (Hz)
    double offset_ppm;      // Frequency offset (PPM)
    double sim_rate_hz;     // Simulation update rate (Hz)
    bool tau_change;        // Change time constant during sim?
    Address* debug_addr;    // Destination for debug packets
};

const SimScenario DEFAULT_SCENARIO =
    {120.0, 100e-9, 5.0, 125e6, 0.0, 8.0, false, 0};

// Report results for each simulation:
struct SimResult {
    double rms_nsec;        // Steady-state RMS error (nsec)
    double phase_over_nsec; // Maximum phase overshoot (nsec)
    double phase_zero_msec; // Time of phase zero-crossing (msec)
    double rate_over_ppm;   // Maximum rate overshoot (ppm)
    double rate_zero_msec;  // Time of rate zero-crossing (msec)
    unsigned coarse_adj;    // Number of coarse time adjustments
};

// Run oscillator + controller simulation for a fixed duration.
// Saves intermediate data to a .CSV file for manual inspection.
// Returns the estimated steady-state RMS error, in nanoseconds.
SimResult simulate(const char* filename, const SimScenario& sim)
{
    // Open file for plaintext output.
    std::ofstream outfile(filename);
    outfile << "Time (msec), Offset (nsec), Rate (PPM)" << std::endl;

    // Set simulation initial conditions.
    double actual_hz = sim.nominal_hz * (1.0 + 0.000001*sim.offset_ppm);
    bool tau_change = sim.tau_change;
    Time tsim(0);
    const Time toff(round_s64(SUBNS_PER_SEC * sim.t0_sec));
    const Time tmax(round_s64(SUBNS_PER_SEC * sim.tmax_sec));
    const Time step(round_s64(SUBNS_PER_SEC / sim.sim_rate_hz));
    SimulatedClock clk(sim.nominal_hz, actual_hz);
    const TrackingCoeff coeff(clk.ref_scale(), sim.tau_sec);
    TrackingController uut(&clk, coeff);
    REQUIRE(coeff.ok());
    if (sim.debug_addr) uut.set_debug(sim.debug_addr);

    // Run simulation for a fixed duration...
    double phase_zero_msec = -1.0, rate_zero_msec = -1.0;
    Statistics stats_all, stats_fin, stats_ppm;
    while (tsim < tmax) {
        // Feed next measurement to the unit under test.
        Time tdiff = tsim + toff - clk.now();
        uut.update(clk.now(), tdiff);
        // Log the phase error vs. time.
        double delta_nsec = tdiff.delta_subns() / double(SUBNS_PER_NSEC);
        double delta_ppm  = clk.clock_offset_ppm();
        outfile << tsim.delta_msec() << ", "
                << delta_nsec << ", "
                << delta_ppm << std::endl;
        // Note the time that various signals first turn negative.
        if (delta_nsec < 0 && phase_zero_msec < 0) {
            phase_zero_msec = tsim.delta_msec();
        }
        if (delta_ppm < 0 && rate_zero_msec < 0) {
            rate_zero_msec = tsim.delta_msec();
        }
        // Update statistics, separating the last 10% of the run.
        stats_all.add(delta_nsec);
        stats_ppm.add(delta_ppm);
        if (tsim*10 >= tmax*9) {
            stats_fin.add(delta_nsec);
        }
        // Change bandwidth at the 50% mark?
        if (tau_change && tsim*2 >= tmax) {
            tau_change = false; // One-time speedup of 2x.
            TrackingCoeff new_coeff(clk.ref_scale(), sim.tau_sec / 2);
            REQUIRE(new_coeff.ok());
            uut.reconfigure(new_coeff);
        }
        // Advance simulation one time-step.
        tsim += step;
        clk.run(step);
    }

    // Return the steady-state RMS error (nsec).
    return SimResult {
        stats_fin.rms(),        // Steady-state RMS error (nsec)
        -stats_all.min(),       // Maximum overshoot (nsec)
        phase_zero_msec,        // Time of first zero-crossing (msec)
        -stats_ppm.min(),       // Maximum rate overshoot (ppm)
        rate_zero_msec,         // Time of rate zero-crossing (msec)
        clk.num_coarse(),       // Number of coarse time adjustments
    };     
}

TEST_CASE("TrackingClockDebug") {
    // Simulation infrastructure.
    SimulatedClock clk(125e6, 125e6);
    TrackingClockDebug uut(&clk);

    SECTION("clock_adjust") {
        CHECK(clk.num_coarse() == 0);
        uut.clock_adjust(satcat5::ptp::ONE_SECOND);
        CHECK(clk.num_coarse() == 1);
    }

    SECTION("clock_rate") {
        for (s64 a = -5 ; a <= 5 ; ++a) {
            CHECK(uut.clock_rate() != a);
            uut.clock_rate(a);
            CHECK(uut.clock_rate() == a);
        }
    }
}

TEST_CASE("TrackingCoeff") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        TrackingCoeff coeff1(clk.ref_scale(), 1.0);
        TrackingCoeff coeff2(clk.ref_scale(), 3600.0);
        TrackingCoeff coeff3(clk.ref_scale(), 1e9);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.disable();  // Suppress echo to screen
        TrackingController uut(&clk, coeff3);
        CHECK(log.contains("Bad config"));
    }
}

TEST_CASE("TrackingController") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;
    SimScenario sim = DEFAULT_SCENARIO;

    // Basic test with a small phase-step.
    // Note: Expected phase-step response with damping 0.707, tau = 5.0 sec
    //  has overshoot ~4.3% and first zero-crossing at ~2.6 seconds.
    SECTION("phase_step_smol") {
        SimResult result = simulate("simulations/tctrl_smol.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // Increase the simulation rate from 8 to 64 Hz.
    SECTION("phase_step_fast") {
        sim.sim_rate_hz *= 8;
        SimResult result = simulate("simulations/tctrl_fast.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // A larger phase-step, with network-debugging enabled.
    SECTION("phase_step_large") {
        satcat5::test::DebugAddress debug;
        sim.debug_addr = &debug;
        sim.t0_sec *= 100;
        SimResult result = simulate("simulations/tctrl_large.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 300.0);
        CHECK(result.phase_over_nsec < 600.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // A moderate frequency offset.
    SECTION("freq_step") {
        sim.offset_ppm = 100.0;
        SimResult result = simulate("simulations/tctrl_freq.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj == 0);
    }

    // Initial offset large enough to require a coarse adjustment.
    SECTION("coarse_step") {
        log.disable();  // Suppress expected info message
        sim.offset_ppm = 100.0;
        sim.t0_sec = 5.0;
        SimResult result = simulate("simulations/tctrl_coarse.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj == 1);
    }

    // Change the filter time-constant halfway through the simulation.
    SECTION("tau_change") {
        sim.offset_ppm = 100.0;
        sim.tau_change = true;
        SimResult result = simulate("simulations/tctrl_tau.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.coarse_adj == 0);
        CHECK(log.empty());
    }
}

TEST_CASE("TrackingDither") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;
    satcat5::test::TimerAlways timer;

    // Confirm dither allows sub-LSB resolution.
    SECTION("average") {
        for (s64 offset = -1000000 ; offset <= 1000000 ; offset += 10000) {
            // Configure unit under test.
            SimulatedClock clk(125e6, 125e6);
            TrackingDither uut(&clk);
            uut.clock_rate(offset);
            // Run for many timesteps.
            for (unsigned t = 0 ; t < 10000 ; ++t) {
                satcat5::poll::service_all();
            }
            // Confirm dithered average matches expectation.
            double expected = offset / 65536.0;
            CHECK(abs(clk.mean() - expected) < 0.001);
        }
    }

    // Confirm coarse adjustments are relayed to the target.
    SECTION("coarse") {
        SimulatedClock clk(125e6, 125e6);
        TrackingDither uut(&clk);
        CHECK(clk.num_coarse() == 0);
        uut.clock_adjust(satcat5::ptp::ONE_SECOND);
        CHECK(clk.num_coarse() == 1);
    }
}
