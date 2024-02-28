--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for auxiliary packet injector
--
-- This is a unit test for the packet injector, verifying that error strobes
-- are fired when inputs misbehave, and verifying that packets remain atomic
-- under all other conditions.  Tests are repeated under a variety of flow
-- control conditions for the primary input.
--
-- The complete test takes 14.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity packet_inject_tb is
    generic (
    AUX_COUNT       : integer := 2;
    MAX_AUX_BYTES   : integer := 14);
    -- No I/O ports
end packet_inject_tb;

architecture tb of packet_inject_tb is

-- Convert byte to stream index (see discussion under p_input)
function get_stream(x : byte_t) return integer is
    variable tmp : std_logic := xor_reduce(x);
begin
    if (tmp = 'X' or tmp = 'U') then
        return 0;   -- Handle metavalue edge case
    else
        return to_integer(unsigned(x(7 downto 4)));
    end if;
end function;

-- System clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '0';

-- Primary input port (no flow control)
signal pri_data     : byte_t := (others => '0');
signal pri_last     : std_logic := '0';
signal pri_write    : std_logic := '0';

-- Auxiliary input ports (valid/ready flow control)
signal aux_data     : byte_array_t(AUX_COUNT downto 1) := (others => (others => '0'));
signal aux_last     : std_logic_vector(AUX_COUNT downto 1) := (others => '0');
signal aux_valid    : std_logic_vector(AUX_COUNT downto 1) := (others => '0');
signal aux_ready    : std_logic_vector(AUX_COUNT downto 1);
signal aux_error    : std_logic;

-- Combined input vector
signal in_data      : byte_array_t(7 downto 0) := (others => (others => '0'));
signal in_last      : std_logic_vector(AUX_COUNT downto 0) := (others => '0');
signal in_valid     : std_logic_vector(AUX_COUNT downto 0) := (others => '0');
signal in_ready     : std_logic_vector(AUX_COUNT downto 0);

-- Combined output port
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_pause    : std_logic := '0';
signal aux_errct    : integer := 0;

-- FIFOs for each data stream.
signal fifo_in_data : byte_array_t(AUX_COUNT downto 0);
signal fifo_in_last : std_logic_vector(AUX_COUNT downto 0);
signal ref_data     : byte_array_t(AUX_COUNT downto 0);
signal ref_last     : std_logic_vector(AUX_COUNT downto 0);
signal fifo_wr      : std_logic_vector(AUX_COUNT downto 0);
signal fifo_rd      : std_logic_vector(AUX_COUNT downto 0);

