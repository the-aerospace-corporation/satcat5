--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- COBS Encoder and Decoder Testbench
--
-- This is a unit test for the COBS Encoder block (cobs_encoder.vhd)
-- and the matching Decoder block (cobs_decoder.vhd).
-- It uses a series of canned input/output pairs to evaluate specific
-- edge cases, then rounds out the test with random test vectors.
--
-- The complete test takes 1.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.uniform;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity cobs_encoder_tb is
    -- Testbench --> No I/O ports
end cobs_encoder_tb;

architecture tb of cobs_encoder_tb is

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal in_rate      : real := 0.0;
signal mid_rate     : real := 0.0;
signal test_idx     : integer := 0;

signal in_data      : byte_t := (others => 'X');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal mid_data     : byte_t;
signal mid_ref      : byte_t := (others => 'X');
signal mid_last     : std_logic;
signal mid_valid    : std_logic;
signal mid_ready    : std_logic := '0';
signal mid_write    : std_logic;
signal out_data     : byte_t;
signal out_ref      : byte_t := (others => 'X');
signal out_last     : std_logic;
signal out_write    : std_logic;

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Encoder under test
u_enc : entity work.cobs_encoder
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => mid_data,
    out_last    => mid_last,
    out_valid   => mid_valid,
    out_ready   => mid_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Decoder under test
mid_write <= mid_valid and mid_ready;

u_dec : entity work.cobs_decoder
    port map(
    in_data     => mid_data,
    in_write    => mid_write,
    out_data    => out_data,
    out_last    => out_last,
    out_write   => out_write,
    out_result  => open,
    clk         => clk,
    reset_p     => reset_p);

