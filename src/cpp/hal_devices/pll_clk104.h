//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Device driver for the Xilinx CLK104 board (Clock Synth for the ZCU208)
//
// This is a simplified setup tool for PLLs on the Xilinx CLK104 clock
// synthesizer, which is intended for use with the ZCU208 development kit.
//
// The driver configures the Texas Instruments LMK04828 and LMX2594 PLLs
// to generate the specified ADC/DAC reference clocks.  It is intended for
// use with the "zcu208_clksynth" example design and does not allow access
// to many system features.
//
// For the initial version, both ADC and DAC clocks are fixed at 400 MHz.
// TODO: Adjustable ADC and DAC clock frequencies?
//
// Reference: https://docs.xilinx.com/r/en-US/ug1437-clk104
// Reference: https://www.ti.com/product/LMK04828
// Reference: https://www.ti.com/product/LMX2594
//

#pragma once

#include <hal_devices/i2c_sc18s602.h>
#include <hal_devices/i2c_tca9548.h>
#include <satcat5/cfgbus_gpio.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace device {
        namespace pll {
            class Clk104
                : public satcat5::cfg::SpiEventListener
                , public satcat5::poll::Timer
            {
            public:
                // Constructor links to the specified I2C bus.
                // An optional GPO register allows SPI readback.
                Clk104(
                    satcat5::cfg::I2cGeneric* i2c,
                    satcat5::cfg::GpoRegister* gpo);

                // Constants for "ref_sel", below.
                static constexpr u8 REF_EXT  = 0; // INPUT_REF (J11)
                static constexpr u8 REF_TCXO = 1; // TCXO (U4)
                static constexpr u8 REF_FPGA = 2; // SFP_REC_CLK

                // Start configuration process.
                void configure(
                    u8 ref_sel,     // See constants above.
                    u32 ref_hz,     // Reference clock frequency
                    bool verbose=false);

                // Configuration status?
                bool busy() const;      // Configuration in progress?
                bool ready() const;     // Configuration complete?
                u8 progress() const;    // Estimated progress (0-100%)

            protected:
                // Callbacks event handlers.
                void spi_done(unsigned nread, const u8* rbytes) override;
                void timer_event() override;

                // Pointer to the parent interface.
                satcat5::device::i2c::Tca9548  m_i2c;
                satcat5::device::i2c::Sc18is602 m_spi;
                satcat5::cfg::GpoRegister* const m_gpo;

                // Configuration parameters.
                u32 m_step;         // Next step to execute
                u8 m_retry;         // Remaining retries?
                u8 m_verbose;       // Log verbosity
                u8 m_lmk_refsel;    // LMK register
                u8 m_lmk_refdiv;    // LMK register
            };
        }
    }
}