-- High-level test control
signal test_idx     : integer := 0;
signal test_long    : std_logic := '0';
signal rate_pri     : real := 0.0;  -- Average primary duty cycle (must be < 1.0)
signal rate_aux     : real := 0.0;  -- On average, initiate packet every X clocks
signal rate_out     : real := 0.0;  -- Average output duty cycle
signal rate_pause   : real := 0.0;  -- Probability of 20-cycle pause

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Generate each input stream.
-- MSBs always indicate the stream index, LSBs are random data.
p_input : process(clk_100)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;

    -- Generate the next random byte for a given stream.
    impure function rand_byte(strm_id : integer) return byte_t is
        variable rand_i : integer range 0 to 15;
        variable result : byte_t;
    begin
        uniform(seed1, seed2, rand);
        rand_i := integer(floor(rand * 16.0));
        result := i2s(strm_id, 4) & i2s(rand_i, 4);
        return result;
    end function;

    -- Track FIFO state to avoid overflow.
    variable fifo_ct : natural := 0;

    -- Track remaining bytes in each auxiliary frame.
    type rem_bytes_t is array(1 to AUX_COUNT) of integer;
    variable rem_bytes : rem_bytes_t := (others => 0);

    -- Pause should never last more than 20 cycles.
    variable rem_pause : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Track words in FIFO.
        if (reset_p = '1') then
            fifo_ct := 0;
        elsif (pri_write = '1' and (in_valid(0) = '0' or in_ready(0) = '0')) then
            fifo_ct := fifo_ct + 1;
        elsif (pri_write = '0' and in_valid(0) = '1' and in_ready(0) = '1') then
            fifo_ct := fifo_ct - 1;
        end if;

        -- Sanity-check that the required FIFO depth matches documentation.
        -- (Note: This only applies if output is never bottlenecked.)
        if (rate_out >= 1.0 and rate_pause = 0.0) then
            assert (fifo_ct < MAX_AUX_BYTES + 3)
                report "FIFO depth = " & integer'image(fifo_ct) severity warning;
        end if;

        -- Generate each new primary data word.
        uniform(seed1, seed2, rand);
        if (reset_p = '0' and rand < rate_pri and fifo_ct < 2*MAX_AUX_BYTES) then
            pri_data  <= rand_byte(0);
            pri_write <= '1';
            uniform(seed1, seed2, rand);
            pri_last  <= bool2bit(rand < 0.05);
        else
            pri_data  <= (others => '0');
            pri_write <= '0';
            pri_last  <= '0';
        end if;

        -- Generate data for each auxiliary stream.
        for n in 1 to AUX_COUNT loop
            -- Should we start a new packet this cycle?
            uniform(seed1, seed2, rand);
            if (reset_p = '1') then
                rem_bytes(n) := 0;
            elsif (rem_bytes(n) = 0 and rand < rate_aux) then
                if (test_long = '1') then
                    rem_bytes(n) := MAX_AUX_BYTES + 1;
                else
                    uniform(seed1, seed2, rand);
                    rem_bytes(n) := 1 + integer(floor(rand * real(MAX_AUX_BYTES)));
                end if;
            end if;
            -- State machine for the AXI-stream flow control.
            if ((reset_p = '1') or (rem_bytes(n) = 0 and aux_ready(n) = '1')) then
                -- Reset or last byte consumed.
                aux_data(n)  <= (others => '0');
                aux_last(n)  <= '0';
                aux_valid(n) <= '0';
            elsif ((rem_bytes(n) > 0) and (aux_valid(n) = '0' or aux_ready(n) = '1')) then
                -- Generate next byte.
                aux_data(n)  <= rand_byte(n);
                aux_last(n)  <= bool2bit(rem_bytes(n) = 1);
                aux_valid(n) <= '1';
                rem_bytes(n) := rem_bytes(n) - 1;
            end if;
        end loop;

        -- Output flow-control randomization.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < rate_out);

        uniform(seed1, seed2, rand);
        if (rem_pause = 0 and rand < rate_pause) then
            rem_pause := 20;
        elsif (rem_pause > 0) then
            rem_pause := rem_pause - 1;
        end if;
        out_pause <= bool2bit(rem_pause > 0);
    end if;
end process;

-- FIFO references for each data stream.
gen_fifo : for n in 0 to AUX_COUNT generate
    gen_pri : if n = 0 generate
        fifo_in_data(n) <= pri_data;
        fifo_in_last(n) <= pri_last;
        fifo_wr(n)      <= pri_write;
    end generate;
    gen_aux : if n > 0 generate
        fifo_in_data(n) <= aux_data(n);
        fifo_in_last(n) <= aux_last(n);
        fifo_wr(n)      <= aux_valid(n) and aux_ready(n);
    end generate;
    fifo_rd(n) <= out_valid and out_ready and bool2bit(n = get_stream(out_data));

    u_fifo_pri : entity work.fifo_smol_sync
        generic map(
        IO_WIDTH    => 8,
        DEPTH_LOG2  => 6)
        port map(
        in_data     => fifo_in_data(n),
        in_last     => fifo_in_last(n),
        in_write    => fifo_wr(n),
        out_data    => ref_data(n),
        out_last    => ref_last(n),
        out_valid   => open,
        out_read    => fifo_rd(n),
        fifo_full   => open,
        fifo_empty  => open,
        fifo_hfull  => open,
        fifo_hempty => open,
        fifo_error  => open,
        clk         => clk_100,
        reset_p     => reset_p);
end generate;

-- Convert primary flow control.
u_conv : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH      => 8,
    FIFO_DEPTH      => 2 * MAX_AUX_BYTES)
    port map(
    in_data         => pri_data,
    in_last         => pri_last,
    in_write        => pri_write,
    out_data        => in_data(0),
    out_last        => in_last(0),
    out_valid       => in_valid(0),
    out_ready       => in_ready(0),
    clk             => clk_100,
    reset_p         => reset_p);

