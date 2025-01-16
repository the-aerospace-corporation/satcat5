--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Synchronous packet metadata FIFO
--
-- This test operates the "fifo_pktmeta" block under a variety of
-- flow-control conditions, including sudden transitions between
-- minimum-length and maximum-length packets. Tests are run in
-- parallel for various build-time configurations.
--
-- The complete test takes 2.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.rand_int;

entity fifo_pktmeta_tb_helper is
    generic (
    IO_BYTES    : positive;
    TEST_ITER   : positive);
end fifo_pktmeta_tb_helper;

architecture helper of fifo_pktmeta_tb_helper is

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- FIFO for packet-length control (input, reference).
signal in_pktlen    : std_logic_vector(15 downto 0);
signal in_pktvalid  : std_logic;
signal in_pktready  : std_logic;
signal ref_pktlen   : std_logic_vector(15 downto 0);
signal ref_pktvalid : std_logic;
signal ref_pktready : std_logic;

-- Generate the input and reference streams.
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_meta      : unsigned(7 downto 0) := (others => '0');
signal in_nlast     : integer range 0 to IO_BYTES := 0;
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal ref_meta     : unsigned(7 downto 0) := (others => '0');
signal ref_nlast    : integer range 0 to IO_BYTES := 0;
signal ref_valid    : std_logic := '0';
signal ref_next     : std_logic;

