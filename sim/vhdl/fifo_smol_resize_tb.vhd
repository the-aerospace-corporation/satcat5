--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Word-resizing FIFO Testbench
--
-- This unit test covers both nominal and off-nominal conditions for the
-- word-resizing FIFO.  The test includes preset and randomized sequences
-- with various options for randomized flow control.  Tests are run in
-- parallel for various generic configurations.
--
-- The complete test takes just under 0.2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity fifo_smol_resize_tb_helper is
    generic (
    IN_BYTES    : integer;          -- Input word size
    OUT_BYTES   : integer;          -- Output word size
    DEPTH_LOG2  : integer;          -- FIFO depth = 2^N
    VERBOSE     : boolean);         -- Extra debug messages?
    port (
    clk         : in  std_logic);   -- Common clock
end fifo_smol_resize_tb_helper;

architecture helper of fifo_smol_resize_tb_helper is

-- Input, reference, and output streams
signal in_data      : std_logic_vector(8*IN_BYTES-1 downto 0) := (others => '0');
signal in_nlast     : integer range 0 to IN_BYTES := 0;
signal in_write     : std_logic := '0';
signal in_wait      : std_logic;
signal ref_data     : std_logic_vector(8*OUT_BYTES-1 downto 0) := (others => '0');
signal ref_mask     : std_logic_vector(8*OUT_BYTES-1 downto 0) := (others => '0');
signal ref_nlast    : integer range 0 to OUT_BYTES := 0;
signal ref_valid    : std_logic := '0';
signal out_data     : std_logic_vector(8*OUT_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to OUT_BYTES;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_read     : std_logic := '0';
signal out_next     : std_logic;

-- FIFO status signals (and sticky equivalents)
signal fifo_full    : std_logic;
signal fifo_empty   : std_logic;
signal fifo_hfull   : std_logic;
signal fifo_hempty  : std_logic;
signal fifo_error   : std_logic;
signal sticky_error : std_logic := '0';

-- High-level test control
signal reset_p      : std_logic := '1';
signal test_index   : natural := 0; -- Increment before each test
signal test_frmlen  : natural := 0; -- 0 = Random, 1+ = N bytes
signal in_rate      : real := 0.0;
signal in_count     : natural := 0; -- Bytes sent
signal in_request   : natural := 0; -- Send exactly N bytes
signal in_limit     : std_logic := '0';
signal out_rate     : real := 0.0;
signal out_count    : natural := 0; -- Bytes received
signal out_request  : natural := 0; -- Read exactly N bytes

begin

-- Input stream generation and flow randomization.
in_wait  <= reset_p or (in_limit and fifo_hfull);
out_next <= out_valid and out_read;

p_gen : process(clk)
    variable seed1i, seed1r, seed1f : positive := 8679109;
    variable seed2i, seed2r, seed2f : positive := 5871025;
    variable req_i, req_r : natural := 0;   -- Remaining bytes total
    variable frm_i, frm_r : natural := 0;   -- Remaining bytes in frame
    variable rand : real;
    variable temp_data, temp_mask : std_logic_vector(7 downto 0);
begin
    if rising_edge(clk) then
        -- Start a new input frame?
        if (reset_p = '1') then
            req_i   := in_request;
            frm_i   := 0;       -- No active frame
        elsif (frm_i = 0 and in_count < in_request) then
            -- Random or fixed-length frames?
            if (test_frmlen = 0) then
                uniform(seed1i, seed2i, rand);
                frm_i := 1 + integer(floor(64.0 * rand));
            else
                frm_i := test_frmlen;
            end if;
            -- Never exceed the requested total length.
            frm_i := int_min(req_i, frm_i);
            req_i := req_i - frm_i;
        end if;

        -- Start a new reference frame?
        if (reset_p = '1') then
            seed1r  := seed1i;  -- Resync input & reference
            seed2r  := seed2i;
            req_r   := in_request;
            frm_r   := 0;       -- No active frame
        elsif (frm_r = 0 and out_count < in_request) then
            -- Random or fixed-length frames?
            if (test_frmlen = 0) then
                uniform(seed1r, seed2r, rand);
                frm_r := 1 + integer(floor(64.0 * rand));
            else
                frm_r := test_frmlen;
            end if;
            -- Never exceed the requested total length.
            frm_r := int_min(req_r, frm_r);
            req_r := req_r - frm_r;
        end if;

        -- Generate new input data?
        uniform(seed1f, seed2f, rand);
        if (in_wait = '0' and frm_i > 0 and rand < in_rate) then
            in_write <= '1';
            if (frm_i > IN_BYTES) then
                in_nlast <= 0;      -- Frame continues...
            else
                in_nlast <= frm_i;  -- End of frame at Nth byte
            end if;
            for n in IN_BYTES-1 downto 0 loop
                if (frm_i > 0) then
                    uniform(seed1i, seed2i, rand);
                    temp_data   := i2s(integer(floor(rand * 256.0)), 8);
                    frm_i       := frm_i - 1;
                else
                    temp_data   := (others => '0');
                end if;
                in_data(8*n+7 downto 8*n) <= temp_data;
            end loop;
        else
            in_data     <= (others => '0');
            in_nlast    <= 0;
            in_write    <= '0';
        end if;

        -- Generate new reference data?
        uniform(seed1f, seed2f, rand);
        if (reset_p = '1') then
            ref_data    <= (others => '0');
            ref_mask    <= (others => '0');
            ref_nlast   <= 0;
            ref_valid   <= '0';
        elsif (ref_valid = '0' or out_next = '1') then
            if (frm_r > OUT_BYTES) then
                ref_valid   <= '1'; -- Frame continues...
                ref_nlast   <= 0;
            elsif (frm_r > 0) then
                ref_valid   <= '1'; -- End of frame at Nth byte
                ref_nlast   <= frm_r;
            else
                ref_valid   <= '0'; -- Revert to idle
                ref_nlast   <= 0;
            end if;
            for n in OUT_BYTES-1 downto 0 loop
                if (frm_r > 0) then
                    uniform(seed1r, seed2r, rand);
                    temp_data   := i2s(integer(floor(rand * 256.0)), 8);
                    temp_mask   := (others => '1');
                    frm_r       := frm_r - 1;
                else
                    temp_data   := (others => '0');
                    temp_mask   := (others => '0');
                end if;
                ref_data(8*n+7 downto 8*n) <= temp_data;
                ref_mask(8*n+7 downto 8*n) <= temp_mask;
            end loop;
        end if;

        -- Flow-control randomization for output.
        uniform(seed1f, seed2f, rand);
        out_read <= bool2bit(rand < out_rate and out_request > 0);
    end if;
end process;

-- Unit under test.
uut : entity work.fifo_smol_resize
    generic map(
    IN_BYTES    => IN_BYTES,
    OUT_BYTES   => OUT_BYTES,
    DEPTH_LOG2  => DEPTH_LOG2,
    ERROR_UNDER => false,   -- Ignore underflow (default)
    ERROR_OVER  => true,    -- Treat overflow as error
    ERROR_PRINT => false)   -- Suppress overflow warnings
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_last    => out_last,
    out_valid   => out_valid,
    out_read    => out_read,
    fifo_full   => fifo_full,
    fifo_empty  => fifo_empty,
    fifo_hfull  => fifo_hfull,
    fifo_hempty => fifo_hempty,
    fifo_error  => fifo_error,
    clk         => clk,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk)
