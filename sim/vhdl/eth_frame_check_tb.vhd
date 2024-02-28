--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet frame verification.
--
-- This testbench generates randomized Ethernet frames in the
-- following categories:
--      * Valid frames with an EtherType field.
--      * Valid frames with a length field.
--      * Invalid frames that are too short or too long.
--      * Invalid frames with a mismatched length field.
--      * Invalid frames with a mismatched check sequence.
--
-- The output is inspected to verify that the data is correct and
-- the commit/revert strobes are asserted correctly.
--
-- The test runs indefinitely, with reasonably complete coverage
-- (1000 packets) after about 8.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity eth_frame_check_tb_helper is
    generic (
    IO_BYTES    : positive;             -- Width of input/output datapath?
    STRIP_FCS   : boolean);             -- Remove FCS from output?
    port (
    test_done   : out std_logic);
end eth_frame_check_tb_helper;

architecture tb of eth_frame_check_tb_helper is

-- Local type definitions:
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input and reference streams
signal in_rate      : real := 0.0;
signal in_data      : data_t := (others => '0');
signal in_nlast     : last_t := 0;
signal in_write     : std_logic := '0';
signal ref_data     : data_t := (others => '0');
signal ref_nlast    : last_t := 0;
signal ref_commit   : std_logic := '0';
signal ref_revert   : std_logic := '0';
signal ref_error    : std_logic := '0';

-- Output stream
signal out_data     : data_t;
signal out_nlast    : last_t;
signal out_write    : std_logic;
signal out_commit   : std_logic;
signal out_revert   : std_logic;
signal out_error    : std_logic;