-- Test control.
p_test : process
    procedure run_one(raw, enc: std_logic_vector) is
        -- Normalize the reference vector format.
        variable raw_bytes : positive := raw'length / 8;
        variable enc_bytes : natural := enc'length / 8;
        variable v_raw : std_logic_vector(0 to 8*raw_bytes-1) := raw;
        variable v_enc : std_logic_vector(0 to 8*enc_bytes-1) := enc;
        -- Byte counters for each read position.
        variable p_in, p_mid, p_out : integer := 0;
        variable wdog : integer := 0;
    begin
        -- Set initial conditions.
        test_idx    <= test_idx + 1;
        in_data     <= (others => 'X');
        in_last     <= '0';
        in_valid    <= '0';
        mid_ready   <= '0';
        mid_ref     <= (others => 'X');
        out_ref     <= (others => 'X');

        -- Run the test to completion.
        while (p_out < raw_bytes and wdog < 100) loop
            -- Generate the input sequence.
            wait until rising_edge(clk);
            if (in_valid = '1' and in_ready = '0') then
                in_valid <= '1';    -- Hold current
            elsif (p_in < raw_bytes and rand_float < in_rate) then
                in_valid <= '1';    -- Next byte
                in_data  <= v_raw(8*p_in to 8*p_in+7);
                p_in := p_in + 1;
                in_last  <= bool2bit(p_in = raw_bytes);
            elsif (in_ready = '1') then
                in_valid <= '0';    -- Byte consumed
                in_data  <= (others => 'X');
                in_last  <= '0';
            end if;

            -- Flow-control randomization.
            mid_ready <= bool2bit(rand_float < mid_rate);

            -- Optionally check the encoded signal.
            -- (Fixed tests provide this vector; random ones do not.)
            if (p_mid < enc_bytes and mid_write = '1') then
                p_mid := p_mid + 1;
                assert (mid_data = mid_ref)
                    report "Encoded data mismatch." severity error;
                assert (mid_last = bool2bit(p_mid = enc_bytes))
                    report "Encoded last mismatch." severity error;
            end if;
            if (p_mid < enc_bytes) then
                mid_ref <= v_enc(8*p_mid to 8*p_mid+7);
            else
                mid_ref <= (others => 'X');
            end if;

            -- Check the final decoded output signal.
            if (out_write = '1') then
                p_out := p_out + 1;
                assert (out_data = out_ref)
                    report "Decoded data mismatch." severity error;
                assert (out_last = bool2bit(p_out = raw_bytes))
                    report "Decoded last mismatch." severity error;
            end if;
            if (p_out < raw_bytes) then
                out_ref <= v_raw(8*p_out to 8*p_out+7);
            else
                out_ref <= (others => 'X');
            end if;

            -- Inactivity timeout?
            if (in_valid = '1' or mid_write = '1' or out_write = '1') then
                wdog := 0;
            else
                wdog := wdog + 1;
            end if;
        end loop;

        -- Flush pipeline.
        assert (p_out = raw_bytes)
            report "Missing end-of-frame (timeout)." severity error;
        in_data     <= (others => 'X');
        in_last     <= '0';
        in_valid    <= '0';
        mid_ready   <= '1';
        mid_ref     <= (others => 'X');
        out_ref     <= (others => 'X');
        for n in 1 to 50 loop
            wait until rising_edge(clk);
            assert (mid_write = '0' and out_write = '0')
                report "Unexpected trailing data." severity error;
        end loop;
    end procedure;

    -- Run each of the examples from the Wikipedia page:
    -- https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
    procedure run_fixed(ri, ro: real) is
    begin
        -- Set flow-control rate for this test series.
        in_rate     <= ri;
        mid_rate    <= ro;
        -- Run each test with canned data.
        run_one(x"00",          x"010100");
        run_one(x"0000",        x"01010100");
        run_one(x"001100",      x"0102110100");
        run_one(x"11220033",    x"031122023300");
        run_one(x"11223344",    x"051122334400");
        run_one(x"11000000",    x"021101010100");
        run_one(
            x"0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20" &
            x"2122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F40" &
            x"4142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F60" &
            x"6162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F80" &
            x"8182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0" &
            x"A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0" &
            x"C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0" &
            x"E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFE",
            x"FF0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F" &
            x"202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F" &
            x"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F" &
            x"606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F" &
            x"808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9F" &
            x"A0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBF" &
            x"C0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDF" &
            x"E0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFE00");
        run_one(
            x"000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F" &
            x"202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F" &
            x"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F" &
            x"606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F" &
            x"808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9F" &
            x"A0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBF" &
            x"C0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDF" &
            x"E0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFE",
            x"01FF0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E" &
            x"1F202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E" &
            x"3F404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E" &
            x"5F606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E" &
            x"7F808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E" &
            x"9FA0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBE" &
            x"BFC0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDE" &
            x"DFE0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFE00");
        run_one(
            x"0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20" &
            x"2122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F40" &
            x"4142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F60" &
            x"6162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F80" &
            x"8182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0" &
            x"A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0" &
            x"C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0" &
            x"E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF",
            x"FF0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F" &
            x"202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F" &
            x"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F" &
            x"606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F" &
            x"808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9F" &
            x"A0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBF" &
            x"C0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDF" &
            x"E0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFE02FF00");
        run_one(
            x"02030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F2021" &
            x"22232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F4041" &
            x"42434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F6061" &
            x"62636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F8081" &
            x"82838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1" &
            x"A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1" &
            x"C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1" &
            x"E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF00",
            x"FF02030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20" &
            x"2122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F40" &
            x"4142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F60" &
            x"6162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F80" &
            x"8182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0" &
            x"A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0" &
            x"C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0" &
            x"E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF010100");
        run_one(
            x"030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F202122" &
            x"232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F404142" &
            x"434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F606162" &
            x"636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F808182" &
            x"838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1A2" &
            x"A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1C2" &
            x"C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1E2" &
            x"E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF0001",
            x"FE030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F2021" &
            x"22232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F4041" &
            x"42434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F6061" &
            x"62636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F8081" &
            x"82838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1" &
            x"A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1" &
            x"C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1" &
            x"E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF020100");
    end procedure;

    -- Run a random 
    procedure run_rand(ri, ro: real; nbytes: positive) is
        -- Generate the input/output vector.
        variable raw : std_logic_vector(8*nbytes-1 downto 0) := rand_bytes(nbytes);
    begin
        -- Set flow-control rate for this test series.
        in_rate     <= ri;
        mid_rate    <= ro;
        -- Run the randomized test.
        run_one(raw, x"");
    end procedure;
begin
    in_rate     <= 0.0;
    mid_rate    <= 0.0;
    test_idx    <= 0;
    in_data     <= (others => 'X');
    in_last     <= '0';
    in_valid    <= '0';
    mid_ready   <= '0';
    mid_ref     <= (others => 'X');
    out_ref     <= (others => 'X');
    wait until falling_edge(reset_p);
    wait for 1 us;

    -- Run the canned sequences.
    run_fixed(1.0, 1.0);
    run_fixed(0.5, 0.5);
    run_fixed(0.1, 0.9);
    run_fixed(0.9, 0.1);

    -- Run a series of randomized sequences.
    for n in 1 to 100 loop
        run_rand(0.5, 0.5, 10*n);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
