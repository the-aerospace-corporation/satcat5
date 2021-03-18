--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- RGII transceiver port (MAC-to-PHY or MAC-to-MAC)
--
-- This module implements the interface logic for an RMII port, adapting
-- an external RMII interface to the generic internal format used
-- throughout this design.  It supports both 10 Mbps and 100 Mbps modes.
--
-- The RMII interface uses a 50 MHz reference clock that may be sourced
-- by the MAC or by an external oscillator, depending on the design.
-- If this block is the clock source, connect rmii_clkin internally
-- and connect rmii_clkout to the output pin.  If this block is the
-- clock sink, connect rmii_clkin to the pin and leave rmii_clkout open.
--
-- The reset signal for this block is also used to shut down the
-- clock output, to save power if the port is disabled.
--
-- See also: RMII Specification v1.2 (March 1998)
-- http://ebook.pldworld.com/_eBook/-Telecommunications,Networks-/TCPIP/RMII/rmii_rev12.pdf
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity port_rmii is
    generic (
    MODE_CLKOUT : boolean := true);     -- Enable clock output?
    port (
    -- External RMII interface.
    rmii_txd    : out std_logic_vector(1 downto 0);
    rmii_txen   : out std_logic;        -- Data-valid strobe
    rmii_txer   : out std_logic;        -- Error strobe (optional)
    rmii_rxd    : in  std_logic_vector(1 downto 0);
    rmii_rxen   : in  std_logic;        -- Carrier-sense / data-valid (DV_CRS)
    rmii_rxer   : in  std_logic;        -- Error strobe

    -- Internal or external clock.
    rmii_clkin  : in  std_logic;        -- 50 MHz reference
    rmii_clkout : out std_logic;        -- Optional clock output

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : out port_tx_s2m;

    -- Other control
    lock_refclk : in  std_logic;        -- Separate clock for lock-detect
    mode_fast   : in  std_logic;        -- 10 Mbps or 100 Mbps mode?
    reset_p     : in  std_logic);       -- Reset / shutdown
end port_rmii;

architecture port_rmii of port_rmii is

-- Raw I/O registers
signal txdv, rxen, rxerr    : std_logic := '0';
signal txdata, rxdata       : std_logic_vector(1 downto 0) := (others => '0');
signal reg_clken, reg_txen  : std_logic := '0';
signal reg_txd              : std_logic_vector(1 downto 0) := (others => '0');

-- Receive-clock detection.
signal rxclk_tog            : std_logic := '0'; -- Toggle in rx_clk
signal rxclk_det            : std_logic := '0'; -- Strobe in lock_refclk
signal rxclk_halt           : std_logic := '1'; -- Flat in lock_refclk

-- All other control signals
signal status_word          : port_status_t;
signal rxclk                : std_logic;
signal txrx_halt            : std_logic := '1';
signal txrx_lock, txrx_cken : std_logic := '0';
signal tx_byte,   rx_byte   : std_logic_vector(7 downto 0) := (others => '0');
signal tx_bvalid, rx_bvalid : std_logic := '0';
signal tx_bnext,  rx_bnext  : std_logic := '0';

begin

-- Instantiate the appropriate clock configuration:
clk_int : if MODE_CLKOUT generate
    -- Internal reference clock, no buffer needed.
    rxclk <= rmii_clkin;

    -- Drive output clock.
    u_txclk : entity work.ddr_output
        port map(
        d_re    => reg_clken,
        d_fe    => '0',
        clk     => rxclk,
        q_pin   => rmii_clkout);
end generate;

clk_ext : if not MODE_CLKOUT generate
    -- External reference clock, instantiate buffer.
    u_rxclk : entity work.clk_input
        generic map(CLKIN_MHZ => 50.0)
        port map(
        reset_p => reset_p,
        clk_pin => rmii_clkin,
        clk_out => rxclk);

    -- Output clock (optional) is the buffered signal.
    rmii_clkout <= rxclk;
end generate;

-- First-stage input and output buffers.
-- No resets or other logic, to ensure it can be absorbed into IOB.
rmii_txd    <= reg_txd;
rmii_txen   <= reg_txen;
rmii_txer   <= '0';

p_iobuf : process(rxclk)
begin
    if rising_edge(rxclk) then
        reg_clken  <= txrx_lock;
        reg_txd    <= txdata;
        reg_txen   <= txdv;

        rxdata  <= rmii_rxd;
        rxen    <= rmii_rxen;
        rxerr   <= rmii_rxer;
    end if;
end process;

-- Use a separate clock for detecting rxclk.
p_lock : process(lock_refclk)
    -- RXCLK_DET strobe every 16 rxclk --> 50 MHz / 16 = 3.1 MHz.
    -- Reference clock 25-250 MHz typ. --> Wait up to 256 clocks.
    constant WDOG_MAX : integer := 255;
    variable wdog_ctr : integer range 0 to WDOG_MAX := 0;
