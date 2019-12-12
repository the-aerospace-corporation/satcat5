//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation
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
//
// PLL for the iCE40-HX8K breakout board. This takes the 12MHz oscillator
// and generates 50MHz (A) and 25MHz (B) clock outputs.
//

module rmii_serial_adapter_pll_dev(REFERENCECLK,
                                   PLLOUTCOREA,
                                   PLLOUTCOREB,
                                   PLLOUTGLOBALA,
                                   PLLOUTGLOBALB,
                                   RESET,
                                   LOCK);

input REFERENCECLK;
input RESET;    /* To initialize the simulation properly, the RESET signal (Active Low) must be asserted at the beginning of the simulation */
output PLLOUTCOREA;
output PLLOUTCOREB;
output PLLOUTGLOBALA;
output PLLOUTGLOBALB;
output LOCK;

SB_PLL40_2F_CORE rmii_serial_adapter_pll_dev_inst(.REFERENCECLK(REFERENCECLK),
                                                  .PLLOUTCOREA(PLLOUTCOREA),
                                                  .PLLOUTCOREB(PLLOUTCOREB),
                                                  .PLLOUTGLOBALA(PLLOUTGLOBALA),
                                                  .PLLOUTGLOBALB(PLLOUTGLOBALB),
                                                  .EXTFEEDBACK(),
                                                  .DYNAMICDELAY(),
                                                  .RESETB(RESET),
                                                  .BYPASS(1'b0),
                                                  .LATCHINPUTVALUE(),
                                                  .LOCK(LOCK),
                                                  .SDI(),
                                                  .SDO(),
                                                  .SCLK());

//\\ Fin=12, Fout=50;
defparam rmii_serial_adapter_pll_dev_inst.DIVR = 4'b0000;
defparam rmii_serial_adapter_pll_dev_inst.DIVF = 7'b1000010;
defparam rmii_serial_adapter_pll_dev_inst.DIVQ = 3'b100;
defparam rmii_serial_adapter_pll_dev_inst.FILTER_RANGE = 3'b001;
defparam rmii_serial_adapter_pll_dev_inst.FEEDBACK_PATH = "SIMPLE";
defparam rmii_serial_adapter_pll_dev_inst.DELAY_ADJUSTMENT_MODE_FEEDBACK = "FIXED";
defparam rmii_serial_adapter_pll_dev_inst.FDA_FEEDBACK = 4'b0000;
defparam rmii_serial_adapter_pll_dev_inst.DELAY_ADJUSTMENT_MODE_RELATIVE = "FIXED";
defparam rmii_serial_adapter_pll_dev_inst.FDA_RELATIVE = 4'b0000;
defparam rmii_serial_adapter_pll_dev_inst.SHIFTREG_DIV_MODE = 2'b00;
defparam rmii_serial_adapter_pll_dev_inst.PLLOUT_SELECT_PORTA = "GENCLK";
defparam rmii_serial_adapter_pll_dev_inst.PLLOUT_SELECT_PORTB = "GENCLK_HALF";
defparam rmii_serial_adapter_pll_dev_inst.ENABLE_ICEGATE_PORTA = 1'b0;
defparam rmii_serial_adapter_pll_dev_inst.ENABLE_ICEGATE_PORTB = 1'b0;

endmodule
