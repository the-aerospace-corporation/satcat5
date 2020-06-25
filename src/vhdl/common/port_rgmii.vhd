--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- RGMII transceiver port (MAC-to-PHY or MAC-to-MAC)
--
-- This module implements the interface logic for an RGMII port,
-- adapting an external RGMII interface to the generic internal
-- format used throughout this design.
--
-- The reset signal for this block is also used to shut down the
-- clock output, to save power if the port is disabled.
--
-- The transmit path has an option to delay the output clock. Such
-- a delay is required by the RGMII standard and should be applied
-- exactly once (either using a delayed output, a long PCB trace, or
-- a phase-shift at the receiver). If no delay is desired, tie
-- clk_125 and clk_txc to the same source.  Otherwise, tie clk_txc
-- to 90-degree shifted clock (2.0 nsec delay).
--
-- The receive path has a similar option, to delay the incoming clock by
-- approximately 2 nsec.  As above, this delay is part of the RGMII standard
-- and must be applied exactly once.  To use, set RXCLK_DELAY = 2.0.
--
-- See also: Reduced Gigabit Media Independent Interface v 2.0 (April 2002)
-- https://web.archive.org/web/20160303171328/http://www.hp.com/rnd/pdfs/RGMIIv2_0_final_hp.pdf
--
-- Note: For cross-platform support, the block uses vendor-specific
--       I/O structures from io_microsemi, io_xilinx, etc.
-- Note: If the "shutdown" signal is used, hold reset_p for at least
--       1 msec after shutdown is released. (RXCLK_ALIGN mode only.)
-- Note: 10/100 Mbps modes are not supported.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity port_rgmii is
    generic (
    RXCLK_ALIGN : boolean := false; -- Enable precision clock-buffer deskew
    RXCLK_LOCAL : boolean := false; -- Enable input clock buffer (local)
    RXCLK_GLOBL : boolean := true;  -- Enable input clock buffer (global)
    RXCLK_DELAY : real := 0.0;      -- Input clock delay, in nanoseconds (typ. 0.0 or 2.0)
    RXDAT_DELAY : real := 0.0;      -- Input data/control delay, in nanoseconds
    POWER_SAVE  : boolean := true); -- Enable power-saving on idle ports
    port (
    -- External RGMII interface.
    rgmii_txc   : out std_logic;
    rgmii_txd   : out std_logic_vector(3 downto 0);
    rgmii_txctl : out std_logic;
    rgmii_rxc   : in  std_logic;
    rgmii_rxd   : in  std_logic_vector(3 downto 0);
    rgmii_rxctl : in  std_logic;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : out port_tx_s2m;

    -- Reference clock and reset.
    clk_125     : in  std_logic;    -- Main reference clock
    clk_txc     : in  std_logic;    -- Same clock or delayed clock
    reset_p     : in  std_logic;    -- Reset / port shutdown
    shdn_p      : in  std_logic := '0'); -- Long-term shutdown (optional)
end port_rgmii;

architecture port_rgmii of port_rgmii is

signal txen, txen_d     : std_logic := '0';
signal txdata           : std_logic_vector(7 downto 0) := (others => '0');
signal txmeta           : std_logic_vector(3 downto 0);
signal txdv, txerr      : std_logic := '0';

signal rxclk            : std_logic;
signal rxlock           : std_logic := '0';
signal rxdata           : std_logic_vector(7 downto 0) := (others => '0');
signal rxdv, rxerr      : std_logic;
signal rxdiv_t          : std_logic := '0'; -- Toggle in rxclk domain
signal rxdiv_s          : std_logic;        -- Strobe in clk_125 domain

signal reset_sync       : std_logic;        -- Reset sync'd to clk_125

begin

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => clk_125);

-- Instantiate platform-specific I/O structures:
-- Note: For symmetry with clock input path, set DELAY_NSEC = 0.0 on all
--       inputs, rather than bypassing the delay-control structure.
u_txc : entity work.ddr_output
    port map(
    d_re    => txen_d,
    d_fe    => '0',
    clk     => clk_txc, -- Optionally delayed clock
    q_pin   => rgmii_txc);
u_txctl : entity work.ddr_output
    port map(
    d_re    => txdv,
    d_fe    => txerr,
    clk     => clk_125,
    q_pin   => rgmii_txctl);

u_rxctl : entity work.ddr_input
    generic map(DELAY_NSEC => RXDAT_DELAY)
    port map(
    d_pin   => rgmii_rxctl,
    clk     => rxclk,
    q_re    => rxdv,
    q_fe    => rxerr);

gen_clk_int : if not (RXCLK_ALIGN or RXCLK_LOCAL or RXCLK_GLOBL) generate
    rxclk <= rgmii_rxc; -- Recommended for simulation ONLY.
