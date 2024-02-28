--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the preamble-insertion and preamble-removal blocks
--
-- This testbench generates a random data stream, passes it through
-- the preamble-insertion block, and then through the preamble-removal
-- block.  It confirms that the output stream matches the input, that
-- the inter-packet gap meets requirements, and that byte-repetition
-- modes are applied and detected correctly.
--
-- The test runs indefinitely, with good coverage within 2.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity eth_preamble_tb is
    -- Unit testbench: Two modes, no I/O ports.
    generic (DV_XOR_ERR : boolean := false);
end eth_preamble_tb;

architecture tb of eth_preamble_tb is

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';
signal reset_n      : std_logic := '0';

-- Input and reference streams.
signal in_data      : byte_t := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal in_write     : std_logic;
signal in_rep_rate  : byte_u := (others => '0');
signal in_rep_read  : std_logic;
signal ref_data     : byte_t;
signal ref_repeat   : byte_t;
signal ref_last     : std_logic;
signal ref_valid    : std_logic;

-- Intermediate signal conversions.
signal ptx_data     : port_tx_s2m;
signal ptx_ctrl     : port_tx_m2s;
signal mid_data     : byte_t;
signal mid_dv       : std_logic;
signal mid_err      : std_logic;
signal mid_cken     : std_logic := '0';
signal mid_rate     : port_rate_t := RATE_WORD_NULL;
signal prx_data     : port_rx_m2s;

-- Output stream.
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_write    : std_logic;
signal out_final    : std_logic;
signal out_error    : std_logic;
signal out_repeat   : byte_u := (others => '0');
signal out_count    : natural := 0;

-- Test control
signal test_rate    : real := 0.0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;
reset_n <= not reset_p;

-- Input stream generation.
p_in : process(clk_100)
begin
    if rising_edge(clk_100) then
        -- Randomize the input stream except for the first byte, which must
        -- never be 0xD5 to avoid confusing the repeat-detector.
        if (reset_p = '1') then
            in_data     <= (others => '0');
            in_last     <= '0';
            in_valid    <= '0';
        elsif (in_valid = '1' and in_ready = '0') then
            null;       -- Hold current output
        elsif (in_valid = '0' or in_last = '1') then
            in_data     <= (others => '1'); -- First byte in frame
            in_last     <= rand_bit(0.1);
            in_valid    <= '1';
        else
            in_data     <= rand_vec(8);     -- Any other byte
            in_last     <= rand_bit(0.1);
            in_valid    <= '1';
        end if;

        -- Randomize repetition after the setting is read for each frame.
        -- (In normal use it's quasi-static, no synchronization required.)
        if (reset_p = '1') then
            in_rep_rate <= (others => '0');
        elsif (in_rep_read = '1') then
            in_rep_rate <= to_unsigned(rand_int(15), 8);
        end if;

        -- Flow-control randomization.
        mid_cken <= rand_bit(test_rate);
    end if;
end process;

-- Reference stream is a delayed copy of input.
in_write    <= in_valid and in_ready;
out_final   <= out_write and out_last;

u_fifo_dat : entity work.fifo_smol_sync
    generic map(
    DEPTH_LOG2  => 6,
    IO_WIDTH    => 8)
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_write    => in_write,
    out_data    => ref_data,
    out_last    => ref_last,
    out_valid   => ref_valid,
    out_read    => out_write,
    clk         => clk_100,
    reset_p     => reset_p);

u_fifo_rep : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8)
    port map(
    in_data     => std_logic_vector(in_rep_rate),
    in_write    => in_rep_read,
    out_data    => ref_repeat,
    out_read    => out_final,
    clk         => clk_100,
    reset_p     => reset_p);

-- Map input stream to port signals.
ptx_data.data   <= in_data;
ptx_data.last   <= in_last;
ptx_data.valid  <= in_valid;
in_ready        <= ptx_ctrl.ready;

-- Unit under test: Preamble inseration
uut_tx : entity work.eth_preamble_tx
    generic map(
    DV_XOR_ERR  => DV_XOR_ERR)
    port map(
    tx_clk      => clk_100,
    tx_data     => ptx_data,
    tx_ctrl     => ptx_ctrl,
    out_data    => mid_data,
    out_dv      => mid_dv,
    out_err     => mid_err,
    tx_cken     => mid_cken,
    tx_pwren    => reset_n,
    rep_rate    => in_rep_rate,
    rep_read    => in_rep_read);

-- Measure inter-packet gap.
p_gap : process(clk_100)
    variable gap : natural := 0;
begin
    if rising_edge(clk_100) and (mid_cken = '1') then
        if (mid_dv = '1') then
            -- New or continued frame
            assert (gap = 0 or gap >= 12)
                report "Invalid inter-packet gap." severity error;
            gap := 0;
        else
            -- Gap between frames
            gap := gap + 1;
        end if;
    end if;
end process;

-- Unit under test: Preamble removal
uut_rx : entity work.eth_preamble_rx
    generic map(
    DV_XOR_ERR  => DV_XOR_ERR,
    REP_ENABLE  => true)
    port map(
    raw_clk     => clk_100,
    raw_lock    => reset_n,
    raw_cken    => mid_cken,
    raw_data    => mid_data,
    raw_dv      => mid_dv,
    raw_err     => mid_err,
    rate_word   => mid_rate,
    rep_rate    => out_repeat,
    status      => (others => '0'),
    rx_data     => prx_data);

-- Convert Rx port signals.
out_data    <= prx_data.data;
out_last    <= prx_data.last;
out_write   <= prx_data.write;
out_error   <= prx_data.rxerr;

-- Check the output stream.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        -- Check outputs against reference.
        if (out_write = '1' and ref_valid = '0') then
            report "Unexpected output data." severity error;
        elsif (out_write = '1') then
            assert (out_data = ref_data and out_last = ref_last)
                report "Output stream mismatch." severity error;
            assert (out_repeat = unsigned(ref_repeat))
                report "Repeat detection mismatch." severity error;
        end if;
        assert (out_error = '0')
            report "Unexpected error strobe." severity error;

        -- Cumulative count of output words.
        if (out_write = '1') then
            out_count <= out_count + 1;
            if (out_count = 4000) then
                report "All tests completed!";
            end if;
        end if;

        -- Derive rate from repeat-count.
        mid_rate <= get_rate_word(800 / (1 + to_integer(out_repeat)));
    end if;
end process;

-- Flow-control is a simple cosine pattern.
p_test : process
    variable t : real := 0.0;
begin
    test_rate <= 0.5 * (1.0 + cos(MATH_2_PI * t));
    t := (t + 0.001) mod 1.0;
    wait for 1 us;
end process;

end tb;
