--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SLIP-Decoder Testbench
--
-- This is a unit test for the SLIP-decoder block.  It uses a series
-- of canned input/output pairs to evaluate nominal cases as well as
-- certain error conditions.  Additional coverage is provided in the
-- SLIP-Encoder unit test.
--
-- The complete test takes less than 0.02 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.uniform;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;

entity slip_decoder_tb is
    -- Testbench --> No I/O ports
end slip_decoder_tb;

architecture tb of slip_decoder_tb is

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal in_rate      : real := 0.0;
signal test_idx     : integer := 0;

signal in_data      : byte_t := (others => '0');
signal in_write     : std_logic := '0';
signal out_data     : byte_t;
signal out_ref      : byte_t := (others => '0');
signal out_write    : std_logic;
signal out_last     : std_logic;
signal decode_err   : std_logic;


begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Unit under test
uut : entity work.slip_decoder
    port map(
    in_data    => in_data,
    in_write   => in_write,
    out_data   => out_data,
    out_write  => out_write,
    out_last   => out_last,
    decode_err => decode_err,
    reset_p    => reset_p,
    refclk     => clk);

-- Test sequence generation
p_test : process
    -- PRNG for flow control
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;

    -- Internal test state.
    -- (Note: ModelSim can't debug variables inside a process.)
    variable timeout, in_len, in_ptr, out_len, out_ptr : integer := 0;

    -- Run a procedure with known input and output.
    procedure run_one(constant rate:real; istr,ostr:std_logic_vector) is
        variable got_err : std_logic := '0';

        function get_byte(str:std_logic_vector; bidx:integer) return byte_t is
            variable result : byte_t := (others => '0');
        begin
            -- Note: Default for hard-coded std_logic_vector is (0 to N-1).
            -- Extract the requested byte and convert to (7 downto 0)
            for n in 0 to 7 loop
                result(7-n) := str(8*bidx+n);
            end loop;
            return result;
        end function;
    begin
        -- Report start of new test.
        report "Starting test #" & integer'image(test_idx + 1);
        test_idx <= test_idx + 1;
        in_rate  <= rate;
        in_write <= '0';
        in_data  <= (others => '0');
        out_ref  <= (others => '0');
        wait for 100 ns;

        -- Write input as we read output.  Stop once idle.
        timeout := 0;
        in_ptr  := 0;
        out_ptr := 0;
        in_len  := istr'length / 8; -- Length in bytes (round down)
        out_len := ostr'length / 8;
        while (timeout < 30) loop
            -- Flow control randomization for input.
            uniform(seed1, seed2, rand);
            if ((in_ptr < in_len) and (rand < in_rate)) then
                in_data  <= get_byte(istr, in_ptr);
                in_write <= '1';
                in_ptr   := in_ptr + 1;
            else
                in_write <= '0';
            end if;

            -- Check the output stream.
            if (out_write = '0') then
                null;
            elsif (out_ptr < out_len) then
                -- Check the next output word against reference.
                assert (out_data = out_ref)
                    report "Output data mismatch" severity error;
                out_ptr := out_ptr + 1;
                -- Check the "last" strobe.
                if (out_ptr = out_len) then
                    assert (out_last = '1')
                        report "Missing LAST strobe" severity error;
                else
                    assert (out_last = '0')
                        report "Unexpected LAST strobe" severity error;
                end if;
            elsif (out_len > 0) then
                -- For valid frames, data-after-EOF is an error.
                report "Unexpected output data" severity error;
            end if;

            -- Update the timeout counter and persistent error flag.
            if (out_write = '1') then
                timeout := 0;
            else
                timeout := timeout + 1;
            end if;

            if (decode_err = '1') then
                got_err := '1';
            end if;

            -- Drive the next output reference value.
            if (out_ptr < out_len) then
                out_ref <= get_byte(ostr, out_ptr);
            else
                out_ref <= (others => '0');
            end if;

            -- Ready for next clock cycle.
            wait until rising_edge(clk);
        end loop;

        -- Confirm we received the entire expected frame.
        if (out_len > 0) then
            assert (out_ptr = out_len)
                report "Missing frame data" severity error;
            assert (got_err = '0')
                report "Unexpected decoder-error strobe" severity error;
        else
            assert (got_err = '1')
                report "Missing decoder-error strobe" severity error;
        end if;
    end procedure;
begin
    -- Global reset.
    reset_p <= '1';
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    -- Test nominal cases with escape characters in various positions.
    run_one(0.2, x"C0DEADBEEFC0",   x"DEADBEEF");   -- No escape characters
    run_one(0.3, x"C0DBDCADBEEFC0", x"C0ADBEEF");   -- Escaped EOF (0xC0 -> 0xDBDC)
    run_one(0.4, x"C0DEDBDCBEEFC0", x"DEC0BEEF");
    run_one(0.5, x"C0DEADDBDCEFC0", x"DEADC0EF");
    run_one(0.6, x"C0DEADBEDBDCC0", x"DEADBEC0");
    run_one(0.7, x"C0DBDDADBEEFC0", x"DBADBEEF");   -- Escaped ESC (0xDB -> 0xDBDD)
    run_one(0.8, x"C0DEDBDDBEEFC0", x"DEDBBEEF");
    run_one(0.9, x"C0DEADDBDDEFC0", x"DEADDBEF");
    run_one(1.0, x"C0DEADBEDBDDC0", x"DEADBEDB");

    -- Confirm error strobe for invalid escape characters.
    run_one(0.8, x"C0DBADBEEFC0", x"");
    run_one(0.8, x"C0DEDBBEEFC0", x"");
    run_one(0.8, x"C0DEADDBEFC0", x"");
    run_one(0.8, x"C0DEADBEDBC0", x"");

    -- A few more tests with longer random data.
    run_one(0.8, x"C0" &
        x"DFAB1A90720C7C36B3E1B8586C67B2ED" &
        x"DCAE1BF63B3B414B23E834242760A235" &
        x"F2E04101C8E6F22C5C81001F816A8F8A" &
        x"5B16522FF66CA39D161A687455AA372B" &
        x"EEA1B87AB64B78FD5E4972A5D8BAF5FA" &
        x"788D7D1AF8A8CCAA5D478329FC57460CC0",
        x"DFAB1A90720C7C36B3E1B8586C67B2ED" &
        x"DCAE1BF63B3B414B23E834242760A235" &
        x"F2E04101C8E6F22C5C81001F816A8F8A" &
        x"5B16522FF66CA39D161A687455AA372B" &
        x"EEA1B87AB64B78FD5E4972A5D8BAF5FA" &
        x"788D7D1AF8A8CCAA5D478329FC57460C");
    run_one(0.8, x"C0" &
        x"3778AEA62D801941A8FABA081D91BA4F" &
        x"63A7988AFB77F64381171F688A99C431" &
        x"2DC9E29BFCF81BAC4141DFCC0194D613" &
        x"E2A7983A66BD14B0C5BCB9C1AEA32155" &
        x"89A42B9F9C392D3D3D089C2E2C5A2073" &
        x"34BE04C9B91A3AE5EC005BE242EF56CAC0",
        x"3778AEA62D801941A8FABA081D91BA4F" &
        x"63A7988AFB77F64381171F688A99C431" &
        x"2DC9E29BFCF81BAC4141DFCC0194D613" &
        x"E2A7983A66BD14B0C5BCB9C1AEA32155" &
        x"89A42B9F9C392D3D3D089C2E2C5A2073" &
        x"34BE04C9B91A3AE5EC005BE242EF56CA");

    -- Done.
    report "All tests completed.";
    wait;
end process;

end tb;
