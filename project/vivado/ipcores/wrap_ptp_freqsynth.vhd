--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "ptp_clksynth" and "sgmii_serdes_tx"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity wrap_ptp_freqsynth is
    generic (
    RTC_CLK_HZ  : integer;
    SYNTH_HZ    : integer;
    SYNTH_IOSTD : string := "LVDS_25");
    port (
    -- Real-time clock
    rtc_clk     : in  std_logic;
    rtc_nsec    : in  std_logic_vector(31 downto 0);
    rtc_subns   : in  std_logic_vector(15 downto 0);

    -- SERDES clock must be 5x "rtc_clk"
    rtc_clk_5x  : in  std_logic;
    reset_p     : in  std_logic;

    -- Differential output.
    synth_txp   : out std_logic;
    synth_txn   : out std_logic);
end wrap_ptp_freqsynth;

architecture wrap_ptp_freqsynth of wrap_ptp_freqsynth is

signal rtc_time : tstamp_t;
signal par_data : std_logic_vector(9 downto 0);

begin

-- Concatenate the "nanoseconds" and "subnanoseconds" field from the RTC.
rtc_time <= unsigned(rtc_nsec) & unsigned(rtc_subns);

-- Synthesize a square wave at the designated frequency.
u_synth : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => RTC_CLK_HZ,
    PAR_COUNT   => 10,
    REF_MOD_HZ  => 1,
    MSB_FIRST   => true)
    port map(
    par_clk     => rtc_clk,
    par_tstamp  => rtc_time,
    par_out     => par_data,
    reset_p     => reset_p);

-- Serialize the parallel output signal.
u_serdes : entity work.sgmii_serdes_tx
    generic map(IOSTANDARD => SYNTH_IOSTD)
    port map(
    TxD_p_pin   => synth_txp,
    TxD_n_pin   => synth_txn,
    par_data    => par_data,
    clk_625     => rtc_clk,
    clk_125     => rtc_clk_5x,
    reset_p     => reset_p);

end wrap_ptp_freqsynth;
