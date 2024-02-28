--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Traffic generator/counter for use with other config_stats testbenches.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_stats_refsrc is
    generic (
    COUNT_WIDTH : natural;
    PRNG_SEED1  : positive := 1234;
    PRNG_SEED2  : positive := 5678);
    port (
    -- Traffic streams.
    prx_data    : out port_rx_m2s;
    ptx_data    : out port_tx_s2m;
    ptx_ctrl    : out port_tx_m2s;

    -- Reference counts.
    ref_bcbyte  : out natural;
    ref_bcfrm   : out natural;
    ref_rxbyte  : out natural;
    ref_rxfrm   : out natural;
    ref_txbyte  : out natural;
    ref_txfrm   : out natural;

    -- High-level control.
    rx_status   : in  port_status_t;
    rx_rate     : in  real;
    tx_rate     : in  real;
    burst_run   : in  std_logic;
    burst_done  : out std_logic;
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end port_stats_refsrc;

architecture port_stats_refsrc of port_stats_refsrc is

-- Saturation limit for each counter.
-- TODO: Support COUNT_WIDTH >= 30 bits?
constant COUNTER_MAX : natural := 2**COUNT_WIDTH - 1;

-- Tx and Rx data streams.
signal rx_data  : byte_t := (others => '0');
signal rx_last  : std_logic := '0';
signal rx_write : std_logic := '0';
signal rx_bcast : std_logic := '0';
signal rx_done  : std_logic := '0';
signal tx_data  : byte_t := (others => '0');
signal tx_last  : std_logic := '0';
signal tx_valid : std_logic := '0';
signal tx_ready : std_logic := '0';
signal tx_done  : std_logic := '0';

-- Reference counters.
signal bcbyte   : natural := 0;
signal bcfrm    : natural := 0;
signal rxbyte   : natural := 0;
signal rxfrm    : natural := 0;
signal txbyte   : natural := 0;
signal txfrm    : natural := 0;
signal rxdone   : std_logic := '0';
signal txdone   : std_logic := '0';

begin

-- Drive top-level signals.
prx_data.clk     <= clk;
prx_data.data    <= rx_data;
prx_data.last    <= rx_last;
prx_data.write   <= rx_write;
prx_data.rate    <= get_rate_word(1000);
prx_data.status  <= rx_status;
prx_data.tsof    <= TSTAMP_DISABLED;
prx_data.rxerr   <= '0';
prx_data.reset_p <= reset_p;
ptx_data.data    <= tx_data;
ptx_data.last    <= tx_last;
ptx_data.valid   <= tx_valid;
ptx_ctrl.clk     <= clk;
ptx_ctrl.ready   <= tx_ready;
ptx_ctrl.pstart  <= '1';
ptx_ctrl.tnow    <= TSTAMP_DISABLED;
ptx_ctrl.txerr   <= '0';
ptx_ctrl.reset_p <= reset_p;

ref_bcbyte       <= int_min(bcbyte, COUNTER_MAX);
ref_bcfrm        <= int_min(bcfrm,  COUNTER_MAX);
ref_rxbyte       <= int_min(rxbyte, COUNTER_MAX);
ref_rxfrm        <= int_min(rxfrm,  COUNTER_MAX);
ref_txbyte       <= int_min(txbyte, COUNTER_MAX);
ref_txfrm        <= int_min(txfrm,  COUNTER_MAX);
burst_done       <= rx_done and tx_done;

-- Tx and Rx data streams.
p_gen : process(clk)
    variable seed1  : positive := PRNG_SEED1;
    variable seed2  : positive := PRNG_SEED2;
    variable rand   : real := 0.0;
    variable rx_bc  : std_logic := '0';
    variable rx_cnt : natural := 0;
    variable rx_rem : natural := 0;
    variable tx_rem : natural := 0;
begin
    if rising_edge(clk) then
        -- Should we start a new Rx packet?
        -- (20% chance that any given frame is to broadcast address.)
        if (burst_run = '1' and rx_rem = 0) then
            uniform(seed1, seed2, rand);
            rx_rem := 18 + integer(floor(100.0 * rand));
            uniform(seed1, seed2, rand);
            rx_bc  := bool2bit(rand < 0.2);
            rx_cnt := 0;
        end if;
        rx_bcast <= rx_bc and bool2bit(rx_rem > 0);
        rx_done  <= bool2bit(burst_run = '0' and rx_rem = 0);

        -- Should we start a new Tx packet?
        if (burst_run = '1' and tx_rem = 0) then
            uniform(seed1, seed2, rand);
            tx_rem := integer(floor(100.0 * rand));
        end if;
        tx_done <= bool2bit(burst_run = '0' and tx_rem = 0);

        -- Generate Rx stream.
        uniform(seed1, seed2, rand);
        if (rx_rem > 0 and rand < rx_rate and reset_p = '0') then
            if (rx_bc = '1' and rx_cnt < 6) then
                -- Destination MAC = Broadcast (FF-FF-FF-FF-FF-FF)
                rx_data <= (others => '1');
            else
                -- All other bytes are completely random.
                for n in rx_data'range loop
                    uniform(seed1, seed2, rand);
                    rx_data(n) <= bool2bit(rand < 0.5);
                end loop;
            end if;
            rx_last  <= bool2bit(rx_rem = 1);
            rx_write <= '1';
            rx_cnt   := rx_cnt + 1;
            rx_rem   := rx_rem - 1;
        else
            rx_data  <= (others => '0');
            rx_write <= '0';
        end if;

        -- Generate Tx stream.
        if (reset_p = '1') then
            tx_data  <= (others => '0');
            tx_last  <= '0';
            tx_valid <= '0';
        elsif (tx_valid = '0' or tx_ready = '1') then
            uniform(seed1, seed2, rand);
            if (tx_rem > 0 and rand < tx_rate) then
                for n in rx_data'range loop
                    uniform(seed1, seed2, rand);
                    tx_data(n) <= bool2bit(rand < 0.5);
                end loop;
                tx_last  <= bool2bit(tx_rem = 1);
                tx_valid <= '1';
                tx_rem   := tx_rem - 1;
            else
                tx_data  <= (others => '0');
                tx_last  <= '0';
                tx_valid <= '0';
            end if;
        end if;

        uniform(seed1, seed2, rand);
        tx_ready <= bool2bit(rand < tx_rate);
    end if;
end process;

-- Reference counters
p_ref : process(clk)
    variable burst_run_d : std_logic := '0';
begin
    if rising_edge(clk) then
        if (reset_p = '1' or (burst_run = '1' and burst_run_d = '0')) then
            -- Reset counters and done flags at start of each burst.
            bcbyte  <= 0;
            bcfrm   <= 0;
            rxbyte  <= 0;
            rxfrm   <= 0;
            txbyte  <= 0;
            txfrm   <= 0;
        else
            -- Increment counters during each run.
            bcbyte  <= bcbyte   + u2i(rx_bcast and rx_write);
            bcfrm   <= bcfrm    + u2i(rx_bcast and rx_write and rx_last);
            rxbyte  <= rxbyte   + u2i(rx_write);
            rxfrm   <= rxfrm    + u2i(rx_write and rx_last);
            txbyte  <= txbyte   + u2i(tx_valid and tx_ready);
            txfrm   <= txfrm    + u2i(tx_valid and tx_ready and tx_last);
        end if;
        burst_run_d := burst_run;
    end if;
end process;

end port_stats_refsrc;
