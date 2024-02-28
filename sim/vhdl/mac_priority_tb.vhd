--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for MAC-layer packet priority sorter
--
-- This testbench configures the "mac_priority" block, streams a large
-- number of randomized Ethernet frames, and confirms that each one is
-- categorized correctly.
--
-- The complete test takes less than 0.1 milliseconds @ IO_BYTES = 16.
-- The complete test takes less than 0.6 milliseconds @ IO_BYTES = 1.
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

entity mac_priority_tb is
    generic (
    IO_BYTES : positive := 16);  -- Set pipeline width
    -- Testbench has no top-level I/O.
end mac_priority_tb;

architecture tb of mac_priority_tb is

-- Clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input and output streams.
signal in_wcount    : mac_bcount_t := 0;
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal out_pri      : std_logic := '0';
signal out_valid    : std_logic := '0';
signal out_ready    : std_logic := '0';
signal out_count    : natural := 0;

-- FIFO for reference stream
signal ref_pri      : std_logic;
signal ref_valid    : std_logic;

-- Test control
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal test_sof     : std_logic := '0';
signal test_idle    : std_logic := '0';
signal test_pri     : std_logic := '0';
signal test_etype   : mac_type_t := (others => '0');
signal cfg_cmd      : cfgbus_cmd;
signal cfg_done     : std_logic;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5.0 ns;    -- 1 / (2*5ns) = 100 MHz
cfg_cmd.clk <= clk_100;

-- Input stream generation:
-- On demand, generate a random frame with the specified EtherType.
p_in : process(clk_100)
    variable temp   : byte_t := (others => '0');
    variable bcount : natural := 0;
    variable blen   : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Start of frame?
        if (test_sof = '1') then
            -- Randomize frame length from 14-128 bytes.
            assert (bcount >= blen)
                report "Packet generator still busy!" severity error;
            bcount  := 0;
            blen    := 14 + rand_int(115);
        end if;

        -- Flow control and output-data randomization
        if (bcount < blen and rand_bit(test_rate) = '1') then
            -- Drive the "last" and "write" strobes.
            in_last  <= bool2bit(bcount + IO_BYTES >= blen);
            in_write <= '1';
            -- Word-counter for packet parsing.
            in_wcount <= int_min(bcount / IO_BYTES, IP_HDR_MAX);
            -- Generate each byte.  (All random except EtherType.)
            for b in IO_BYTES-1 downto 0 loop
                if (bcount = 12) then
                    temp := test_etype(15 downto 8);    -- EtherType (MSBs)
                elsif (bcount = 13) then
                    temp := test_etype(7 downto 0);     -- EtherType (LSBs)
                else
                    temp := rand_vec(8);                -- All other fields
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
        test_idle <= bool2bit(bcount >= blen);
    end if;
end process;

-- FIFO for reference data (one "high" or "low" flag per frame).
out_ready <= ref_valid and out_valid;

u_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 1)
    port map(
    in_data(0)  => test_pri,
    in_write    => test_sof,
    out_data(0) => ref_pri,
    out_valid   => ref_valid,
    out_read    => out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Unit under test
uut : entity work.mac_priority
    generic map(
    DEVADDR     => CFGBUS_ADDR_ANY,
    REGADDR     => CFGBUS_ADDR_ANY,
    IO_BYTES    => IO_BYTES,
    TABLE_SIZE  => 4)
    port map(
    in_wcount   => in_wcount,
    in_data     => in_data,
    in_last     => in_last,
    in_write    => in_write,
    out_pri     => out_pri,
    out_valid   => out_valid,
    out_ready   => out_ready,
    out_error   => open,    -- Not tested
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,    -- Not tested
    cfg_done    => cfg_done,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check output against reference.
p_out : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_valid = '1' and ref_valid = '1') then
            assert (out_pri = ref_pri)
                report "Priority mismatch @" & integer'image(out_count) severity error;
            out_count <= out_count + 1;
        else
            assert (out_valid = '0')
                report "Unexpected output." severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Reset UUT before each test.
    procedure test_start(rate : real) is
    begin
        -- Increment test index and set flow-control conditions.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        test_rate   <= rate;
        -- Hold block in reset for a few clocks.
        reset_p <= '1';
        for n in 1 to 10 loop
            wait until rising_edge(clk_100);
        end loop;
        reset_p <= '0';
    end procedure;

    -- Designate a specific EtherType as high-priority.
    procedure test_load(idx: natural; etype: mac_type_t) is
        constant cmd : cfgbus_word := i2s(idx, 8) & i2s(0, 8) & etype;
    begin

        cfgbus_write(cfg_cmd, 0, 0, cmd);
        wait until rising_edge(cfg_done);
    end procedure;

    -- Send an Ethernet frame of the designated EtherType.
    procedure test_send(pri: std_logic; etype: mac_type_t) is
    begin
        wait until rising_edge(clk_100);
        test_sof    <= '1';
        test_etype  <= etype;
        test_pri    <= pri;
        wait until rising_edge(clk_100);
        test_sof    <= '0';
        wait until rising_edge(clk_100);
        while (test_idle = '0') loop
            wait until rising_edge(clk_100);
        end loop;
    end procedure;
begin
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Repeat the sequence at different rates.
    for n in 1 to 10 loop
        -- Test #1: Empty table.
        test_start(0.1 * real(n));
        test_send('0', x"1234");
        test_send('0', x"5678");
        test_send('0', x"9ABC");
        test_send('0', x"DEF0");

        -- Test #2: One designated type with overwrite.
        test_start(0.1 * real(n));
        test_load(0, x"5678");
        test_send('0', x"1234");
        test_send('1', x"5678");
        test_send('0', x"9ABC");
        test_send('0', x"DEF0");
        test_load(0, x"DEF0");
        test_send('0', x"1234");
        test_send('0', x"5678");
        test_send('0', x"9ABC");
        test_send('1', x"DEF0");

        -- Test #3: Two designated types.
        test_start(0.1 * real(n));
        test_load(0, x"5678");
        test_load(1, x"DEF0");
        test_send('0', x"1234");
        test_send('1', x"5678");
        test_send('0', x"9ABC");
        test_send('1', x"DEF0");
        test_send('0', x"1234");
        test_send('1', x"5678");
        test_send('0', x"9ABC");
        test_send('1', x"DEF0");
        test_send('0', x"1234");
        test_send('1', x"5678");
        test_send('0', x"9ABC");
        test_send('1', x"DEF0");
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