-- Output stream from unit under test.
signal uut_error    : std_logic;
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_meta     : std_logic_vector(7 downto 0);
signal out_pktlen   : unsigned(15 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';

-- High-level test control.
signal test_index   : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;
signal test_pktlen  : unsigned(15 downto 0) := (others => '0');
signal test_pktwr   : std_logic := '0';

begin

-- Clock generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- FIFO for packet-length control (input, reference).
in_pktready  <=  in_valid and  in_ready and bool2bit( in_nlast > 0);
ref_pktready <= out_valid and out_ready and bool2bit(out_nlast > 0);
ref_next     <= out_valid and out_ready;

u_fifo_in : entity work.fifo_large_sync
    generic map(
    FIFO_DEPTH  => 1024,
    FIFO_WIDTH  => 16)
    port map(
    in_data     => std_logic_vector(test_pktlen),
    in_write    => test_pktwr,
    out_data    => in_pktlen,
    out_valid   => in_pktvalid,
    out_ready   => in_pktready,
    clk         => clk,
    reset_p     => reset_p);

u_fifo_ref : entity work.fifo_large_sync
    generic map(
    FIFO_DEPTH  => 1024,
    FIFO_WIDTH  => 16)
    port map(
    in_data     => std_logic_vector(test_pktlen),
    in_write    => test_pktwr,
    out_data    => ref_pktlen,
    out_valid   => ref_pktvalid,
    out_ready   => ref_pktready,
    clk         => clk,
    reset_p     => reset_p);

-- Generate the input and refernece streams.
p_gen : process(clk)
    variable iseed1, rseed1, fseed1 : positive := 1234;
    variable iseed2, rseed2, fseed2 : positive := 5678;
    variable in_bcount, ref_bcount : natural := 0;
    variable rand : real;
    variable in_vreq : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Flow-control randomization.
        uniform(fseed1, fseed2, rand);
        in_vreq := in_pktvalid and bool2bit(rand < test_rate_i);
        uniform(fseed1, fseed2, rand);
        out_ready <= bool2bit(rand < test_rate_o);

        -- PRNG for the input stream.
        if (reset_p = '1') then
            in_data     <= (others => 'X');
            in_nlast    <= 0;
            in_valid    <= '0';
            in_bcount   := 0;
        elsif ((in_vreq = '1') and (in_valid = '0' or in_ready = '1')) then
            in_valid    <= '1';
            for n in in_data'range loop
                uniform(iseed1, iseed2, rand);
                in_data(n) <= bool2bit(rand < 0.5);
            end loop;
            if (in_bcount + IO_BYTES < u2i(in_pktlen)) then
                in_nlast  <= 0;     -- Continue current frame
                in_bcount := in_bcount + IO_BYTES;
            else
                in_nlast  <= u2i(in_pktlen) - in_bcount;
                in_bcount := 0;     -- End of frame / start of next
            end if;
        elsif (in_ready = '1') then
            in_data     <= (others => 'X');
            in_nlast    <= 0;
            in_valid    <= '0';
        end if;

        -- PRNG for the reference stream.
        if (reset_p = '1') then
            ref_data    <= (others => 'X');
            ref_nlast   <= 0;
            ref_valid   <= '0';
            ref_bcount  := 0;
        elsif ((ref_pktvalid = '1') and (ref_valid = '0' or ref_next = '1')) then
            ref_valid   <= '1';
            for n in in_data'range loop
                uniform(rseed1, rseed2, rand);
                ref_data(n) <= bool2bit(rand < 0.5);
            end loop;
            if (ref_bcount + IO_BYTES < u2i(ref_pktlen)) then
                ref_nlast  <= 0;    -- Continue current frame
                ref_bcount := ref_bcount + IO_BYTES;
            else
                ref_nlast  <= u2i(ref_pktlen) - ref_bcount;
                ref_bcount := 0;    -- End of frame / start of next
            end if;
        elsif (ref_next = '1') then
            ref_data    <= (others => 'X');
            ref_nlast   <= 0;
            ref_valid   <= '0';
        end if;

        -- Packet metadata is a simple counter.
        if (reset_p = '1') then
            in_meta <= (others => '0');
        elsif (in_valid = '1' and in_ready = '1' and in_nlast > 0) then
            in_meta <= in_meta + 1;
        end if;

        if (reset_p = '1') then
            ref_meta <= (others => '0');
        elsif (out_valid = '1' and out_ready = '1' and out_nlast > 0) then
            ref_meta <= ref_meta + 1;
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.fifo_pktmeta
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => in_meta'length)
    port map(
    in_data     => in_data,
    in_meta     => std_logic_vector(in_meta),
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    in_error    => uut_error,
    out_data    => out_data,
    out_meta    => out_meta,
    out_pktlen  => out_pktlen,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Check the output stream.
p_check : process(clk)
begin
    if rising_edge(clk) then
        assert (uut_error = '0')
            report "Internal overflow." severity error;

        if (out_valid = '1' and out_ready = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch." severity error;
            assert (unsigned(out_meta) = ref_meta)
                report "META mismatch." severity error;
            assert (out_pktlen = unsigned(ref_pktlen))
                report "PKTLEN mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Load a packet length into the two control FIFOs.
    procedure load_len(nbytes: positive) is
    begin
        test_pktlen <= to_unsigned(nbytes, 16);
        test_pktwr  <= '1';
        wait until rising_edge(clk);
        test_pktwr  <= '0';
    end procedure;

    -- Run a full test sequence with the given flow conditions.
    procedure run_seq(ri, ro: real) is
        variable timeout : integer := 2000;
    begin
        -- Set test conditions.
        test_index  <= test_index + 1;
        test_rate_i <= ri;
        test_rate_o <= ro;
        -- Test a series of random lengths.
        for n in 1 to TEST_ITER loop
            load_len(64 + rand_int(1500));
        end loop;
        -- Test a sandwich of min and max length packets.
        load_len(1500);
        for n in 1 to 32 loop
            load_len(64);
        end loop;
        load_len(1500);
        -- Run the test until the sequence is completed or timeout.
        while (ref_pktvalid = '1' and timeout > 0) loop
            wait until rising_edge(clk);
            if (in_ready = '1' or out_valid = '1') then
                timeout := 2000;
            else
                timeout := timeout - 1;
            end if;
        end loop;
        assert (ref_pktvalid = '0' and timeout > 0)
            report "Timeout waiting for output data." severity error;
    end procedure;
begin
    reset_p <= '1';
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    run_seq(1.0, 1.0);
    run_seq(0.3, 0.7);
    run_seq(0.7, 0.3);

    report "All tests completed!";
    wait;
end process;

end helper;


--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_pktmeta_tb is
    -- Testbench --> No I/O ports
end fifo_pktmeta_tb;

architecture tb of fifo_pktmeta_tb is

begin

-- Instantiate test units in various configurations.
test0 : entity work.fifo_pktmeta_tb_helper
    generic map(IO_BYTES => 1, TEST_ITER => 40);
test1 : entity work.fifo_pktmeta_tb_helper
    generic map(IO_BYTES => 3, TEST_ITER => 125);
test2 : entity work.fifo_pktmeta_tb_helper
    generic map(IO_BYTES => 8, TEST_ITER => 300);

end tb;
