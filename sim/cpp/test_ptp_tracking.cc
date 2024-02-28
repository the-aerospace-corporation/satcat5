//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the PTP time-tracking filter

#include <algorithm>
#include <fstream>
#include <hal_test/catch.hpp>
#include <hal_test/ptp_clock.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/utils.h>
#include <satcat5/wide_integer.h>

using satcat5::net::Address;
using satcat5::ptp::CoeffLR;
using satcat5::ptp::CoeffPI;
using satcat5::ptp::CoeffPII;
using satcat5::ptp::ControllerLR;
using satcat5::ptp::ControllerPI;
using satcat5::ptp::ControllerPII;
using satcat5::ptp::SimulatedClock;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::Time;
using satcat5::ptp::TrackingClock;
using satcat5::ptp::TrackingController;
using satcat5::ptp::TrackingDither;
using satcat5::test::Statistics;
using satcat5::util::round_s64;
using satcat5::util::round_u64;

// Scenario parameters for each simulation:
struct SimScenario {
    double tmax_sec;        // Simulation duration (sec)
    double t0_sec;          // Initial time-offset (sec)
    double tau_sec;         // Filter time-constant (sec)
    double nominal_hz;      // Nominal oscillator frequency (Hz)
    double offset_ppm;      // Frequency offset (PPM)
    double sim_rate_hz;     // Simulation update rate (Hz)
    double time_shift;      // Change server time at halfway point?
    bool tau_change;        // Change time constant at halfway point?
    unsigned boxcar_order;  // Enable boxcar filter?
    unsigned median_order;  // Enable median filter?
    unsigned linear_order;  // Enable linear-regression controller?
    std::string ctrl_type;  // Control type? (LR / PI / PII)
};

const SimScenario DEFAULT_SCENARIO =
    {120.0, 100e-9, 5.0, 125e6, 0.0, 8.0, 0.0, false, 0, 1, 8, "PI"};

// Report results for each simulation:
struct SimResult {
    double rms_nsec;        // Steady-state RMS error (nsec)
    double phase_over_nsec; // Maximum phase overshoot (nsec)
    double phase_zero_msec; // Time of phase zero-crossing (msec)
    double phase_90p_msec;  // Time of 90% step-response (msec)
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

    // Flip sign of certain statistics? (e.g., zero-crossings)
    double stat_flip = (sim.t0_sec > 0) ? 1.0 : -1.0;
    double thresh_90p = 0.1e9 * fabs(sim.t0_sec);

    // Simulated timer object reads from "tsim_usec".
    // (Separate "always" object polls it during poll::service_all.)
    u32 tsim_usec = 0;
    satcat5::util::TimerRegister timer(&tsim_usec, 1000000);
    satcat5::test::TimerAlways always_poll_timers;

    // Set simulation initial conditions.
    double actual_hz = sim.nominal_hz * (1.0 + 0.000001*sim.offset_ppm);
    bool first_half = true;
    Time tsim(0);
    Time toff(round_s64(SUBNS_PER_SEC * sim.t0_sec));
    const Time tmax(round_s64(SUBNS_PER_SEC * sim.tmax_sec));
    const Time tadj(round_s64(SUBNS_PER_SEC * sim.time_shift));
    const Time step(round_s64(SUBNS_PER_SEC / sim.sim_rate_hz));
    SimulatedClock clk(sim.nominal_hz, actual_hz);

    // Set time-constants for all operating modes.
    const CoeffLR coeff_lr(clk.ref_scale(), sim.tau_sec);
    const CoeffPI coeff_pi(clk.ref_scale(), sim.tau_sec);
    const CoeffPII coeff_pii(clk.ref_scale(), sim.tau_sec);

    // Set up each of the tracking filters.
    satcat5::ptp::MedianFilter<9> premedian(sim.median_order);
    satcat5::ptp::BoxcarFilter<6> preboxcar(sim.boxcar_order);
    satcat5::ptp::ControllerLR<32> ctrl_lr(coeff_lr);
    satcat5::ptp::ControllerPI ctrl_pi(coeff_pi);
    satcat5::ptp::ControllerPII ctrl_pii(coeff_pii);
    satcat5::ptp::BoxcarFilter<6> postboxcar(sim.boxcar_order);
    ctrl_lr.set_window(sim.linear_order);

    // Additional sanity checks before we start.
    // (Do this after configuring controllers, for better error logging.)
    REQUIRE(coeff_lr.ok());
    REQUIRE(coeff_pi.ok());
    REQUIRE(coeff_pii.ok());

