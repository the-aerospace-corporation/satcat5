--------------------------------------------------------------------------
-- Copyright 2020 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet PAUSE frame controller.
--
-- Generate a stream of randomly generated Ethernet frames, which occasionally
-- contain a valid PAUSE frame.  Once received, verify that the PAUSE strobe
-- is held high for the specified amount of time.
--
-- The test takes less than 2.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_pause_ctrl_tb is
    -- Testbench has no I/O ports
end eth_pause_ctrl_tb;

architecture tb of eth_pause_ctrl_tb is

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream generation
signal in_data      : byte_t := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_cmdwr     : std_logic := '0';

-- Reference signal generation.
signal pause_ref    : std_logic := '0';

-- Unit under test.
signal port_rx      : port_rx_m2s;
signal pause_tx     : std_logic;

-- High-level test control.
signal test_inrate  : real := 0.0;
signal test_pstart  : std_logic := '0';
signal test_plen    : integer := 0;
signal test_prate   : positive := 1;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Input stream generation
p_input : process(clk_100)
    variable seed1      : positive := 18710510;
    variable seed2      : positive := 87015819;
    variable rand       : real := 0.0;

    impure function rand_byte return byte_t is
        variable tmp : byte_t;
    begin
        for n in tmp'range loop
            uniform(seed1, seed2, rand);
            tmp(n) := bool2bit(rand < 0.5);
        end loop;
        return tmp;
    end function;

    variable pkt_is_cmd : std_logic := '0';
    variable pkt_bcount : integer := 0;
    variable pkt_blen   : integer := 0;
    variable pkt_arg    : std_logic_vector(15 downto 0) := (others => '0');
    variable cmd_next   : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Keep a sticky flag for the start-command strobe.
        if (test_pstart = '1') then
            cmd_next    := '1';
        end if;

        -- Time to start a new packet?
        if (pkt_bcount = pkt_blen) then
            -- Randomize packet length and note type.
            uniform(seed1, seed2, rand);
            pkt_bcount  := 0;
            pkt_blen    := 18 + integer(floor(rand * 64.0));
            pkt_is_cmd  := cmd_next;
            pkt_arg     := std_logic_vector(to_unsigned(test_plen, 16));
            cmd_next    := '0';
        end if;

        -- Flow-control randomization:
        uniform(seed1, seed2, rand);
        if (rand < test_inrate) then
            -- Generate the next byte...
            if (pkt_is_cmd = '1') then
                -- Generate a valid PAUSE command:
                case pkt_bcount is
                    -- Packet header:
                    when 0 =>   in_data <= x"01";   -- DST-MAC
                    when 1 =>   in_data <= x"80";
                    when 2 =>   in_data <= x"C2";
                    when 3 =>   in_data <= x"00";
                    when 4 =>   in_data <= x"00";
                    when 5 =>   in_data <= x"01";
                    when 12 =>  in_data <= x"88";   -- EtherType
                    when 13 =>  in_data <= x"08";
                    when 14 =>  in_data <= x"00";   -- Opcode
                    when 15 =>  in_data <= x"01";
                    -- Pause time
                    when 16 =>  in_data <= pkt_arg(15 downto 8);
                    when 17 =>  in_data <= pkt_arg(7 downto 0);
                    -- Everything else is don't-care.
                    when others => in_data <= rand_byte;
                end case;
            else
                -- All other packets are random data.
                in_data <= rand_byte;
            end if;
            -- Increment counters and assert strobes.
            pkt_bcount  := pkt_bcount + 1;
            in_last     <= bool2bit(pkt_bcount = pkt_blen);
            in_cmdwr    <= pkt_is_cmd and bool2bit(pkt_bcount = 17);
            in_write    <= '1';
        else
            -- Idle
            in_write    <= '0';
            in_cmdwr    <= '0';
        end if;
    end if;
end process;

-- Reference signal generation.
p_ref : process(clk_100)
    function get_len(len : integer; rate : positive) return integer is
        variable clks_per_quanta : real := 512.0 * 100.0 / real(rate);
        variable clks_total      : real := real(len) * clks_per_quanta;
    begin
        return integer(floor(clks_total));
    end function;

    variable count : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Set counter on command; otherwise decrement.
        if (in_cmdwr = '1') then
            count := get_len(test_plen, test_prate);
        elsif (count > 0) then
            count := count - 1;
        end if;

        -- Pause until end of countdown.
        pause_ref <= bool2bit(count > 0);
    end if;
end process;

-- Unit under test.
port_rx.clk     <= clk_100;
port_rx.data    <= in_data;
port_rx.last    <= in_last;
port_rx.write   <= in_write;
port_rx.rxerr   <= '0';
port_rx.rate    <= get_rate_word(test_prate);
port_rx.status  <= (others => '0');
port_rx.reset_p <= reset_p;

uut : entity work.eth_pause_ctrl
    generic map(
    REFCLK_HZ   => 100_000_000)
    port map(
    port_rx     => port_rx,
    pause_tx    => pause_tx,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- Check output against reference.
p_check : process(clk_100)
    variable change     : integer := 0;
    variable mismatch   : integer := 0;
    variable pause_d    : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Count cycles since last change to UUT output.
        if (pause_tx /= pause_d) then
            assert (change > 100)
                report "Unexpected change!" severity error;
            change := 0;
        else
            change := change + 1;
        end if;

        -- Count consecutive mismatch of UUT vs. REF.
        if (pause_tx = pause_ref) then
            assert (mismatch < 100)
                report "Excessive mismatch: " & integer'image(mismatch)
                severity error;
            mismatch := 0;
        else
            mismatch := mismatch + 1;
        end if;

        -- Delayed copy of pause_tx.
        pause_d := pause_tx;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure pause_cmd(plen : integer) is
    begin
        wait until rising_edge(clk_100);
        test_pstart <= '1';
        test_plen   <= plen;
        wait until rising_edge(clk_100);
        test_pstart <= '0';
    end procedure;
begin
    -- Wait for reset to end.
    test_inrate <= 0.0;
    test_pstart <= '0';
    test_plen   <= 0;
    test_prate  <= 1;
    wait until (reset_p = '0');
    wait for 1 us;

    -- Tests at 10 Mbps -> Quanta = 51 usec
    test_prate  <= 10;
    test_inrate <= 0.5;
    wait for 200 us;
    pause_cmd(1);
    wait for 200 us;
    pause_cmd(2);
    wait for 200 us;
    pause_cmd(3);
    wait for 200 us;
    pause_cmd(999);
    wait for 200 us;
    pause_cmd(0);
    wait for 200 us;

    -- Tests at 100 Mbps -> Quanta = 5.1 usec
    test_prate  <= 100;
    test_inrate <= 0.5;
    wait for 200 us;
    pause_cmd(1);
    wait for 200 us;
    pause_cmd(2);
    wait for 200 us;
    pause_cmd(10);
    wait for 200 us;
    pause_cmd(23);
    wait for 200 us;
    pause_cmd(999);
    wait for 200 us;
    pause_cmd(0);
    wait for 200 us;

    report "All tests completed!";
    wait;
end process;

end tb;
