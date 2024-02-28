--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Fixed-integer-ratio resampling with PTP timestamps.
--
-- This module connects a Tx and Rx data streams to an oversampled SERDES.
-- The SERDES operates at a fixed integer multiple of the actual line
-- rate.  As such, every on-the-wire bit is repeated N times.  Outgoing
-- data is upsampled by repetition, and incoming data is decimated by
-- the same factor.
--
-- The block is PTP-aware and will provide adjusted Rx timestamps.
-- On the transmit path, delay is constant and no adjustment is required.
-- However, the receive path timestamps must be adjusted to account for
-- the random alignment of incoming data transitions.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity io_resample_fixed is
    generic (
    IO_CLK_HZ   : positive;     -- Tx/Rx parallel clock (Hz)
    IO_WIDTH    : positive;     -- Tx/Rx width (internal)
    OVERSAMPLE  : positive;     -- Oversampling ratio
    MSB_FIRST   : boolean);     -- Serial I/O order
    port (
    -- Transmit / upsampling
    tx_in_data  : in  std_logic_vector(IO_WIDTH-1 downto 0);
    tx_out_data : out std_logic_vector(IO_WIDTH*OVERSAMPLE-1 downto 0);

    -- Receive / downsampling
    rx_clk      : in  std_logic;
    rx_in_data  : in  std_logic_vector(IO_WIDTH*OVERSAMPLE-1 downto 0);
    rx_in_time  : in  tstamp_t;
    rx_out_data : out std_logic_vector(IO_WIDTH-1 downto 0);
    rx_out_time : out tstamp_t;
    rx_out_lock : out std_logic;
    rx_reset_p  : in  std_logic := '0');
end io_resample_fixed;

architecture io_resample_fixed of io_resample_fixed is

-- Define internal type shortcuts.
subtype sreg_t is std_logic_vector(IO_WIDTH*OVERSAMPLE downto 0);
subtype wide_t is std_logic_vector(IO_WIDTH*OVERSAMPLE-1 downto 0);
subtype word_t is std_logic_vector(IO_WIDTH-1 downto 0);
type delay_table_t is array(0 to OVERSAMPLE-1) of tstamp_t;

-- Generate lookup table for timestamp adjustments.
function get_delay_rom return delay_table_t is
    constant TPAR : tstamp_t := get_tstamp_incr(IO_CLK_HZ);
    constant TBIT : tstamp_t := tstamp_div(TPAR, IO_WIDTH * OVERSAMPLE);
    variable result : delay_table_t := (others => (others => 'X'));
begin
    for n in result'range loop
        result(n) := tstamp_mult(TBIT, n) + TPAR;
    end loop;
    return result;
end function;

-- Internal state.
signal rx_in_flip   : wide_t;
signal rx_locked    : std_logic := '0';
signal rx_ontime    : integer range 0 to OVERSAMPLE-1 := 0;
signal rx_tstamp    : tstamp_t := TSTAMP_DISABLED;
signal rx_sreg      : sreg_t := (others => '0');
signal check_1st    : word_t := (others => '0');
signal check_mid    : word_t := (others => '0');

begin

-- Transmit simply repeats each input bit N times.
-- Combinational logic only, no clock or reset required.
gen_tx: for n in tx_out_data'range generate
    tx_out_data(n) <= tx_in_data(n / OVERSAMPLE);
end generate;

-- Receive path decimates with a predictable phase offset.
-- Combinational logic only, no clock or reset required.
gen_rx: for n in rx_out_data'range generate
    rx_out_data(n) <= rx_in_data(n * OVERSAMPLE) when MSB_FIRST
                 else rx_in_data((n+1) * OVERSAMPLE - 1);
end generate;

-- Drive other top-level outputs.
rx_out_time <= rx_tstamp;
rx_out_lock <= rx_locked;

