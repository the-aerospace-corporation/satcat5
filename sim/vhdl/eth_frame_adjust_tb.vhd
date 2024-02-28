--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet frame adjustment block.
--
-- This testbench generates a mixture of regular Ethernet traffic and
-- "runt" packets that are too short for IEEE 802.3 compliance.  Each
-- packet is passed through the unit under test, which pads as needed.
-- The padded checksum is verified by the eth_frame_check block, and
-- underlying data is checked against a FIFO-delayed copy of the input.
--
-- The test runs indefinitely, with reasonably complete coverage
-- (1000 packets) after about 2.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

-- Unit testbench for a specific configuration.
entity eth_frame_adjust_tb_helper is
    generic (
    STRIP_FCS   : boolean;
    IO_BYTES    : positive);
    port (
    test_done   : out std_logic);
end eth_frame_adjust_tb_helper;

architecture helper of eth_frame_adjust_tb_helper is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input and reference streams.
signal in_data      : data_t := (others => '0');
signal in_error     : std_logic := '0';
signal in_nlast     : last_t := 0;
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal in_rate      : real := 0.0;
signal err_rate     : real := 0.0;
signal ref_data     : data_t := (others => '0');
signal ref_nlast    : last_t := 0;

-- Output stream.
signal out_data     : data_t;
signal out_nlast    : last_t;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_rate     : real := 0.0;

-- Test status.
signal frm_idx      : natural := 0;
signal test_done_i  : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Set rate of input and output streams.
p_rate : process
    procedure run(ri, ro, re : real) is
    begin
        -- Run specified test conditions.
        in_rate  <= ri;
        err_rate <= re;
        out_rate <= ro;
        wait for 99 us;
        -- Flush output before the next test.
        in_rate  <= 0.0;
        out_rate <= 1.0;
        wait for 1 us;
    end procedure;
begin
    if (reset_p = '1') then
        -- One-time check for valid-before-ready.
        wait until falling_edge(reset_p);
        in_rate <= 1.0;
        wait for 10 us;
    end if;
    -- All other tests run on a loop...
    run(1.0, 1.0, 0.0); -- Continuity check
    run(1.0, 0.5, 0.0); -- Continuity check
    run(0.1, 0.9, 0.2);
    run(0.3, 0.9, 0.2);
    run(0.5, 0.9, 0.2);
    run(0.7, 0.9, 0.2);
    run(0.9, 0.1, 0.2);
    run(0.9, 0.3, 0.2);
    run(0.9, 0.5, 0.2);
    run(0.9, 0.7, 0.2);
    run(0.9, 0.9, 0.2);
    wait for 500 us;
end process;