aux_conv : for n in 1 to AUX_COUNT generate
    in_data(n)   <= aux_data(n);
    in_last(n)   <= aux_last(n);
    in_valid(n)  <= aux_valid(n);
    aux_ready(n) <= in_ready(n);
end generate;

-- Unit under test
uut : entity work.packet_inject
    generic map(
    INPUT_COUNT     => AUX_COUNT+1,
    APPEND_FCS      => false,
    MIN_OUT_BYTES   => 0,
    MAX_OUT_BYTES   => MAX_AUX_BYTES,
    RULE_PRI_MAXLEN => false,
    RULE_PRI_CONTIG => false,
    RULE_AUX_MAXLEN => true,
    RULE_AUX_CONTIG => true)
    port map(
    in0_data        => in_data(0),
    in1_data        => in_data(1),
    in2_data        => in_data(2),
    in3_data        => in_data(3),
    in4_data        => in_data(4),
    in5_data        => in_data(5),
    in6_data        => in_data(6),
    in7_data        => in_data(7),
    in_last         => in_last,
    in_valid        => in_valid,
    in_ready        => in_ready,
    in_error        => aux_error,
    out_data        => out_data,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    out_pause       => out_pause,
    clk             => clk_100,
    reset_p         => reset_p);

-- Check the output stream.
p_output : process(clk_100)
    variable strm   : integer := 0;
    variable bcount : integer := 0;
    variable pcount : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Check data and last against FIFO reference.
        if (reset_p = '0' and out_valid = '1' and out_ready = '1') then
            strm := get_stream(out_data);
            -- Check for pause violations at start of frame.
            if (bcount = 0) then
                assert (pcount < 3)
                    report "Pause violation: " & integer'image(pcount)
                    severity error;
            end if;
            -- Always check for data match.
            assert (out_data = ref_data(strm))
                report "Output data mismatch." severity error;
            -- Ignore "last" strobe if we're testing aux-too-long condition.
            if (strm = 0 or test_long = '0') then
                assert (out_last = ref_last(strm))
                    report "End-of-packet mismatch." severity error;
            end if;
            -- Count bytes received this frame.
            if (out_last = '1') then
                bcount := 0;
            else
                bcount := bcount + 1;
            end if;
        end if;

        -- Count consecutive pause cycles.
        if (reset_p = '1' or out_pause = '0') then
            pcount := 0;
        elsif (out_valid = '0' or out_ready = '1') then
            pcount := pcount + 1;
        end if;

        if (reset_p = '1') then
            aux_errct <= 0;
        elsif (aux_error = '1') then
            aux_errct <= aux_errct + 1;
        end if;
    end if;
end process;

-- High-level test control
p_test : process
    procedure run_test(rp, ro, ra : real; l : std_logic) is
    begin
        -- Set test conditions and issue reset.
        report "Starting test #" & integer'image(test_idx+1);
        test_idx    <= test_idx + 1;
        test_long   <= l;
        rate_pri    <= rp;
        rate_out    <= ro;
        rate_aux    <= ra;

        -- Force reset, then allow test to run.
        reset_p <= '1';
        wait for 1 us;
        reset_p <= '0';
        wait for 999 us;

        -- Confirm expected error counts.
        if (test_long = '1') then
            assert (aux_errct > 0)
                report "Missing aux-error." severity error;
        else
            assert (aux_errct = 0)
                report "Unexected aux-error." severity error;
        end if;
    end procedure;
begin
    rate_pause <= 0.0;
    run_test(0.10, 1.00, 0.01, '0');
    run_test(0.10, 1.00, 0.01, '1');
    run_test(0.50, 1.00, 0.01, '0');
    run_test(0.50, 1.00, 0.01, '1');
    run_test(0.90, 1.00, 0.01, '0');
    run_test(0.90, 1.00, 0.01, '1');
    run_test(0.99, 1.00, 0.01, '0');
    run_test(0.99, 1.00, 0.01, '1');
    run_test(0.40, 0.50, 0.01, '1');
    rate_pause <= 0.002;
    run_test(0.10, 1.00, 0.01, '0');
    run_test(0.50, 1.00, 0.01, '0');
    run_test(0.90, 1.00, 0.01, '0');
    run_test(0.99, 1.00, 0.01, '0');
    run_test(0.40, 0.50, 0.01, '1');
    report "All tests completed!";
    wait;
end process;

end tb;