begin
    if rising_edge(lock_refclk) then
        rxclk_halt <= bool2bit(wdog_ctr = 0);
        if (reset_p = '1') then
            wdog_ctr := 0;
        elsif (rxclk_det = '1') then
            wdog_ctr := WDOG_MAX;
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;
        end if;
    end if;
end process;

u_clkdet : sync_toggle2pulse
    port map(
    in_toggle   => rxclk_tog,
    out_strobe  => rxclk_det,
    out_clk     => lock_refclk);
u_lock : sync_reset
    port map(
    in_reset_p  => rxclk_halt,
    out_reset_p => txrx_halt,
    out_clk     => rxclk);

txrx_lock <= not txrx_halt;

-- Clock divider and shift registers convert 2-bit I/O to bytes.
-- Note: Within each byte, all Tx/Rx shift register logic is LSB-first.
p_sreg : process(rxclk)
    variable rx_wait    : std_logic := '1';
    variable tx_count   : integer range 0 to 3 := 0;
    variable rx_count   : integer range 0 to 3 := 0;
    variable clk_count  : integer range 0 to 9 := 0;
    variable tog_count  : unsigned(4 downto 0) := (others => '0');
begin
    if rising_edge(rxclk) then
        -- For lock-detection, generate toggle every 16 clocks.
        tog_count := tog_count + 1;
        rxclk_tog <= tog_count(tog_count'left);

        -- Update the Tx & Rx shift registers (LSB first, no reset).
        if (txrx_cken = '1') then
            txdata  <= tx_byte(2*tx_count+1 downto 2*tx_count);
            rx_byte <= rxdata & rx_byte(7 downto 2);
        end if;

        -- Update all counter and status registers.
        tx_bnext <= '0';
        rx_bnext <= '0';
        if (txrx_lock = '0') then
            -- Reset / shutdown.
            txdv        <= '0';
            tx_count    := 0;
            rx_count    := 0;
            rx_bvalid   <= '0';
            rx_wait     := '1';
        elsif (txrx_cken = '1') then
            -- Transmission occurs on a fixed schedule.
            if (tx_count = 0) then
                txdv <= tx_bvalid;  -- Latch value at start of byte
            end if;
            if ((mode_fast = '0' and tx_count = 3) or
                (mode_fast = '1' and tx_count = 2)) then
                -- Strobe just before end of current byte, so upstream
                -- source can have the next one ready in time.
                tx_bnext <= '1';
            end if;
            if (tx_count = 3) then
                tx_count := 0;
            else
                tx_count := tx_count + 1;
            end if;

            -- Update the byte-valid flag on byte boundaries.
            -- There is some complexity here because DV/CRS may be asserted
            -- before the preamble, and it may toggle near the end of the
            -- packet due to FIFO buffering (see RMII standard, Figure 2)
            if (rx_wait = '1') then
                -- Waiting for start of preamble.
                rx_count  := 1;
                rx_bvalid <= '0';   -- No valid data yet
                rx_bnext  <= '1';   -- Flush pipeline
                if (rxen = '1' and rxdata /= "00") then
                    rx_wait := '0';     -- Got start of amble
                end if;
            elsif (rx_count /= 3) then
                -- Waiting for end of byte (every four bit pairs).
                rx_count := rx_count + 1;
            else
                -- Update "valid" flag on last bit-pair.
                rx_bvalid <= rxen;
                rx_bnext  <= '1';
                rx_count  := 0;
                rx_wait   := not rxen;
            end if;
        end if;

        -- Clock enable 100% or 10% depending on link rate.
        -- (Note: Bit phasing is arbitrary in 10 Mbps mode.)
        txrx_cken <= txrx_lock and bool2bit(clk_count = 0);
        if (mode_fast = '1' or clk_count = 9) then
            clk_count := 0;
        else
            clk_count := clk_count + 1;
        end if;
    end if;
end process;

-- Upstream status reporting.
status_word <= (
    0 => reset_p,
    1 => rxclk_halt,
    2 => txrx_lock,
    3 => mode_fast,
    others => '0');

-- Preamble insertion and removal.
u_amble_rx : entity work.eth_preamble_rx
    generic map(
    RATE_MBPS   => 100)
    port map(
    raw_clk     => rxclk,
    raw_lock    => txrx_lock,
    raw_cken    => rx_bnext,
    raw_data    => rx_byte,
    raw_dv      => rx_bvalid,
    raw_err     => rxerr,
    status      => status_word,
    rx_data     => rx_data);

u_amble_tx : entity work.eth_preamble_tx
    port map(
    out_data    => tx_byte,
    out_dv      => tx_bvalid,
    out_err     => open,
    tx_clk      => rxclk,
    tx_cken     => tx_bnext,
    tx_pwren    => txrx_lock,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl);

end port_rmii;
