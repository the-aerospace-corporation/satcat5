--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet status reporting block.
--
-- This testbench generates a series of fixed-size status words,
-- and confirms that the packets sent match the expected format.
-- The status word is randomized after the end of each packet.
--
-- The test sequence covers different flow-control conditions, and
-- completes within 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity config_send_status_tb is
    -- Unit testbench, no I/O ports.
end config_send_status_tb;

architecture tb of config_send_status_tb is

-- Test configuration:
constant MSG_BYTES   : integer := 8;
constant MSG_ETYPE   : mac_type_t := x"5C00";
constant MAC_DEST    : mac_addr_t := x"FFFFFFFFFFFF";
constant MAC_SOURCE  : mac_addr_t := x"536174436174";

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Status word
signal status       : std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');

-- Output stream
signal ref_data     : byte_t := (others => '0');
signal uut_data     : byte_t;
signal uut_last     : std_logic;
signal uut_valid    : std_logic;
signal uut_ready    : std_logic;
signal uut_write    : std_logic;
signal out_rate     : real := 0.0;
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_revert   : std_logic;
signal out_write    : std_logic;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Generate a new status word before the start of each packet.
p_src : process(clk_100)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable empty  : boolean := true;
begin
    if rising_edge(clk_100) then
        -- Clear contents after word is consumed.
        if (reset_p = '0' and out_write = '1' and out_last = '1') then
            empty := true;
        end if;

        -- Flow-control randomization.
        uniform(seed1, seed2, rand);
        uut_ready <= bool2bit(rand < out_rate);

        -- Generate a new random word on demand.
        if (empty) then
            for n in status'range loop
                uniform(seed1, seed2, rand);
                status(n) <= bool2bit(rand < 0.5);
            end loop;
            empty := false;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.config_send_status
    generic map(
    MSG_BYTES       => MSG_BYTES,
    MSG_ETYPE       => MSG_ETYPE,
    MAC_DEST        => MAC_DEST,
    MAC_SOURCE      => MAC_SOURCE,
    AUTO_DELAY_CLKS => 1000)    -- Send every N clock cycles
    port map(
    status_val      => status,
    out_data        => uut_data,
    out_last        => uut_last,
    out_valid       => uut_valid,
    out_ready       => uut_ready,
    clk             => clk_100,
    reset_p         => reset_p);

-- Verify frame-check sequence (FCS).
uut_write <= uut_valid and uut_ready;
u_fcs : entity work.eth_frame_check
    generic map(
    ALLOW_RUNT  => true,
    STRIP_FCS   => true)
    port map(
    in_data     => uut_data,
    in_last     => uut_last,
    in_write    => uut_write,
    out_data    => out_data,
    out_write   => out_write,
    out_commit  => out_last,
    out_revert  => out_revert,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the output stream.
p_chk : process(clk_100)
    -- Expected packet length, not including FCS.
    constant FRAME_BYTES : integer := MSG_BYTES + 14;

    -- Extract indexed byte from a larger vector.
    function get_byte(x : std_logic_vector; b : integer) return byte_t is
        variable x2 : std_logic_vector(x'length-1 downto 0) := x;
        variable temp : byte_t := x2(x2'left-8*b downto x2'left-8*b-7);
    begin
        -- Default byte order is big-endian.
        return temp;
    end function;

    -- Working variables
    variable byte_idx : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Watch for FCS mismatch and other errors:
        assert (out_revert = '0')
            report "Unexpected packet error." severity error;

        -- Confirm data against reference sequence.
        if (reset_p = '1') then
            byte_idx := 0;
        elsif (out_write = '1') then
            assert (out_data = ref_data)
                report "Data mismatch" severity error;
            byte_idx := byte_idx + 1;
            if (out_last = '1' or out_revert = '1') then
                -- Check length before starting new frame.
                assert (byte_idx = FRAME_BYTES)
                    report "Length mismatch" severity error;
                byte_idx := 0;
            end if;
        end if;

        -- Generate next byte in the reference sequence.
        if (byte_idx < FRAME_BYTES) then
            ref_data <= get_byte(MAC_DEST & MAC_SOURCE & MSG_ETYPE & status, byte_idx);
        else
            ref_data <= (others => 'X');    -- Invalid...
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
begin
    wait until falling_edge(reset_p);
    for n in 1 to 10 loop
        report "Starting test #" & integer'image(n);
        out_rate <= real(n) / 10.0;
        wait for 99 us;
    end loop;
    report "All tests finished.";
    wait;
end process;

end tb;
