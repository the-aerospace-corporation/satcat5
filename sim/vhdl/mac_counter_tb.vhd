--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the traffic-counting diagnostic block
--
-- This testbench streams a randomized stream of traffic through the
-- "mac_counter" block, and confirms that the ConfigBus interfaces
-- operates as expected.
--
-- The complete test takes less than 0.5 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity mac_counter_tb_single is
    generic (
    IO_BYTES : positive := 1);   -- Set pipeline width
    -- Testbench has no top-level I/O.
end mac_counter_tb_single;

architecture single of mac_counter_tb_single is

-- Clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream.
signal in_wcount    : mac_bcount_t := 0;
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_busy      : std_logic := '0';

-- ConfigBus interface
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;

-- Test control
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal test_sof     : std_logic := '0';
shared variable test_frame : eth_packet := null;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5.0 ns;    -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
cfg_cmd.clk <= clk_100;

-- Input stream generation:
p_in : process(clk_100)
    variable temp   : byte_t := (others => '0');
    variable btmp   : natural := 0;
    variable bcount : natural := 0;
    variable blen   : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Start of new frame?
        if (test_sof = '1') then
            assert (bcount >= blen)
                report "Packet generator still busy!" severity error;
            bcount  := 0;
            blen    := test_frame.all'length / 8;
        end if;

        -- Flow control and output-data randomization
        if (bcount < blen and rand_bit(test_rate) = '1') then
            -- Drive the "last" and "write" strobes.
            in_last  <= bool2bit(bcount + IO_BYTES >= blen);
            in_write <= '1';
            -- Word-counter for packet parsing.
            in_wcount <= int_min(bcount / IO_BYTES, IP_HDR_MAX);
            -- Relay each byte.
            for b in IO_BYTES-1 downto 0 loop
                if (bcount < blen) then
                    btmp := 8 * (blen - bcount);
                    temp := test_frame.all(btmp-1 downto btmp-8);
                else
                    temp := (others => '0');
                end if;
                in_data(8*b+7 downto 8*b) <= temp;
                bcount := bcount + 1;
            end loop;
        else
            -- No new data this clock.
            in_data  <= (others => '0');
            in_last  <= '0';
            in_write <= '0';
        end if;
        in_busy <= bool2bit(bcount < blen);
    end if;
end process;

-- Unit under test.
uut : entity work.mac_counter
    generic map(
    DEV_ADDR    => CFGBUS_ADDR_ANY,
    REG_ADDR    => CFGBUS_ADDR_ANY,
    IO_BYTES    => IO_BYTES)
    port map(
    in_wcount   => in_wcount,
    in_data     => in_data,
    in_last     => in_last,
    in_write    => in_write,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk_100,
    reset_p     => reset_p);

-- High-level test control.
p_test : process
    -- Generate a random Ethernet frame with the given EtherType.
    impure function test_pkt_eth(etype : mac_type_t) return eth_packet is
        -- Randomize frame length from 1-128 payload bytes.
        constant len : positive := 1 + rand_int(128);
        constant dst : mac_addr_t := rand_vec(48);
        constant src : mac_addr_t := rand_vec(48);
    begin
        return make_eth_pkt(dst, src, etype, rand_vec(8*len));
    end function;

    -- Send a packet with the designated EtherType.
    procedure send_pkt(etype : mac_type_t) is
    begin
        wait until rising_edge(clk_100);
        test_sof    <= '1';
        test_frame  := test_pkt_eth(etype);
        wait until rising_edge(clk_100);
        test_sof    <= '0';
        wait until falling_edge(in_busy);
    end procedure;

    -- Query the counter register and start a new interval.
    procedure counter_query(
        constant etype  : mac_type_t;
        constant refct  : integer := -1)
    is
        constant cfg_word   : cfgbus_word := x"0000" & etype;
        variable read_ct    : integer := 0;
    begin
        -- Write register to refresh counters and set new filter mode.
        cfgbus_write(cfg_cmd, 0, 0, cfg_word);

        -- If a reference count is provided, read it.
        if (refct >= 0) then
            wait for 100 ns;
            cfgbus_read(cfg_cmd, 0, 0);
            cfgbus_wait(cfg_cmd, cfg_ack);
            read_ct := u2i(cfg_ack.rdata);
            assert (cfg_ack.rdack = '1' and read_ct = refct)
                report "Counter mismatch @" & integer'image(test_index)
                     & ": Got " & integer'image(read_ct)
                     & ", expected " & integer'image(refct);
        end if;

        -- Announce start of next test segment.
        -- (Short wait before we allow the first packet to be sent.)
        test_index <= test_index + 1;
        report "Starting test #" & integer'image(test_index + 1);
        wait for 100 ns;
    end procedure;
begin
    cfgbus_reset(cfg_cmd, 1 us);
    wait for 1 us;

    -- Repeat test sequence at different rates...
    for r in 1 to 5 loop
        test_rate <= 0.2 * real(r);

        counter_query(x"0000");     -- First segment = Any EtherType
        for n in 1 to 10 loop
            send_pkt(rand_vec(16));
        end loop;

        counter_query(x"1234", 10); -- Restart / Check previous
        for n in 1 to 5 loop
            send_pkt(x"4321");
            send_pkt(x"3214");
            send_pkt(x"2143");
            send_pkt(x"1432");
        end loop;

        counter_query(x"4321", 0);  -- Restart / Check previous
        for n in 1 to 5 loop
            send_pkt(x"4321");
            send_pkt(x"3214");
            send_pkt(x"2143");
            send_pkt(x"1432");
        end loop;

        counter_query(x"0000", 5);  -- Restart / Check previous
    end loop;

    report "All tests completed, B = " & integer'image(IO_BYTES);
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity mac_counter_tb is
    -- Testbench has no top-level I/O.
end mac_counter_tb;

architecture tb of mac_counter_tb is
begin
    uut1 : entity work.mac_counter_tb_single
        generic map(IO_BYTES => 1);
    uut8 : entity work.mac_counter_tb_single
        generic map(IO_BYTES => 8);
end tb;
