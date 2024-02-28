--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Shift register with early/late slip command
--
-- The input to this block is a deserialized bit-stream, with exactly N
-- bits per clock at less than 100% duty cycle.  The output is the same
-- bit-stream, but with the option to slip earlier (i.e., drop any sample)
-- or slip later (i.e., repeat any sample.)  The output width may be equal
-- or larger than the input; in the latter case, bits will be repeated.
-- (This may be useful to objects that require prior history.)
--
-- For acceptable efficiency at a relatively large word size, the
-- implementation uses a pipelined barrel shifter.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity sgmii_data_slip is
    generic (
    IN_WIDTH    : positive;         -- Input width (max 64)
    OUT_WIDTH   : positive;         -- Output width (typ 64)
    DLY_STEP    : tstamp_t);        -- Sample period for delay compensation
    port (
    -- Input stream (MSB first)
    in_data     : in  std_logic_vector(IN_WIDTH-1 downto 0);
    in_next     : in  std_logic;    -- Clock enable
    in_tsof     : in  tstamp_t;     -- Timestamp

    -- Output stream (MSB first)
    out_data    : out std_logic_vector(OUT_WIDTH-1 downto 0);
    out_next    : out std_logic;    -- Clock enable
    out_tsof    : out tstamp_t;

    -- Command strobes for shifting sample position.
    slip_early  : in  std_logic;    -- Move earlier (drop sample)
    slip_late   : in  std_logic;    -- Move later (repeat sample)
    slip_ready  : out std_logic;    -- Ready for new command

    -- Clock and reset
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end sgmii_data_slip;

architecture sgmii_data_slip of sgmii_data_slip is

constant SHIFT_MAX  : integer := IN_WIDTH-1;
constant DLY_ZERO   : tstamp_t := (others => '0');
constant DLY_MAX    : tstamp_t := tstamp_mult(DLY_STEP, SHIFT_MAX);

signal sreg_data    : std_logic_vector(IN_WIDTH+OUT_WIDTH-1 downto 0) := (others => '0');
signal sreg_tsof    : tstamp_t := DLY_ZERO;
signal sreg_dly     : tstamp_t := DLY_MAX;
signal sreg_idx     : integer range 0 to SHIFT_MAX := 0;
signal sreg_next    : std_logic := '0';

signal flag_any     : std_logic;
signal flag_add     : std_logic := '0';
signal flag_drop    : std_logic := '0';
signal slip_ready_i : std_logic := '0';

signal out_data_i   : std_logic_vector(OUT_WIDTH-1 downto 0) := (others => '0');
signal out_tsof_i   : tstamp_t := (others => '0');
signal out_next_i   : std_logic := '0';

begin

-- Simulation only: Confirm slip commands are never double-asserted.
p_check : process(clk)
    variable cmd_prev : std_logic := '0';
begin
    if rising_edge(clk) then
        if (cmd_prev = '1') then
            assert (slip_early = '0' and slip_late = '0')
                report "Double command strobe" severity error;
        end if;
        cmd_prev := slip_early or slip_late;
    end if;
end process;

-- Control logic.
flag_any <= flag_add or flag_drop or slip_early or slip_late;

p_ctrl : process(clk)
    constant OUT_DELAY  : integer := 2;
    variable dly_count  : integer range 0 to OUT_DELAY := OUT_DELAY;
begin
    if rising_edge(clk) then
        -- Indicate whether we are ready for new commands:
        -- (And keep the flag low while output pipeline is flushed.)
        if (flag_any = '1') then
            slip_ready_i <= '0';
            dly_count    := OUT_DELAY;
        elsif (dly_count > 0) then
            slip_ready_i <= '0';
            dly_count    := dly_count - 1;
        else
            slip_ready_i <= '1';
        end if;

        -- Update the shift register and clock-enable strobe.
        if (in_next = '1') then
            sreg_data <= sreg_data(OUT_WIDTH-1 downto 0) & in_data; -- MSB first
            sreg_tsof <= in_tsof;       -- Latch timetamp
            sreg_next <= not flag_drop; -- Drive output unless we need to drop.
        else
            sreg_next <= flag_add;      -- Idle input --> insert sample.
        end if;

        -- Increment or decrement barrel-shifter index.
        -- Concurrently adjust the offset for the output timestamp.
        if (reset_p = '1') then
            sreg_idx <= 0;
            sreg_dly <= DLY_MAX;
        elsif (slip_late = '1' and sreg_idx /= 0) then
            sreg_idx <= sreg_idx - 1;   -- Normal increment
            sreg_dly <= sreg_dly + DLY_STEP;
        elsif (slip_early = '1' and sreg_idx /= SHIFT_MAX) then
            sreg_idx <= sreg_idx + 1;   -- Normal decrement
            sreg_dly <= sreg_dly - DLY_STEP;
        elsif (flag_add = '1' and in_next = '0') then
            sreg_idx <= 0;              -- Wraparound increment
            sreg_dly <= DLY_MAX;
        elsif (flag_drop = '1' and in_next = '1') then
            sreg_idx <= SHIFT_MAX;      -- Wraparound decrement
            sreg_dly <= DLY_ZERO;
        end if;

        -- Persistent flags for each wraparound type.
        if (reset_p = '1') then
            flag_add <= '0';
        elsif (slip_early = '1' and sreg_idx = SHIFT_MAX) then
            flag_add <= '1';
        elsif (in_next = '0') then
            flag_add <= '0';
        end if;

        if (reset_p = '1') then
            flag_drop <= '0';
        elsif (slip_late = '1' and sreg_idx = 0) then
            flag_drop <= '1';
        elsif (in_next = '1') then
            flag_drop <= '0';
        end if;
    end if;
end process;

-- Barrel shifter.  Radix-4 --> 2.5 stages, fixed delay.
p_shift : process(clk)
    function get_mult(x, r: integer) return integer is
    begin
        return (x/r) * r;
    end function;

    function get_shift(x: std_logic_vector; n: integer) return std_logic is
    begin
        if (n > x'left) then
            return '0';
        else
            return x(n);
        end if;
    end function;

    variable st1_data   : std_logic_vector(OUT_WIDTH+15 downto 0) := (others => '0');
    variable st1_tsof   : tstamp_t := (others => '0');
    variable st1_rem    : integer range 0 to 15;
    variable st1_next   : std_logic := '0';
    variable st2_data   : std_logic_vector(OUT_WIDTH+3 downto 0) := (others => '0');
    variable st2_tsof   : tstamp_t := (others => '0');
    variable st2_rem    : integer range 0 to 3;
    variable st2_next   : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Sanity check: This pipeline is only valid up to a certain size.
        assert (IN_WIDTH <= 64)
            report "Unsupported IN_WIDTH." severity failure;
        assert (OUT_WIDTH >= IN_WIDTH)
            report "Unsupported OUT_WIDTH." severity failure;

        -- Pipeline stage 3: Shift by 0/1/2/3 (Final output)
        for n in out_data'range loop
            out_data_i(n) <= get_shift(st2_data, n + st2_rem);
        end loop;
        out_tsof_i  <= st2_tsof;
        out_next_i  <= st2_next;

        -- Pipeline stage 2: Shift by 0/4/8/12
        for n in st2_data'range loop
            st2_data(n) := get_shift(st1_data, n + get_mult(st1_rem, 4));
        end loop;
        st2_rem     := st1_rem mod 4;
        st2_tsof    := st1_tsof;
        st2_next    := st1_next;

        -- Pipeline stage 1: Shift by 0/16/32/48
        for n in st1_data'range loop
            st1_data(n) := get_shift(sreg_data, n + get_mult(sreg_idx, 16));
        end loop;
        st1_rem     := sreg_idx mod 16;
        st1_tsof    := sreg_tsof + sreg_dly;
        st1_next    := sreg_next;
    end if;
end process;

slip_ready  <= slip_ready_i;
out_data    <= out_data_i;
out_tsof    <= out_tsof_i;
out_next    <= out_next_i;

end sgmii_data_slip;