-- Adjust the received timestamp based on current lock state.
-- An example with IO_WIDTH = 6 and OVERSAMPLE = 4:
--  Output sample:      v   v   v   v   v   v
--  rx_ontime = 0:   BBBBCCCCDDDDEEEEFFFFGGGG
--  rx_ontime = 1:   ABBBBCCCCDDDDEEEEFFFFGGG
--  rx_ontime = 2:   AABBBBCCCCDDDDEEEEFFFFGG
--  rx_ontime = 3:   AAABBBBCCCCDDDDEEEEFFFFG
p_adjust : process(rx_clk)
    constant delay_rom : delay_table_t := get_delay_rom;
    variable rx_offset : tstamp_t := (others => '0');
begin
    if rising_edge(rx_clk) then
        -- Note: Pipeline delay is precompensated by the lookup-table.
        if ((rx_in_time = TSTAMP_DISABLED) or (rx_locked = '0')) then
            rx_tstamp <= TSTAMP_DISABLED;
        else
            rx_tstamp <= rx_in_time + rx_offset;
        end if;
        rx_offset := delay_rom(rx_ontime);
    end if;
end process;

-- Convert input to normalized, LSB-first format.
rx_in_flip <= flip_vector(rx_in_data) when MSB_FIRST else rx_in_data;

-- Lock/unlock/search state machine.
-- Try each hypothesis sequentially, penalizing any signal with
-- 0/1 transitions in the middle of any window (check_mid) and
-- rewarding 0/1 transitions at window boundaries (check_1st).
p_search : process(rx_clk)
    function shift_ontime(curr, prev: wide_t; shift: natural) return sreg_t is
        variable temp : sreg_t := resize(
            shift_right(curr & prev, shift),
            IO_WIDTH * OVERSAMPLE + 1);
    begin
        return temp;
    end function;

    constant MAX_COUNT  : integer := 15;
    variable lock_ctr   : integer range 0 to MAX_COUNT := MAX_COUNT/2;
    variable check_tmp  : std_logic_vector(OVERSAMPLE downto 0);
    variable rx_prev    : wide_t := (others => '0');
begin
    if rising_edge(rx_clk) then
        -- Pipeline stage 3: Update search state.
        if (rx_reset_p = '1') then
            -- System reset.
            -- Note: Counter reset to half-scale allows time for pipeline
            --  to flush before moving to the next "rx_ontime" hypothesis.
            rx_locked <= '0';
            rx_ontime <= 0;
            lock_ctr := MAX_COUNT/2;
        elsif (or_reduce(check_1st) = '1' and or_reduce(check_mid) = '0') then
            -- Aligned transitions increment the lock counter.
            -- Incrementing to the max sets to the "locked" flag.
            if (lock_ctr = MAX_COUNT) then
                rx_locked <= '1';
            else
                lock_ctr := lock_ctr + 1;
            end if;
        else
            -- Misaligned or null transitions decrement the lock counter.
            -- If we reach zero, clear lock and try a new hypothesis.
            if (lock_ctr = 0) then
                rx_locked <= '0';
                rx_ontime <= (rx_ontime + 1) mod OVERSAMPLE;
                lock_ctr := MAX_COUNT/2;
            else
                lock_ctr := lock_ctr - 1;
            end if;
        end if;

        -- Pipeline stage 2: Check for expected and unexpected transitions.
        for n in 0 to IO_WIDTH-1 loop
            check_tmp := rx_sreg((n+1)*OVERSAMPLE downto n*OVERSAMPLE);
            check_1st(n) <= check_tmp(OVERSAMPLE) xor check_tmp(OVERSAMPLE-1);
            check_mid(n) <= not same_bits(check_tmp(OVERSAMPLE-1 downto 0));
        end loop;

        -- Pipeline stage 1: Shift input based on current hypothesis.
        rx_sreg <= shift_ontime(rx_in_flip, rx_prev, rx_ontime);
        rx_prev := rx_in_flip;
    end if;
end process;

end io_resample_fixed;
