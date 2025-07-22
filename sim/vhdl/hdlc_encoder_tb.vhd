--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
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
    FRAME_BYTES : natural;  -- Number of bytes in frame excluding flags/FCS
    MSB_FIRST   : boolean); -- true for MSb first; false for LSb first
    port(
    test_done   : out std_logic);
end hdlc_encoder_tb_helper;

architecture helper of hdlc_encoder_tb_helper is

signal in_data      : byte_t := (others => '0');
signal in_valid     : std_logic := '0';
signal in_last      : std_logic := '0';
signal in_ready     : std_logic;

signal enc_data     : std_logic;
signal enc_valid    : std_logic;
signal enc_last     : std_logic;
signal enc_ready    : std_logic := '0';

signal dec_write    : std_logic;

signal out_data     : byte_t;
signal out_write    : std_logic;
signal out_last     : std_logic;

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

signal ref_data     : byte_t := (others => '0');
signal ref_last     : std_logic := '0';

signal rate_in      : real := 0.0;
signal rate_enc     : real := 0.0;

signal test_done_i  : std_logic := '0';

begin

-- Clock gen
clk <= not clk after 5 ns; -- 1/(2*5 ns) = 100 MHz

-- Randomized input and reference data streams.
p_src : process(clk)
    constant RATE_EOF  : real := 0.02;

    variable seed1a, seed1b : positive := 1234;
    variable seed2a, seed2b : positive := 5678;
    variable rand : real := 0.0;

    variable in_byte_count  : integer   := 0;
    variable ref_byte_count : integer   := 0;
    variable temp_last      : std_logic := '0';

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
            in_byte_count := 0;
        elsif (in_valid = '1') and (in_ready = '1') then
            if (in_last = '1') then
                in_byte_count := 0;
            else
                in_byte_count := in_byte_count + 1;
            end if;

            if (FRAME_BYTES = 0) then
                uniform(seed1a, seed2a, rand);
                in_data <= float2byte(rand);
                uniform(seed1a, seed2a, rand);
                in_last <= bool2bit(rand < RATE_EOF);
            else
                if (in_byte_count = (FRAME_BYTES-1)) then
                    uniform(seed1a, seed2a, rand);
                    in_data <= float2byte(rand);
                    in_last <= '1';
                else
                    uniform(seed1a, seed2a, rand);
                    in_data <= float2byte(rand);
                    uniform(seed1a, seed2a, rand);
                    in_last <= bool2bit(rand < RATE_EOF);
                end if;
            end if;
        end if;

        if (reset_p = '1') then
            ref_data <= (others => '0');
            ref_last <= '0';
            ref_byte_count := 0;
            temp_last := '0';
        elsif (out_write = '1') then
            if (ref_last = '1') then
                ref_byte_count := 0;
            else
                ref_byte_count := ref_byte_count + 1;
            end if;

            if (FRAME_BYTES = 0) then
                uniform(seed1b, seed2b, rand);
                ref_data <= float2byte(rand);
                uniform(seed1b, seed2b, rand);
                ref_last <= bool2bit(rand < RATE_EOF);
            else
                if (temp_last = '1') then
                    ref_data <= (others => '0');
                    if (ref_byte_count = (FRAME_BYTES-1)) then
                        ref_last  <= '1';
                        temp_last := '0';
                    else
                        ref_last <= '0';
                    end if;
                elsif (ref_byte_count = (FRAME_BYTES-1)) then
                    uniform(seed1b, seed2b, rand);
                    ref_data <= float2byte(rand);
                    ref_last <= '1';
                else
                    uniform(seed1b, seed2b, rand);
                    ref_data <= float2byte(rand);
                    uniform(seed1b, seed2b, rand);
                    ref_last <= bool2bit(rand < RATE_EOF);

                    if (rand < RATE_EOF) and
                            (ref_byte_count < FRAME_BYTES) then
                        temp_last := '1';
                        ref_last  <= '0';
                    else
                        temp_last := '0';
                    end if;
                end if;
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
    FRAME_BYTES => FRAME_BYTES,
    MSB_FIRST   => MSB_FIRST)
    port map(
    in_data   => in_data,
    in_valid  => in_valid,
    in_last   => in_last,
    in_ready  => in_ready,
    out_data  => enc_data,
    out_valid => enc_valid,
    out_last  => enc_last,
    out_ready => enc_ready,
    clk       => clk,
    reset_p   => reset_p);

dec_write <= enc_valid and enc_ready;

uut_dec : entity work.hdlc_decoder
    generic map(
    BUFFER_KBYTES => 1,
    MSB_FIRST     => MSB_FIRST)
    port map(
    in_data   => enc_data,
    in_write  => dec_write,
    out_data  => out_data,
    out_write => out_write,
    out_last  => out_last,
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
    generic map(
    FRAME_BYTES => 0, MSB_FIRST => false)
    port map(test_done => test_done(0));

uut1 : entity work.hdlc_encoder_tb_helper
    generic map(
    FRAME_BYTES => 0, MSB_FIRST => true)
    port map(test_done => test_done(1));

uut2 : entity work.hdlc_encoder_tb_helper
    generic map(
    FRAME_BYTES => 5, MSB_FIRST => false)
    port map(test_done => test_done(2));

uut3 : entity work.hdlc_encoder_tb_helper
    generic map(
    FRAME_BYTES => 10, MSB_FIRST => true)
    port map(test_done => test_done(3));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
