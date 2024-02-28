--------------------------------------------------------------------------
-- Copyright 2019-2020 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SGMII Transmitter using OSERDESE2
--
-- This block accepts a 10-bit parallel data (as from an 8b/10b encoder)
-- and serializes the 1250 Mbps output using a leader/follower pair of
-- Xilinx 7-Series OSERDESE2 primitives.
--
-- To save power, this output enters tristate while in reset.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;

entity sgmii_serdes_tx is
    generic (
    IOSTANDARD  : string := "LVDS_25";  -- I/O standard for TxD_*
    POL_INVERT  : boolean := false);    -- Invert input polarity
    port (
    -- Top-level LVDS output pair.
    TxD_p_pin   : out std_logic;
    TxD_n_pin   : out std_logic;

    -- 8b/10b tokens, ready to be serialized.
    par_data    : in  std_logic_vector(9 downto 0);

    -- Clock and reset/shutdown
    clk_625     : in  std_logic;
    clk_125     : in  std_logic;
    reset_p     : in  std_logic);
end sgmii_serdes_tx;

architecture rtl of sgmii_serdes_tx is

subtype slv10 is std_logic_vector(9 downto 0);
constant PAR_MASK       : slv10 := (others => bool2bit(POL_INVERT));
signal par_inv          : slv10;
signal ser_dq, ser_tq   : std_logic;
signal shift1, shift2   : std_logic;

begin

-- LVDS output driver:
u_out: OBUFTDS
    generic map (IOSTANDARD => IOSTANDARD, SLEW => "FAST")
    port map (I => ser_dq, T => ser_tq, O => TxD_p_pin, OB => TxD_n_pin);

-- Leader serializer
u_ser0 : OSERDESE2
    generic map (
    DATA_RATE_OQ    => "DDR",   -- DDR, SDR
    DATA_RATE_TQ    => "SDR",   -- DDR, BUF, SDR
    DATA_WIDTH      => 10,      -- Parallel data width (2-8,10,14)
    INIT_OQ         => '0',     -- Initial value of OQ output (1’b0,1’b1)
    INIT_TQ         => '1',     -- Initial value of TQ output (1’b0,1’b1)
    SERDES_MODE     => "MASTER",-- Can't do anything about Xilinx terminology...
    SRVAL_OQ        => '0',     -- OQ output value when SR is used (1’b0,1’b1)
    SRVAL_TQ        => '1',     -- TQ output value when SR is used (1’b0,1’b1)
    TBYTE_CTL       => "FALSE", -- Enable tristate byte operation (FALSE, TRUE)
    TBYTE_SRC       => "FALSE", -- Tristate byte source (FALSE, TRUE)
    TRISTATE_WIDTH  => 1)       -- 3-state converter width (1,4)
    port map (
    OFB         => open,
    OQ          => ser_dq,
    SHIFTOUT1   => open,
    SHIFTOUT2   => open,
    TBYTEOUT    => open,
    TFB         => open,
    TQ          => ser_tq,
    CLK         => clk_625,
    CLKDIV      => clk_125,
    D1          => par_inv(9),  -- Bit "a" = First out
    D2          => par_inv(8),  -- Bit "b"
    D3          => par_inv(7),  -- Bit "c"
    D4          => par_inv(6),  -- Bit "d"
    D5          => par_inv(5),  -- Bit "e"
    D6          => par_inv(4),  -- Bit "f"
    D7          => par_inv(3),  -- Bit "g"
    D8          => par_inv(2),  -- Bit "h"
    OCE         => '1',
    RST         => reset_p,
    SHIFTIN1    => shift1,
    SHIFTIN2    => shift2,
    T1          => '0',
    T2          => '0',
    T3          => '0',
    T4          => '0',
    TBYTEIN     => '0',
    TCE         => '1');

-- Follower serializer
u_ser1 : OSERDESE2
    generic map (
    DATA_RATE_OQ    => "DDR",   -- DDR, SDR
    DATA_RATE_TQ    => "SDR",   -- DDR, BUF, SDR
    DATA_WIDTH      => 10,      -- Parallel data width (2-8,10,14)
    INIT_OQ         => '0',     -- Initial value of OQ output (1’b0,1’b1)
    INIT_TQ         => '1',     -- Initial value of TQ output (1’b0,1’b1)
    SERDES_MODE     => "SLAVE", -- Can't do anything about Xilinx terminology...
    SRVAL_OQ        => '0',     -- OQ output value when SR is used (1’b0,1’b1)
    SRVAL_TQ        => '1',     -- TQ output value when SR is used (1’b0,1’b1)
    TBYTE_CTL       => "FALSE", -- Enable tristate byte operation (FALSE, TRUE)
    TBYTE_SRC       => "FALSE", -- Tristate byte source (FALSE, TRUE)
    TRISTATE_WIDTH  => 1)       -- 3-state converter width (1,4)
    port map (
    OFB         => open,
    OQ          => open,
    SHIFTOUT1   => shift1,
    SHIFTOUT2   => shift2,
    TBYTEOUT    => open,
    TFB         => open,
    TQ          => open,
    CLK         => clk_625,
    CLKDIV      => clk_125,
    D1          => '0',         -- Unused in 10-bit mode,see UG471
    D2          => '0',
    D3          => par_inv(1),  -- Bit "i"
    D4          => par_inv(0),  -- Bit "j" = Last out
    D5          => '0',
    D6          => '0',
    D7          => '0',
    D8          => '0',
    OCE         => '1',
    RST         => reset_p,
    SHIFTIN1    => '0',
    SHIFTIN2    => '0',
    T1          => '0',
    T2          => '0',
    T3          => '0',
    T4          => '0',
    TBYTEIN     => '0',
    TCE         => '1');

-- Optionally invert the parallel output signal.
-- (This makes it easy to swap _P and _N signals for PCB optimization.)
par_inv <= par_data xor PAR_MASK;

end rtl;