-- High-level test control
signal ref_index    : natural := 0;
signal test_done_i  : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Set rate of input stream.
p_rate : process
begin
    wait until (reset_p = '0');
    for n in 1 to 9 loop
        in_rate <= 0.1 * real(n);
        wait for 100 us;
    end loop;
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
    variable tmp_flip : std_logic := '0';
    variable tmp_len  : positive := 1;
    variable tmp_typ  : mac_type_t := (others => '0');

    procedure syncrand_byte(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        for n in tmp_byte'range loop
            uniform(s1, s2, rand);
            tmp_byte(n) := bool2bit(rand < 0.5);
        end loop;
    end procedure;

    procedure syncrand_etype(variable s1,s2: inout positive) is
    begin
        syncrand_byte(s1,s2);   tmp_typ(15 downto 8) := tmp_byte;
        syncrand_byte(s1,s2);   tmp_typ(7 downto 0) := tmp_byte;
        if (unsigned(tmp_typ) < 1530) then
            tmp_typ := not tmp_typ;
        end if;
    end procedure;

    procedure syncrand_pkt(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        tmp_flip := '0';
        uniform(s1, s2, rand);
        if (rand < 0.1) then        -- 10% chance of too-short (1-63 bytes)
            uniform(s1, s2, rand);
            tmp_len := 1 + integer(floor(rand * 63.0));
            syncrand_etype(s1, s2);
        elsif (rand < 0.2) then     -- 10% chance of too-long (1523+ bytes)
            uniform(s1, s2, rand);
            tmp_len := MAX_FRAME_BYTES + 1 + integer(floor(rand * 63.0));
            syncrand_etype(s1, s2);
        elsif (rand < 0.3) then     -- 10% chance of valid length (64-1518)
            uniform(s1, s2, rand);
            tmp_len := 64 + integer(floor(rand * 1454.0));
            tmp_typ := i2s(tmp_len - 18, 16);
        elsif (rand < 0.4) then     -- 10% chance of mismatched length
            uniform(s1, s2, rand);
            tmp_len := 64 + integer(floor(rand * 1454.0));
            uniform(s1, s2, rand);
            if (rand < 0.5) then
                tmp_typ := i2s(tmp_len - 19, 16);
            else
                tmp_typ := i2s(tmp_len - 17, 16);
            end if;
        else                        -- Normal frame (64-1522 bytes)
            tmp_flip := bool2bit(rand < 0.5);
            uniform(s1, s2, rand);
            tmp_len := 64 + integer(floor(rand * 1458.0));
            syncrand_etype(s1, s2);
        end if;
    end procedure;

    -- Frame-generator state.
    variable in_rem_dat     : natural := 0;
    variable in_rem_all     : natural := 0;
    variable in_bcount      : natural := 0;
    variable in_bflip       : std_logic := '0';
    variable in_etype       : mac_type_t := (others => '0');
    variable in_crc         : crc_word_t := CRC_INIT;
    variable ref_rem_dat    : natural := 0;
    variable ref_rem_all    : natural := 0;
    variable ref_bcount     : natural := 0;
    variable ref_bflip      : std_logic := '0';
    variable ref_etype      : mac_type_t := (others => '0');
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
            -- Randomize frame parameters...
            syncrand_pkt(iseed1, iseed2);
            in_bcount   := 0;           -- Count bytes sent
            in_bflip    := tmp_flip;    -- Bad FCS?
            in_etype    := tmp_typ;     -- Random type/length
            in_crc      := CRC_INIT;    -- Reset CRC
            in_rem_all  := tmp_len;     -- Data + CRC
            in_rem_dat  := int_max(0, tmp_len - FCS_BYTES);
        end if;

        while (ref_rem_all = 0 and (reset_p = '1' or out_write = '1')) loop
            -- Randomize frame parameters...
            syncrand_pkt(rseed1, rseed2);
            ref_bcount  := 0;           -- Count bytes sent
            ref_bflip   := tmp_flip;
            ref_etype   := tmp_typ;     -- Random type/length
            ref_crc     := CRC_INIT;    -- Reset CRC
            if (STRIP_FCS) then
                ref_rem_all := int_max(0, tmp_len - 4);
                ref_rem_dat := int_max(0, tmp_len - 4);
            else
                ref_rem_all := tmp_len;
                ref_rem_dat := int_max(0, tmp_len - 4);
            end if;
            -- Is this a valid frame?
            if (ref_bflip = '1' or tmp_len < MIN_FRAME_BYTES or tmp_len > MAX_FRAME_BYTES) then
                ref_commit  <= '0'; -- Invalid FCS or frame size
                ref_revert  <= '1';
                ref_error   <= '1';
            elsif (u2i(tmp_typ) >= 1530) then
                ref_commit  <= '1'; -- EtherType frame
                ref_revert  <= '0';
                ref_error   <= '0';
            elsif (u2i(tmp_typ) = tmp_len - 18) then
                ref_commit  <= '1'; -- Length field match
                ref_revert  <= '0';
                ref_error   <= '0';
            else
                ref_commit  <= '0'; -- Length field mismatch
                ref_revert  <= '1';
                ref_error   <= '1';
            end if;
        end loop;

        -- Generate the next input word?
        in_data  <= (others => '0');
        in_nlast <= 0;
        if (rand_bit(in_rate) = '1') then
            in_write <= '1';            -- New data created
            -- Update the end-of-frame indicator.
            if (in_rem_all <= IO_BYTES) then
                in_nlast <= in_rem_all; -- End of frame (partial word)
            else
                in_nlast <= 0;          -- Continue (full word)
            end if;
            -- Generate each random byte, then append CRC.
            for b in 0 to IO_BYTES-1 loop
                if (in_rem_dat > 0) then
                    if (in_bcount = ETH_HDR_ETYPE) then
                        tmp_byte := in_etype(15 downto 8);
                    elsif (in_bcount = ETH_HDR_ETYPE + 1) then
                        tmp_byte := in_etype(7 downto 0);
                    else
                        syncrand_byte(iseed1, iseed2);
                    end if;
                    in_crc := crc_next(in_crc, tmp_byte);
                    in_bcount  := in_bcount + 1;
                    in_rem_dat := in_rem_dat - 1;
                    in_rem_all := in_rem_all - 1;   -- Test data
                elsif (in_rem_all > 4) then
                    tmp_byte := (others => '0');
                    in_crc := crc_next(in_crc, tmp_byte);
                    in_rem_all := in_rem_all - 1;   -- Zero-padding
                elsif (in_rem_all > 0 and in_bflip = '1') then
                    tmp_byte := flip_byte(in_crc(8*in_rem_all-1 downto 8*in_rem_all-8));
                    in_rem_all := in_rem_all - 1;   -- Bad FCS / CRC
                elsif (in_rem_all > 0) then
                    tmp_byte := not flip_byte(in_crc(8*in_rem_all-1 downto 8*in_rem_all-8));
                    in_rem_all := in_rem_all - 1;   -- Good FCS / CRC
                else
                    tmp_byte := (others => '0');    -- Idle
                end if;
                in_data(in_data'left-8*b downto in_data'left-8*b-7) <= tmp_byte;
            end loop;
        else
            in_write <= '0';
        end if;

        -- Generate the next reference word?
        if (reset_p = '1' or out_write = '1') then
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
                    if (ref_bcount = ETH_HDR_ETYPE) then
                        tmp_byte := ref_etype(15 downto 8);
                    elsif (ref_bcount = ETH_HDR_ETYPE + 1) then
                        tmp_byte := ref_etype(7 downto 0);
                    else
                        syncrand_byte(rseed1, rseed2);
                    end if;
                    ref_crc := crc_next(ref_crc, tmp_byte);
                    ref_bcount  := ref_bcount + 1;
                    ref_rem_dat := ref_rem_dat - 1;
                    ref_rem_all := ref_rem_all - 1; -- Test data
                elsif (ref_rem_all > 4) then
                    tmp_byte := (others => '0');
                    ref_crc := crc_next(ref_crc, tmp_byte);
                    ref_rem_all := ref_rem_all - 1; -- Zero-pad
                elsif (ref_rem_all > 0 and ref_bflip = '1') then
                    tmp_byte := flip_byte(ref_crc(8*ref_rem_all-1 downto 8*ref_rem_all-8));
                    ref_rem_all := ref_rem_all - 1; -- Bad FCS / CRC
                elsif (ref_rem_all > 0) then
                    tmp_byte := not flip_byte(ref_crc(8*ref_rem_all-1 downto 8*ref_rem_all-8));
                    ref_rem_all := ref_rem_all - 1; -- Good FCS / CRC
                else
                    tmp_byte := (others => '0');    -- Idle
                end if;
                ref_data(ref_data'left-8*b downto ref_data'left-8*b-7) <= tmp_byte;
            end loop;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.eth_frame_check
    generic map(
    STRIP_FCS   => STRIP_FCS,
    IO_BYTES    => IO_BYTES)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_write   => out_write,
    out_commit  => out_commit,
    out_revert  => out_revert,
    out_error   => out_error,
    clk         => clk_100,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk_100)
    variable chk_mask : data_t := (others => '1');
begin
    if rising_edge(clk_100) then
        if (out_write = '1') then
            for b in chk_mask'range loop    -- Ignore trailing bytes in output.
                chk_mask(chk_mask'left-b) := bool2bit((ref_nlast = 0) or (b/8 < ref_nlast));
            end loop;
            assert ((out_data and chk_mask) = ref_data)
                report "DATA mismatch in packet " & integer'image(ref_index)
                severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch in packet " & integer'image(ref_index)
                severity error;
        end if;

        if (out_write = '1' and ref_nlast > 0) then
            assert (out_commit = ref_commit and out_revert = ref_revert and out_error = ref_error)
                report "Commit/revert mismatch for packet " & integer'image(ref_index)
                severity error;
        elsif (reset_p = '0') then
            assert (out_commit = '0' and out_revert = '0' and out_error = '0')
                report "Unexpected commit/revert strobe" severity error;
        end if;

        if (reset_p = '1') then
            test_done_i <= '0';
            ref_index <= 0;
        elsif (out_write = '1' and ref_nlast > 0) then
            if (ref_index mod 1000 = 999) then
                test_done_i <= '1';
            end if;
            if (ref_index mod 500 = 499) then
                report "Tested packet #" & integer'image(ref_index+1) severity note;
            end if;
            ref_index <= ref_index + 1;
        end if;
    end if;
end process;

test_done <= test_done_i;

end tb;

-----------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity eth_frame_check_tb is
    -- Unit testbench top level, no I/O ports
end eth_frame_check_tb;

architecture tb of eth_frame_check_tb is

signal test_done : std_logic_vector(0 to 7) := (others => '1');

begin

uut1a : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 1,
    STRIP_FCS   => false)
    port map(test_done => test_done(0));

uut1b : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 1,
    STRIP_FCS   => true)
    port map(test_done => test_done(1));

uut2a : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 2,
    STRIP_FCS   => false)
    port map(test_done => test_done(2));

uut2b : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 2,
    STRIP_FCS   => true)
    port map(test_done => test_done(3));

uut3 : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 3,
    STRIP_FCS   => true)
    port map(test_done => test_done(4));

uut4 : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 4,
    STRIP_FCS   => true)
    port map(test_done => test_done(5));

uut5 : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 5,
    STRIP_FCS   => true)
    port map(test_done => test_done(6));

uut8 : entity work.eth_frame_check_tb_helper
    generic map(
    IO_BYTES    => 8,
    STRIP_FCS   => true)
    port map(test_done => test_done(7));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