    // And add those filters to the tracking system under test.
    TrackingController uut(&timer, &clk, 0);
    uut.add_filter(&premedian);
    uut.add_filter(&preboxcar);
    if (sim.ctrl_type == "LR")          uut.add_filter(&ctrl_lr);
    else if (sim.ctrl_type == "PI")     uut.add_filter(&ctrl_pi);
    else if (sim.ctrl_type == "PII")    uut.add_filter(&ctrl_pii);
    else CATCH_ERROR("Unknown control type");
    uut.add_filter(&postboxcar);

    // Run simulation for a fixed duration...
    double phase_zero_msec = -1.0, phase_90p_msec = -1.0, rate_zero_msec = -1.0;
    Statistics stats_all, stats_fin, stats_ppm;
    while (tsim < tmax) {
        // Feed next measurement to the unit under test.
        Time tdiff = tsim + toff - clk.now();
        uut.update(tdiff);
        // Log the phase error vs. time.
        double delta_nsec = tdiff.delta_subns() / double(SUBNS_PER_NSEC);
        double delta_ppm  = clk.clock_offset_ppm();
        outfile << tsim.delta_msec() << ", "
                << delta_nsec << ", "
                << delta_ppm << std::endl;
        // Note the time that various signals first cross zero.
        if (delta_nsec * stat_flip < 0 && phase_zero_msec < 0) {
            phase_zero_msec = tsim.delta_msec();
        }
        if (delta_nsec * stat_flip < thresh_90p && phase_90p_msec < 0) {
            phase_90p_msec = tsim.delta_msec();
        }
        if (delta_ppm * stat_flip < 0 && rate_zero_msec < 0) {
            rate_zero_msec = tsim.delta_msec();
        }
        // Update statistics, separating the last 10% of the run.
        stats_all.add(delta_nsec * stat_flip);
        stats_ppm.add(delta_ppm * stat_flip);
        if (tsim*10 >= tmax*9) {
            stats_fin.add(delta_nsec);
        }
        // Change various parameters at the 50% mark?
        if (first_half && tsim*2 >= tmax) {
            first_half = false;
            if (sim.tau_change) {
                CoeffLR new_coeff_lr(clk.ref_scale(), sim.tau_sec / 2);
                CoeffPI new_coeff_pi(clk.ref_scale(), sim.tau_sec / 2);
                REQUIRE(new_coeff_lr.ok());
                REQUIRE(new_coeff_pi.ok());
                ctrl_lr.set_coeff(new_coeff_lr);
                ctrl_pi.set_coeff(new_coeff_pi);
            }
            toff += tadj;
        }
        // Advance simulation one time-step.
        clk.run(step);
        tsim += step;
        tsim_usec = tsim.delta_usec();
        satcat5::poll::service_all();
    }

    // Return the steady-state RMS error (nsec).
    return SimResult {
        stats_fin.rms(),        // Steady-state RMS error (nsec)
        -stats_all.min(),       // Maximum overshoot (nsec)
        phase_zero_msec,        // Time of first zero-crossing (msec)
        phase_90p_msec,         // Time of 90% step-response (msec)
        -stats_ppm.min(),       // Maximum rate overshoot (ppm)
        rate_zero_msec,         // Time of rate zero-crossing (msec)
        clk.num_coarse(),       // Number of coarse time adjustments
    };
}

TEST_CASE("TrackingClockDebug") {
    // Simulation infrastructure.
    SimulatedClock uut(125e6, 125e6);

    SECTION("clock_adjust") {
        CHECK(uut.num_coarse() == 0);
        uut.clock_adjust(satcat5::ptp::ONE_SECOND);
        CHECK(uut.num_coarse() == 1);
    }

    SECTION("clock_rate") {
        for (s64 a = -5 ; a <= 5 ; ++a) {
            CHECK(uut.get_rate() != a);
            uut.clock_rate(a);
            CHECK(uut.get_rate() == a);
        }
    }
}