end generate;

gen_clk_ext : if (RXCLK_ALIGN or RXCLK_LOCAL or RXCLK_GLOBL) generate
    u_rxc : entity work.clk_input
        generic map(
        CLKIN_MHZ   => 125.0,
        GLOBAL_BUFF => RXCLK_GLOBL,
        DESKEW_EN   => RXCLK_ALIGN,
        DELAY_NSEC  => RXCLK_DELAY)
        port map(
        reset_p => reset_p,
        shdn_p  => shdn_p,
        clk_pin => rgmii_rxc,
        clk_out => rxclk);
end generate;

gen_data_pins : for n in 0 to 3 generate
    u_txd : entity work.ddr_output
        port map(
        d_re    => txdata(n),
        d_fe    => txdata(n+4),
        clk     => clk_125,
        q_pin   => rgmii_txd(n));
    u_rxd : entity work.ddr_input
        generic map(DELAY_NSEC => RXDAT_DELAY)
        port map(
        d_pin   => rgmii_rxd(n),
        clk     => rxclk,
        q_re    => rxdata(n),
        q_fe    => rxdata(n+4));
end generate;

-- Clock-detection state machine:
p_rxdiv : process(rxclk)
    variable count : unsigned(1 downto 0) := (others => '0');
begin
    if rising_edge(rxclk) then
        -- Divide received clock by 4.
        count   := count + 1;
        rxdiv_t <= count(count'left);
    end if;
end process;

hs_rxdiv : sync_toggle2pulse
    port map(
    in_toggle   => rxdiv_t,
    out_strobe  => rxdiv_s,
    out_clk     => clk_125);

p_detect : process(clk_125)
    constant POLL_INTERVAL  : integer := 12500000;  -- 100 msec @ 125 MHz
    constant POLL_ACTIVE    : integer := 125000;    -- 1 msec @ 125 MHz
    variable count_tx   : integer range 0 to POLL_INTERVAL-1 := 0;
    variable count_rx   : unsigned(7 downto 0) := (others => '0');
    variable rxfirst    : std_logic := '0';
begin
    if rising_edge(clk_125) then
        -- Activate or deactivate the transmit clock.
        if (reset_sync = '1') then
            -- Interface shutdown.
            txen <= '0';
            count_tx := 0;
        elsif (rxlock = '1' or not POWER_SAVE) then
            -- Link is active (or in always-on mode).
            txen <= '1';
            count_tx := 0;
        else
            -- No Rx clock detected, shut down Tx most of the time to save
            -- power, waking up periodically in case other side needs it.
            txen <= bool2bit(count_tx < POLL_ACTIVE);
            if (count_tx = POLL_INTERVAL-1) then
                count_tx := 0;
            else
                count_tx := count_tx + 1;
            end if;
        end if;

        -- Delay enable signal by one clock to sync with data.
        txen_d <= txen;

        -- Enable receiver after two clock-activity strobes.
        if (reset_sync = '1' or count_rx = 0) then
            -- Reset or clock watchdog reached zero --> Shutdown.
            rxlock  <= '0';
            rxfirst := '0';
        elsif (rxdiv_s = '1') then
            -- Sanity-check on estimated link rate.
            -- Note: 10 Mbps mode gets one strobe every 200 clocks!
            assert (rxfirst = '0' or count_rx >= 245)
                report "Detected 10/100 interface mode" severity warning;
            -- Wait for two activity strobes before enabling interface.
            rxlock  <= rxfirst;
            rxfirst := '1';
        end if;

        -- Watchdog timer for detecting Rx clock activity.
        if (rxdiv_s = '1') then
            count_rx := (others => '1');
        elsif (count_rx > 0) then
            count_rx := count_rx - 1;
        end if;
    end if;
end process;

-- Receive state machine, including preamble removal.
u_amble_rx : entity work.eth_preamble_rx
    generic map(DV_XOR_ERR  => true)
    port map(
    raw_clk     => rxclk,
    raw_lock    => rxlock,
    raw_data    => rxdata,
    raw_dv      => rxdv,
    raw_err     => rxerr,
    rx_data     => rx_data);

-- Transmit state machine, including insertion of preamble,
-- start-of-frame delimiter, and inter-packet gap.
txmeta <= "110" & rxlock;   -- 1 Gbps full duplex
u_amble_tx : entity work.eth_preamble_tx
    generic map(DV_XOR_ERR => true)
    port map(
    out_data    => txdata,
    out_dv      => txdv,
    out_err     => txerr,
    tx_clk      => clk_125,
    tx_pwren    => txen,
    tx_pkten    => rxlock,
    tx_idle     => txmeta,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl);

end port_rgmii;