begin
    if rising_edge(clk) then
        -- Check data against reference.
        if (reset_p = '0' and out_valid = '1' and out_read = '1' and sticky_error = '0') then
            assert ((out_data and ref_mask) = ref_data)
                report "out_data mismatch" severity error;
            assert (out_nlast = ref_nlast)
                report "out_nlast mismatch" severity error;
            assert (out_last = bool2bit(ref_nlast > 0))
                report "out_last mismatch" severity error;
        end if;

        -- Sanity-check on status flags.
        assert (fifo_full and fifo_empty) = '0'
            report "Full+empty" severity error;
        assert (fifo_hfull = not fifo_hempty)
            report "Hfull mismatch" severity error;

        -- Count input and output length.
        if (reset_p = '1') then
            in_count <= 0;                      -- Start of new test
        elsif (in_write = '1' and in_nlast = 0) then
            in_count <= in_count + IN_BYTES;    -- Continue frame
        elsif (in_write = '1') then
            in_count <= in_count + in_nlast;    -- End of frame
        end if;

        if (reset_p = '1') then
            out_count <= 0;                     -- Start of new test
        elsif (out_next = '1' and out_nlast = 0) then
            out_count <= out_count + OUT_BYTES; -- Continue frame
        elsif (out_next = '1') then
            out_count <= out_count + out_nlast; -- End of frame
        end if;

        -- Make the error flag sticky.
        -- (Overflow means we'll be out-of-sync for remainder of test.)
        if (reset_p = '1') then
            sticky_error <= '0';
        elsif (fifo_error = '1') then
            sticky_error <= '1';
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    constant FIFO_BYTES : positive := int_lcm(IN_BYTES, OUT_BYTES);

    -- Calculate the effective FIFO capacity, given frame size.
    function nbytes_max(nf : natural) return natural is
        constant num_words_pkt : natural := (nf + FIFO_BYTES - 1) / FIFO_BYTES;
        variable num_words_max : natural := 2**DEPTH_LOG2;
        variable num_frames, num_words_rem : natural;
    begin
        -- Shortcut for random frames:
        if (nf = 0) then
            return 0;
        end if;
        -- +1 effective capacity if there is an output buffer and
        -- it is large enough to fit the entire frame.
        if (OUT_BYTES < FIFO_BYTES and nf <= OUT_BYTES) then
            num_words_max := num_words_max + 1;
        end if;
        -- Number of full-size frames?  How many leftover words?
        num_frames    := num_words_max / num_words_pkt;
        num_words_rem := num_words_max - num_frames * num_words_pkt;
        -- If needed, add a smaller frame to get exactly num_words_max.
        return num_frames * nf + num_words_rem * FIFO_BYTES;
    end function;

    -- Run a single test from start to finish.
    procedure test_run(nf, ni, no : natural) is
        constant nmax : natural := nbytes_max(nf);
    begin
        -- Set test conditions.
        if (VERBOSE) then
            report "Starting test #" & integer'image(test_index + 1);
        end if;
        test_index  <= test_index + 1;
        in_request  <= ni;  -- Total bytes to write
        out_request <= no;  -- Total bytes to read
        test_frmlen <= nf;  -- Size of each frame (0 = random)

        -- Briefly assert reset.
        reset_p     <= '1';
        wait until rising_edge(clk);
        reset_p     <= '0';
        wait until rising_edge(clk);

        -- Wait until we're done, then a little extra.
        while (in_count < in_request or out_count < out_request) loop
            wait until rising_edge(clk);
        end loop;
        for n in 1 to 50 loop
            wait until rising_edge(clk);
        end loop;

        -- Check all status flags given expected FIFO capacity.
        if (nmax > 0) then
            assert (fifo_full = bool2bit(ni - no >= nmax))
                report "Flag mismatch: Full" severity error;
            assert (fifo_empty = bool2bit(ni = no))
                report "Flag mismatch: Empty" severity error;
            assert (fifo_hfull = bool2bit(ni - no >= nmax/2))
                report "Flag mismatch: Half-full" severity error;
            assert (sticky_error = bool2bit(ni - no > nmax))
                report "Flag mismatch: Error" severity error;
        end if;
    end procedure;

    -- Run complete test sequence at specified flow-control rates.
    procedure test_seq(ri, ro : real) is
        constant nm1 : positive := nbytes_max(1);
        constant nm7 : positive := nbytes_max(7);
    begin
        -- Set flow-control conditions.
        -- (Early tests all ignore input flow control flags.)
        in_rate     <= ri;
        out_rate    <= ro;
        in_limit    <= '0';

        -- Basic test with just a few bytes.
        test_run(1, 10, 10);

        -- Write a series of single-byte frames.
        -- (Write data but don't read it, so we can check flags.)
        test_run(1, 1, 0);            -- Single byte
        test_run(1, (nm1*1)/4, 0);    -- 1/4 full
        test_run(1, (nm1*3)/4, 0);    -- 3/4 full
        test_run(1, nm1, 0);          -- Exactly full
        test_run(1, nm1+1, 0);        -- Overflow

        -- Same tests but with slightly longer frames.
        test_run(7, 7, 0);            -- One frame
        test_run(7, (nm7*1)/4, 0);    -- 1/4 full
        test_run(7, (nm7*3)/4, 0);    -- 3/4 full
        test_run(7, nm7, 0);          -- Exactly full
        test_run(7, nm7+1, 0);        -- Overflow

        -- Free-flowing test with randomized frame sizes.
        in_limit <= '1';              -- Automatic overflow prevention
        test_run(0, 1000, 1000);      -- Read/write 1000 bytes total
    end procedure;
begin
    test_seq(0.1, 0.9);
    test_seq(0.5, 0.5);
    test_seq(0.9, 0.1);
    report "All tests completed!";
    wait;
end process;

end helper;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_smol_resize_tb is
    -- Testbench --> No I/O ports
end fifo_smol_resize_tb;

architecture tb of fifo_smol_resize_tb is

component fifo_smol_resize_tb_helper is
    generic (
    IN_BYTES    : integer;          -- Input word size
    OUT_BYTES   : integer;          -- Output word size
    DEPTH_LOG2  : integer;          -- FIFO depth = 2^N
    VERBOSE     : boolean);         -- Extra debug messages?
    port (
    clk         : in  std_logic);   -- Common clock
end component;

constant VERBOSE : boolean := false;

signal clk : std_logic := '0';

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Instantiate test units in various configurations.
test0 : fifo_smol_resize_tb_helper
    generic map(
    IN_BYTES    => 1,
    OUT_BYTES   => 4,
    DEPTH_LOG2  => 4,
    VERBOSE     => VERBOSE)
    port map(clk => clk);

test1 : fifo_smol_resize_tb_helper
    generic map(
    IN_BYTES    => 4,
    OUT_BYTES   => 1,
    DEPTH_LOG2  => 4,
    VERBOSE     => VERBOSE)
    port map(clk => clk);

test2 : fifo_smol_resize_tb_helper
    generic map(
    IN_BYTES    => 2,
    OUT_BYTES   => 3,
    DEPTH_LOG2  => 4,
    VERBOSE     => VERBOSE)
    port map(clk => clk);

end tb;