-- Input and reference stream generation.
p_input : process(clk_100)
    -- Two synchronized PRNGs.
    constant SEED1  : positive := 123456;
    constant SEED2  : positive := 987654;
    variable iseed1 : positive := SEED1;    -- Input data
    variable iseed2 : positive := SEED2;
    variable rseed1 : positive := SEED1;    -- Reference data
    variable rseed2 : positive := SEED2;

    -- Pull an item from one of the synchronized streams.
    variable tmp_byte : byte_t := (others => '0');
    variable tmp_len  : positive := 1;
    variable tmp_err  : natural := 0;

    procedure syncrand_byte(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        for n in tmp_byte'range loop
            uniform(s1, s2, rand);
            tmp_byte(n) := bool2bit(rand < 0.5);
        end loop;
    end procedure;

    procedure syncrand_len(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        uniform(s1, s2, rand);
        tmp_len := 1 + integer(floor(rand * 256.0));
    end procedure;

    procedure syncrand_err(variable s1,s2: inout positive; len : positive) is
        variable rand1, rand2 : real := 0.0;
    begin
        uniform(s1, s2, rand1);     -- Should frame include an error?
        uniform(s1, s2, rand2);     -- Determine error position.
        if (rand1 < err_rate) then
            tmp_err := 1 + integer(floor(rand2 * real(len)));
        else
            tmp_err := 0;           -- No errors in this frame.
        end if;
    end procedure;

    -- Frame-generator state.
    variable in_rem_dat     : natural := 0;
    variable in_rem_all     : natural := 0;
    variable in_err_pos     : natural := 0;
    variable in_crc         : crc_word_t := CRC_INIT;
    variable ref_rem_dat    : natural := 0;
    variable ref_rem_all    : natural := 0;
    variable ref_err_en     : std_logic := '0';
    variable ref_crc        : crc_word_t := CRC_INIT;
begin
    if rising_edge(clk_100) then
        -- Reset synchronized PRNG state.
        if (reset_p = '1') then
            iseed1      := SEED1;
            iseed2      := SEED2;
            rseed1      := SEED1;
            rseed2      := SEED2;
            in_rem_dat  := 0;
            in_rem_all  := 0;
            ref_rem_dat := 0;
            ref_rem_all := 0;
        end if;

        -- Decide next frame length?
        if (in_rem_all = 0) then
            syncrand_len(iseed1, iseed2);
            in_crc      := CRC_INIT;        -- Reset CRC
            in_rem_dat  := tmp_len;         -- Data only
            if (STRIP_FCS) then
                in_rem_all := tmp_len + 4;  -- Data + CRC
            else
                in_rem_all := tmp_len;      -- Data only
            end if;
            syncrand_err(iseed1, iseed2, in_rem_all);
            in_err_pos  := tmp_err;         -- Error position
        end if;

        if (ref_rem_all = 0) then
            syncrand_len(rseed1, rseed2);
            ref_crc     := CRC_INIT;        -- Reset CRC
            ref_rem_dat := tmp_len;         -- Data only
            if (tmp_len < 60) then
                ref_rem_all := 64;          -- Data + pad + CRC
            else
                ref_rem_all := tmp_len + 4; -- Data + CRC
            end if;
            syncrand_err(rseed1, rseed2, ref_rem_all);
            ref_err_en  := bool2bit(tmp_err > 0);
        end if;

        -- Generate the next input word?
        if (reset_p = '1' or in_valid = '0' or in_ready = '1') then
            in_data  <= (others => '0');
            in_error <= '0';
            in_nlast <= 0;
            if (rand_bit(in_rate) = '1') then
                in_valid <= '1';            -- New data created
                -- Update the end-of-frame indicator.
                if (in_rem_all <= IO_BYTES) then
                    in_nlast <= in_rem_all; -- End of frame (partial word)
                else
                    in_nlast <= 0;          -- Continue (full word)
                end if;
                -- Generate each random byte, then append CRC.
                for b in 0 to IO_BYTES-1 loop
                    if (in_err_pos > 0 and in_err_pos = in_rem_all) then
                        in_error <= '1';    -- Error strobe at this index?
                    end if;
                    if (in_rem_dat > 0) then
                        syncrand_byte(iseed1, iseed2);
                        in_crc := crc_next(in_crc, tmp_byte);
                        in_rem_dat := in_rem_dat - 1;
                        in_rem_all := in_rem_all - 1;   -- Test data
                    elsif (in_rem_all > 4) then
                        tmp_byte := (others => '0');
                        in_crc := crc_next(in_crc, tmp_byte);
                        in_rem_all := in_rem_all - 1;   -- Zero-pad
                    elsif (in_rem_all > 0) then
                        tmp_byte := not flip_byte(in_crc(8*in_rem_all-1 downto 8*in_rem_all-8));
                        in_rem_all := in_rem_all - 1;   -- FCS / CRC
                    else
                        tmp_byte := (others => '0');    -- Idle
                    end if;
                    in_data(in_data'left-8*b downto in_data'left-8*b-7) <= tmp_byte;
                end loop;
            else
                in_valid <= '0';            -- Previous data consumed
            end if;
        end if;

        -- Generate the next reference word?
        if (reset_p = '1' or (out_valid = '1' and out_ready = '1')) then
            ref_data  <= (others => '0');
            ref_nlast <= 0;
            -- Update the end-of-frame indicator.
            if (ref_rem_all <= IO_BYTES) then
                ref_nlast <= ref_rem_all;   -- End of frame (partial word)
            else
                ref_nlast <= 0;             -- Continue (full word)
            end if;
            -- Generate each random byte, then append zero-pad and CRC.
            for b in 0 to IO_BYTES-1 loop
                if (ref_rem_dat > 0) then
                    syncrand_byte(rseed1, rseed2);
                    ref_crc := crc_next(ref_crc, tmp_byte);
                    ref_rem_dat := ref_rem_dat - 1;
                    ref_rem_all := ref_rem_all - 1;     -- Test data
                elsif (ref_rem_all > 4) then
                    tmp_byte := (others => '0');
                    ref_crc := crc_next(ref_crc, tmp_byte);
                    ref_rem_all := ref_rem_all - 1;     -- Zero-pad
                elsif (ref_rem_all > 0) then
                    tmp_byte := (others => ref_err_en); -- Invert?
                    tmp_byte := tmp_byte xnor flip_byte(
                        ref_crc(8*ref_rem_all-1 downto 8*ref_rem_all-8));
                    ref_rem_all := ref_rem_all - 1;     -- FCS / CRC
                else
                    tmp_byte := (others => '0');        -- Idle
                end if;
                ref_data(ref_data'left-8*b downto ref_data'left-8*b-7) <= tmp_byte;
            end loop;
        end if;

        -- Flow-control randomization.
        out_ready <= rand_bit(out_rate);
    end if;
end process;

-- Unit under test
uut : entity work.eth_frame_adjust
    generic map(
    STRIP_FCS   => STRIP_FCS,
    IO_BYTES    => IO_BYTES)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_error    => in_error,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check output stream.
p_check : process(clk_100)
    variable contig_cnt : integer := 0;
    variable contig_req : std_logic := '0';
    variable nodata_cnt : integer := 0;
    variable ref_end    : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Flow control continuity check: Once first byte is valid,
        -- further data must be contiguous until end of packet.
        -- (This is not an AXI requirement, but is needed for port_adjust)
        if (in_rate < 1.0) then
            -- Input not contiguous, disable checking.
            contig_cnt := 0;
        elsif (contig_cnt < 100) then
            -- Hold for a few clock cycles after mode change.
            contig_cnt := contig_cnt + 1;
        elsif (contig_req = '1') then
            -- Output should now be contiguous.
            assert (out_valid = '1')
                report "Contiguous output violation" severity error;
        end if;
        contig_req := out_valid and bool2bit(out_nlast = 0);

        -- Valid/ready deadlock check: Must eventually assert valid without
        -- waiting for ready strobe, to avoid deadlock in certain edge cases.
        if (reset_p = '1' or out_valid = '1') then
            nodata_cnt := 0;
        elsif (out_ready = '0') then
            nodata_cnt := nodata_cnt + 1;
        end if;
        assert (nodata_cnt /= 100)
            report "Valid-before-ready deadlock." severity error;

        -- Check stream contents.
        if (out_valid = '1') then
            assert (out_data = ref_data and out_nlast = ref_nlast)
                report "Output data mismatch" severity error;
        end if;

        -- Count the number of valid received packets.
        if (reset_p = '1') then
            frm_idx     <= 0;
            test_done_i <= '0';
        elsif (out_valid = '1' and out_ready = '1' and out_nlast > 0) then
            frm_idx <= frm_idx + 1;
            if ((frm_idx mod 1000 = 999) or (frm_idx < 1000 and (frm_idx mod 200) = 199)) then
                report "Received packet #" & integer'image(frm_idx+1);
            end if;
            if (frm_idx = 999) then
                report "Test completed, IO_BYTES = " & integer'image(IO_BYTES);
                test_done_i <= '1';
            end if;
        end if;
    end if;
end process;

test_done <= test_done_i;

end helper;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity eth_frame_adjust_tb is
    -- Top-level unit testbench, no I/O ports.
end eth_frame_adjust_tb;

architecture tb of eth_frame_adjust_tb is

signal test_done : std_logic_vector(0 to 6) := (others => '1');

begin

-- Instantiate each configuration under test:
uut0 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => false, IO_BYTES => 1)
    port map(test_done => test_done(0));

uut1 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 1)
    port map(test_done => test_done(1));

uut2 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 2)
    port map(test_done => test_done(2));

uut3 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 3)
    port map(test_done => test_done(3));

uut5 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 5)
    port map(test_done => test_done(4));

uut8 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 8)
    port map(test_done => test_done(5));

uut16 : entity work.eth_frame_adjust_tb_helper
    generic map(STRIP_FCS => true, IO_BYTES => 16)
    port map(test_done => test_done(6));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