TEST_CASE("TrackingController") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;
    SimScenario sim = DEFAULT_SCENARIO;

    // Suppress routine messages.
    log.suppress("PTP-Track: Adjust");

    // Basic test with a small positive and negative phase-steps.
    // Note: Expected phase-step response with damping 0.707, tau = 5.0 sec
    //  has overshoot ~4.3% and first zero-crossing at ~2.6 seconds.
    SECTION("phase_step_smol_pip") {
        SimResult result = simulate("simulations/tctrl_smol_pip.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    SECTION("phase_step_smol_pin") {
        sim.t0_sec *= -1;
        SimResult result = simulate("simulations/tctrl_smol_pin.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // Same as "phase_step_smol_pip", but using the double-integral controller.
    SECTION("phase_step_smol_piip") {
        sim.ctrl_type = "PII";
        SimResult result = simulate("simulations/tctrl_smol_piip.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    SECTION("phase_step_smol_piin") {
        sim.ctrl_type = "PII";
        sim.t0_sec *= -1;
        SimResult result = simulate("simulations/tctrl_smol_piin.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // Same as "phase_step_smol_pip", but using the linear regression controller.
    SECTION("phase_step_smol_lrp") {
        sim.ctrl_type = "LR";
        SimResult result = simulate("simulations/tctrl_smol_lrp.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec < 1.0);
        CHECK(result.phase_90p_msec > 6000);
        CHECK(result.phase_90p_msec < 6500);
        CHECK(result.coarse_adj == 0);
    }

    SECTION("phase_step_smol_lrn") {
        sim.ctrl_type = "LR";
        sim.t0_sec *= -1;
        SimResult result = simulate("simulations/tctrl_smol_lrn.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec < 1.0);
        CHECK(result.phase_90p_msec > 6000);
        CHECK(result.phase_90p_msec < 6500);
        CHECK(result.coarse_adj == 0);
    }

    // Enable the boxcar filter (latency increases overshoot).
    SECTION("phase_step_boxcar") {
        sim.boxcar_order = 2;
        SimResult result = simulate("simulations/tctrl_boxcar.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 8.0);
        CHECK(result.phase_over_nsec < 12.0);
        CHECK(result.phase_zero_msec > 1500);
        CHECK(result.phase_zero_msec < 2000);
        CHECK(result.coarse_adj == 0);
    }

    // Enable the median filter (latency increases overshoot).
    SECTION("phase_step_median") {
        sim.median_order = 5;
        SimResult result = simulate("simulations/tctrl_median.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 5.0);
        CHECK(result.phase_over_nsec < 8.0);
        CHECK(result.phase_zero_msec > 1500);
        CHECK(result.phase_zero_msec < 2000);
        CHECK(result.coarse_adj == 0);
    }

    // Increase the simulation rate from 8 to 64 Hz.
    SECTION("phase_step_fast_pi") {
        sim.sim_rate_hz *= 8;
        SimResult result = simulate("simulations/tctrl_fast_pi.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec > 3.0);
        CHECK(result.phase_over_nsec < 6.0);
        CHECK(result.phase_zero_msec > 2400);
        CHECK(result.phase_zero_msec < 2800);
        CHECK(result.coarse_adj == 0);
    }

    // Same as "phase_step_fast", but using the linear-regression controller.
    SECTION("phase_step_fast_lr") {
        sim.ctrl_type = "LR";
        sim.sim_rate_hz *= 8;
        sim.linear_order = 16;
        SimResult result = simulate("simulations/tctrl_fast_lr.csv", sim);
        CHECK(result.rms_nsec < 1.0);
        CHECK(result.phase_over_nsec < 1.0);
        CHECK(result.phase_90p_msec > 5700);
        CHECK(result.phase_90p_msec < 6300);
        CHECK(result.coarse_adj == 0);
    }

    // A larger phase-step.
    SECTION("phase_step_large") {
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
    SECTION("coarse_step_pi") {
        log.suppress("Coarse");  // Suppress expected info messages
        log.suppress("Adjust");
        sim.offset_ppm = 100.0;
        sim.t0_sec = 5.0;
        SimResult result = simulate("simulations/tctrl_coarse_pi.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj >= 1);
        CHECK(log.contains("Adjust"));
    }

    SECTION("coarse_step_pii") {
        log.suppress("Coarse");  // Suppress expected info messages
        log.suppress("Adjust");
        sim.ctrl_type = "PII";
        sim.offset_ppm = 100.0;
        sim.t0_sec = 5.0;
        SimResult result = simulate("simulations/tctrl_coarse_pii.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj >= 1);
        CHECK(log.contains("Adjust"));
    }

    SECTION("coarse_step_lr") {
        log.suppress("Coarse");  // Suppress expected info messages
        log.suppress("Adjust");
        sim.ctrl_type = "LR";
        sim.offset_ppm = 100.0;
        sim.t0_sec = 5.0;
        SimResult result = simulate("simulations/tctrl_coarse_lr.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj >= 1);
        CHECK(log.contains("Adjust"));
    }

    // Change the server time halfway through the simulation.
    SECTION("coarse_shift") {
        log.suppress("Coarse");  // Suppress expected info messages
        log.suppress("Adjust");
        sim.time_shift = 5.0;
        SimResult result = simulate("simulations/tctrl_shift.csv", sim);
        CHECK(result.rms_nsec < 5.0);
        CHECK(result.coarse_adj >= 1);
        CHECK(log.contains("Adjust"));
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
            CHECK(fabs(clk.mean() - expected) < 0.001);
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
