--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- HDLC encoder (and decoder) Testbench
--
-- This unit test connects an HDLC encoder block to an HDLC decoder block.
-- Random byte streams are fed into the encoder and compared to the decoder
-- output.
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

entity hdlc_encoder_tb_helper is
    generic(
    BLOCK_BYTES : integer;
    USE_ADDRESS : boolean);
    port(
    test_done   : out std_logic);
end hdlc_encoder_tb_helper;

architecture helper of hdlc_encoder_tb_helper is

signal in_data      : byte_t := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;

signal enc_data     : std_logic;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

signal dec_write    : std_logic;

signal out_data     : byte_t;
signal out_write    : std_logic;
signal out_last     : std_logic;
signal out_error    : std_logic;
signal out_addr     : byte_t;

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

signal ref_data     : byte_t := (others => '0');
signal ref_last     : std_logic := '0';

signal rate_in      : real := 0.0;
signal rate_enc     : real := 0.0;

signal byte_count   : integer := 0;

signal test_done_i  : std_logic := '0';

begin

-- Clock gen
clk <= not clk after 5 ns; -- 1/(2*5 ns) = 100 MHz

p_count : process(clk, out_write)
begin
    if rising_edge(clk) and (reset_p = '1') then
        byte_count <= 0;
    elsif rising_edge(out_write) then
        if (byte_count = BLOCK_BYTES) then
            byte_count <= 1;
        else
            byte_count <= byte_count + 1;
        end if;
    end if;
end process;

-- Randomized input and reference data streams.
p_src : process(clk)
    constant RATE_EOF : real := 0.02;

    variable seed1a, seed1b : positive := 1234;
    variable seed2a, seed2b : positive := 5678;
    variable rand : real := 0.0;

    variable temp_data : byte_t := (others => '0');
    variable temp_last : std_logic := '0';
    variable first : std_logic := '1';

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
        elsif (in_valid = '1') and (in_ready = '1') then
            uniform(seed1a, seed2a, rand);
            in_last <= bool2bit(rand < RATE_EOF);
            uniform(seed1a, seed2a, rand);
            in_data <= float2byte(rand);
        end if;

        if (reset_p = '1') then
            ref_data   <= (others => '0');
            ref_last   <= '0';
            first      := '1';
        elsif (out_write = '1') then
            if (first = '1') then
                first := '0';
                uniform(seed1b, seed2b, rand);
                temp_last := bool2bit(rand < RATE_EOF);
                uniform(seed1b, seed2b, rand);
                temp_data := float2byte(rand);
            end if;

            -- Fill ref data and last, accounting for any padding
            if (BLOCK_BYTES > 0) then
                if (byte_count = BLOCK_BYTES-1) then
                    ref_data <= temp_data;
                    ref_last <= '1';

                    uniform(seed1b, seed2b, rand);
                    temp_last := bool2bit(rand < RATE_EOF);

                    uniform(seed1b, seed2b, rand);
                    temp_data := float2byte(rand);
                elsif (temp_last = '1') then
                    ref_data <= temp_data;
                    ref_last <= '0';

                    temp_data := (others => '0');
                else
                    ref_data <= temp_data;
                    ref_last <= temp_last;

                    uniform(seed1b, seed2b, rand);
                    temp_last := bool2bit(rand < RATE_EOF);

                    uniform(seed1b, seed2b, rand);
                    temp_data := float2byte(rand);
                end if;
            else
                ref_data <= temp_data;
                ref_last <= temp_last;

                uniform(seed1b, seed2b, rand);
                temp_last := bool2bit(rand < RATE_EOF);

                uniform(seed1b, seed2b, rand);
                temp_data := float2byte(rand);
            end if;
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

uut_enc : entity work.hdlc_encoder
    generic map(
    USE_ADDRESS => USE_ADDRESS,
    BLOCK_BYTES  => BLOCK_BYTES)
    port map(
    in_data   => in_data,
    in_last   => in_last,
    in_valid  => in_valid,
    in_ready  => in_ready,
    out_data  => enc_data,
    out_valid => enc_valid,
    out_ready => enc_ready,
    clk       => clk,
    reset_p   => reset_p);

dec_write <= enc_valid and enc_ready;

uut_dec : entity work.hdlc_decoder
    generic map(
    USE_ADDRESS => USE_ADDRESS)
    port map(
    in_data   => enc_data,
    in_write  => dec_write,
    out_data  => out_data,
    out_write => out_write,
    out_last  => out_last,
    out_error => out_error,
    out_addr  => out_addr,
    clk       => clk,
    reset_p   => reset_p);

-- Check output data stream.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (out_write = '1') then
            assert (out_data = ref_data) report "DATA mismatch" severity error;
            assert (out_last = ref_last) report "LAST mismatch" severity error;
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

    test_done_i <= '1';
    wait;
end process;

test_done <= test_done_i;

end helper;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity hdlc_encoder_tb is
    -- Top-level unit testbench, no I/O ports.
end hdlc_encoder_tb;

architecture tb of hdlc_encoder_tb is

signal test_done : std_logic_vector(0 to 3) := (others => '1');

begin

-- Instantiate each configuration under test:
uut0 : entity work.hdlc_encoder_tb_helper
    generic map(BLOCK_BYTES => -1, USE_ADDRESS => false)
    port map(test_done => test_done(0));

uut1 : entity work.hdlc_encoder_tb_helper
    generic map(BLOCK_BYTES => 5, USE_ADDRESS => false)
    port map(test_done => test_done(1));

uut2 : entity work.hdlc_encoder_tb_helper
    generic map(BLOCK_BYTES => 0, USE_ADDRESS => true)
    port map(test_done => test_done(2));

uut3 : entity work.hdlc_encoder_tb_helper
    generic map(BLOCK_BYTES => 5, USE_ADDRESS => true)
    port map(test_done => test_done(3));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
