--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the parallel CRC block
--
-- This testbench streams traffic with a mixture of fixed and randomly-
-- generated test frames, and confirms that the CRC block calculates
-- the expected frame check sequence (FCS / CRC32).
--
-- The complete test takes less than 0.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity eth_frame_parcrc_tb_single is
    generic (
    IO_BYTES    : positive;         -- Set pipeline width
    PORT_INDEX  : natural := 42);   -- Configuration address
    port (
    test_done   : out std_logic);
end eth_frame_parcrc_tb_single;

architecture single of eth_frame_parcrc_tb_single is

-- System clock and reset
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_write     : std_logic;

-- Reference stream
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_crc      : crc_word_t;
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;

-- Output stream
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_crc      : crc_word_t;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_write    : std_logic;

-- Test control.
constant LOAD_BYTES : positive := IO_BYTES;
signal rate_in      : real := 0.0;
signal load_data    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal load_crc     : crc_word_t := (others => '0');
signal load_nlast   : integer range 0 to LOAD_BYTES := 0;
signal load_wr      : std_logic := '0';
signal test_done_i  : std_logic := '0';

begin

-- Clock and reset generation.
clk100  <= not clk100 after 5 ns;   -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Input and reference queues.
u_ififo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_write        => load_wr,
    out_clk         => clk100,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_valid       => in_write,
    out_ready       => '1',
    out_rate        => rate_in,
    reset_p         => reset_p);

u_rfifo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => 32)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_meta         => load_crc,
    in_write        => load_wr,
    out_clk         => clk100,
    out_data        => ref_data,
    out_nlast       => ref_nlast,
    out_meta        => ref_crc,
    out_valid       => ref_valid,
    out_ready       => out_write,
    reset_p         => reset_p);

-- Unit under test.
uut : entity work.eth_frame_parcrc
    generic map(IO_BYTES => IO_BYTES)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_data    => out_data,
    out_crc     => out_crc,
    out_nlast   => out_nlast,
    out_write   => out_write,
    clk         => clk100,
    reset_p     => reset_p);

-- Verify outputs.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (out_write = '1' and ref_valid = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
        elsif (out_write = '1') then
            report "Unexpected output data." severity error;
        end if;

        if (out_write = '1' and out_nlast > 0 and ref_valid = '1') then
            assert (out_crc = ref_crc)
                report "CRC mismatch" severity error;
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
    -- Load test data into designated FIFO.
    procedure load(data : std_logic_vector) is
        constant LOAD_BITS : positive := LOAD_BYTES * 8;
        variable brem : integer := data'length;
    begin
        wait until rising_edge(clk100);
        load_crc    <= eth_checksum(data);
        load_wr     <= '1';
        while (brem > 0) loop
            if (brem > LOAD_BITS) then
                load_data   <= data(brem-1 downto brem-LOAD_BITS);
                load_nlast  <= 0;
            else
                load_data   <= data(brem-1 downto 0) & i2s(0, LOAD_BITS-brem);
                load_nlast  <= brem / 8;
            end if;
            wait until rising_edge(clk100);
            brem := brem - LOAD_BITS;
        end loop;
        load_data   <= (others => '0');
        load_nlast  <= 0;
        load_wr     <= '0';
    end procedure;

    -- Start experiment and run until completed.
    procedure wait_done(rate : real) is
        variable idle_count : natural := 0;
    begin
        -- Wait a few clock cycles for all FIFOs to be ready.
        for n in 1 to 10 loop
            wait until rising_edge(clk100);
        end loop;
        -- Start transmission of test data.
        rate_in <= rate;
        -- Wait until N consecutive idle cycles.
        while (idle_count < 100) loop
            wait until rising_edge(clk100);
            if (in_write = '1' or out_write = '1') then
                idle_count := 0;
            else
                idle_count := idle_count + 1;
            end if;
        end loop;
        -- Post-test cleanup.
        assert (ref_valid = '0')
            report "Output too short" severity error;
        rate_in <= 0.0;
    end procedure;

    -- Fixed tests with known CRC values.
    procedure test_fixed(rate : real) is
        -- Define a few simplified tests with byte-symmetric inputs:
        -- (This makes it easier to isolate flipped bit-order problems.)
        variable PKT0a : std_logic_vector(7 downto 0) := x"18";
        variable PKT0b : std_logic_vector(7 downto 0) := x"A5";
        variable PKT0c : std_logic_vector(15 downto 0) := x"18A5";
        -- Note: Using "variable" rather than "constant" as workaround for XSIM bugs.

        -- Define some known-good reference Ethernet frames:
        -- https://www.cl.cam.ac.uk/research/srg/han/ACS-P35/ethercrc/
        variable PKT1 : std_logic_vector(479 downto 0) :=
            x"FFFFFFFFFFFF0020AFB780B8080600010800060400010020" &
            x"AFB780B880E80F9400000000000080E80FDEDEDEDEDEDEDE" &
            x"DEDEDEDEDEDEDEDEDEDEDEDE";
        variable REF1 : crc_word_t := x"9ED2C2AF";

        -- https://electronics.stackexchange.com/questions/170612/fcs-verification-of-ethernet-frame
        variable PKT2 : std_logic_vector(479 downto 0) :=
            x"FFFFFFFFFFFF00000004141308004500002E000000004011" &
            x"7AC000000000FFFFFFFF000050DA00120000424242424242" &
            x"424242424242424242424242";
        variable REF2 : crc_word_t := x"9BF6D0FD";
    begin
        load(PKT0a);    -- Load each of the byte-symmetric tests.
        load(PKT0b);
        load(PKT0c);
        wait_done(rate);

        load(PKT1);     -- Load each of the reference tests.
        assert (load_crc = REF1) report "REF1 mismatch!" severity error;
        load(PKT2);
        assert (load_crc = REF2) report "REF2 mismatch!" severity error;
        wait_done(rate);
    end procedure;

    -- Randomly generated data of various lengths.
    procedure test_random(rate : real) is
    begin
        for n in 1 to 32 loop
            load(rand_bytes(n));
        end loop;
        load(rand_bytes(256));
        wait_done(rate);

        for n in 1 to 10 loop
            load(rand_bytes(123));
            load(rand_bytes(234));
            wait_done(rate);
        end loop;
    end procedure;

    -- Full test sequence
    procedure test_all(rate : real) is
    begin
        test_fixed(rate);
        test_random(rate);
    end procedure;
begin
    wait for 2 us;

    -- Run test sequence at various rates.
    test_all(1.0);
    test_all(0.5);
    test_all(0.2);

    report "Test completed, IO_BYTES = " & integer'image(IO_BYTES);
    test_done_i <= '1';
    wait;
end process;

test_done <= test_done_i;

end single;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity eth_frame_parcrc_tb is
    -- Testbench has no top-level I/O.
end eth_frame_parcrc_tb;

architecture tb of eth_frame_parcrc_tb is

-- Note: Default here only matters if we comment out some of the test blocks.
signal test_done : std_logic_vector(0 to 6) := (others => '1');

begin

uut1 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 1)
    port map(test_done => test_done(0));
uut2 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 2)
    port map(test_done => test_done(1));
uut3 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 3)
    port map(test_done => test_done(2));
uut5 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 5)
    port map(test_done => test_done(3));
uut8 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 8)
    port map(test_done => test_done(4));
uut13 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 13)
    port map(test_done => test_done(5));
uut16 : entity work.eth_frame_parcrc_tb_single
    generic map(IO_BYTES => 16)
    port map(test_done => test_done(6));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
