--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SLIP-Encoder (and -Decoder) Testbench
--
-- This unit test connects an SLIP-Encoder block to an SLIP-decoder block.
-- Random byte streams from 1-100 bytes long are fed into the encoder and
-- compared to the decoder output.  Off-nominal decoder conditions are
-- tested in a separate unit test.
--
-- The complete test takes just under 4.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.floor;
use     ieee.math_real.uniform;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;

entity slip_encoder_tb is
    -- Testbench --> No I/O ports
end slip_encoder_tb;

architecture tb of slip_encoder_tb is

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal rate_in      : real := 0.0;
signal rate_enc     : real := 0.0;

signal in_data      : byte_t := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;

signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic := '0';
signal enc_write    : std_logic;

signal ref_data     : byte_t := (others => '0');
signal ref_last     : std_logic := '0';
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_write    : std_logic;
signal out_error    : std_logic;
signal out_rcvd     : integer := 0;

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Randomized input and reference data streams.
p_src : process(clk)
    constant RATE_EOF : real := 0.02;

    variable seed1a, seed1b : positive := 1234;
    variable seed2a, seed2b : positive := 5678;
    variable rand : real := 0.0;

    function float2byte(constant x: real) return byte_t is
        variable result : byte_t := std_logic_vector(
            to_unsigned(integer(floor(x * 256.0)), 8));
    begin
        return result;
    end function;
begin
    if rising_edge(clk) then
        -- Input and reference use identical PRNGs.
        if (reset_p = '1') then
            in_data <= (others => '0');
            in_last <= '0';
        elsif (in_valid = '1' and in_ready = '1') then
            uniform(seed1a, seed2a, rand);
            in_data <= float2byte(rand);
            uniform(seed1a, seed2a, rand);
            in_last <= bool2bit(rand < RATE_EOF);
        end if;

        if (reset_p = '1') then
            ref_data <= (others => '0');
            ref_last <= '0';
        elsif (out_write = '1') then
            uniform(seed1b, seed2b, rand);
            ref_data <= float2byte(rand);
            uniform(seed1b, seed2b, rand);
            ref_last <= bool2bit(rand < RATE_EOF);
        end if;
    end if;
end process;

-- Encoder flow control randomization.
p_flow : process(clk)
    variable seed1  : positive := 517501;
    variable seed2  : positive := 985171;
    variable rand   : real := 0.0;
begin
    if rising_edge(clk) then
        -- Input flow control: Random chance of generating new data.
        if (reset_p = '1') then
            in_valid <= '0';
        elsif (in_valid = '0' or in_ready = '1') then
            uniform(seed1, seed2, rand);
            in_valid <= bool2bit(rand < rate_in);
        end if;

        -- Output flow control: Random chance of accepting data.
        uniform(seed1, seed2, rand);
        enc_ready <= bool2bit(rand < rate_enc);
    end if;
end process;

-- UUT Encoder
uut_enc : entity work.slip_encoder
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => enc_data,
    out_valid   => enc_valid,
    out_ready   => enc_ready,
    refclk      => clk,
    reset_p     => reset_p);

-- UUT Decoder
enc_write <= enc_valid and enc_ready;
uut_dec : entity work.slip_decoder
    port map(
    in_data     => enc_data,
    in_write    => enc_write,
    out_data    => out_data,
    out_write   => out_write,
    out_last    => out_last,
    decode_err  => out_error,
    reset_p     => reset_p,
    refclk      => clk);

-- Check output data stream.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (out_write = '1') then
            assert (out_data = ref_data) report "DATA mismatch" severity error;
            assert (out_last = ref_last) report "LAST mismatch" severity error;
            if (out_last = '1') then
                out_rcvd <= out_rcvd + 1;
            end if;
        end if;
        assert (out_error = '0')
            report "Unexpected decoder error" severity error;
    end if;
end process;

-- Overall test control
p_test : process
begin
    -- Reset everything at start of test.
    reset_p <= '1';
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    -- Test a few different flow-control scenarios.
    rate_in <= 0.1;     rate_enc <= 1.0;    wait for 990 us;
    rate_in <= 1.0;     rate_enc <= 0.1;    wait for 1 ms;
    rate_in <= 0.5;     rate_enc <= 0.5;    wait for 1 ms;
    rate_in <= 1.0;     rate_enc <= 1.0;    wait for 1 ms;

    report "All tests completed.";
    wait;
end process;

end tb;
