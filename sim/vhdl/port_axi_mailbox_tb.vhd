--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Testbench for AXI-Lite "Mailbox" port
--
-- This is a unit test for "Mailbox" virtual port.  This block is typically
-- controlled by a soft-core microcontroller, but in this test it is simply
-- connected back-to-back with another identical port.  Both are polled
-- at random intervals to evaluate flow control corner cases.
--
-- The complete test takes about 5.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM, SIN, COS
use     work.common_functions.all;
use     work.switch_types.all;

entity port_axi_mailbox_tb is
    -- Unit testbench top level, no I/O ports
end port_axi_mailbox_tb;

architecture tb of port_axi_mailbox_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 100;

-- Control register address
constant ADDR_WIDTH : integer := 8;
subtype addr_t is std_logic_vector(ADDR_WIDTH-1 downto 0);
constant REG_ADDR_I : integer := 42;
constant REG_ADDR_U : addr_t := I2S(REG_ADDR_I, ADDR_WIDTH);

-- Define the register-write opcodes.
subtype opcode_t is std_logic_vector(23 downto 0);
constant OPCODE_NOOP    : opcode_t := (others => '0');
constant OPCODE_WRITE   : opcode_t := x"020000";
constant OPCODE_FINAL   : opcode_t := x"030000";
constant OPCODE_RESET   : opcode_t := x"FF0000";

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_n      : std_logic := '0';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_m2s;
signal txctrl_a, txctrl_b   : port_tx_s2m;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Intermediate control signals.
signal a_wr_cmd,  b_wr_cmd  : opcode_t;
signal a_rate,    b_rate    : real := 0.0;

-- AXI control signals for each UUT.
signal a_awvalid, b_awvalid : std_logic := '0';
signal a_awready, b_awready : std_logic;
signal a_wdata,   b_wdata   : std_logic_vector(31 downto 0);
signal a_wvalid,  b_wvalid  : std_logic := '0';
signal a_wready,  b_wready  : std_logic;
signal a_arvalid, b_arvalid : std_logic := '0';
signal a_arready, b_arready : std_logic;
signal a_rdata,   b_rdata   : std_logic_vector(31 downto 0);
signal a_rvalid,  b_rvalid  : std_logic;
signal a_rready,  b_rready  : std_logic;
signal a_bresp,   b_bresp   : std_logic_vector(1 downto 0);
signal a_bvalid,  b_bvalid  : std_logic;
signal a_bready,  b_bready  : std_logic := '0';

-- Count transactions on each pipe (AW, W, B, AR, R)
signal a_awcount, b_awcount : natural := 0;
signal a_wcount,  b_wcount  : natural := 0;
signal a_bcount,  b_bcount  : natural := 0;
signal a_arcount, b_arcount : natural := 0;
signal a_rcount,  b_rcount  : natural := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_n <= '1' after 1 us;

-- Cross-connect the two AXI-Lite data streams.
-- (Just the register data; command/address is handled below.)
a_wr_cmd <= OPCODE_NOOP when (b_rdata(31) = '0')
       else OPCODE_WRITE when (b_rdata(30) = '0')
       else OPCODE_FINAL;
b_wr_cmd <= OPCODE_NOOP when (a_rdata(31) = '0')
       else OPCODE_WRITE when (a_rdata(30) = '0')
       else OPCODE_FINAL;

a_wdata  <= a_wr_cmd & b_rdata(7 downto 0);
b_wdata  <= b_wr_cmd & a_rdata(7 downto 0);
a_wvalid <= b_rvalid;
b_wvalid <= a_rvalid;
a_rready <= b_wready;
b_rready <= a_wready;

-- Randomly issue read and write commands at designated rate.
p_poll : process(clk_100)
    function equal_pm2(a,b : natural) return boolean is
    begin
        return (a+2 = b) or (a+1 = b) or (a = b) or (a = b+1) or (a = b+2);
    end function;

    variable seed1 : positive := 678109;
    variable seed2 : positive := 167190;
    variable rand  : real := 0.0;
    variable phase : real := 0.0;
begin
    if rising_edge(clk_100) then
        -- Randomly decide if we should issue each command type.
        -- On new or continued command, set "valid" high.
        -- If no new command and previous was consumed, set "valid" low.
        uniform(seed1, seed2, rand);
        if (reset_n = '1' and rand < a_rate) then
            a_awvalid <= '1';
        elsif (a_awready = '1') then
            a_awvalid <= '0';
        end if;

        uniform(seed1, seed2, rand);
        if (reset_n = '1' and rand < a_rate) then
            a_arvalid <= '1';
        elsif (a_arready = '1') then
            a_arvalid <= '0';
        end if;

        uniform(seed1, seed2, rand);
        if (reset_n = '1' and rand < b_rate) then
            b_awvalid <= '1';
        elsif (b_awready = '1') then
            b_awvalid <= '0';
        end if;

        uniform(seed1, seed2, rand);
        if (reset_n = '1' and rand < b_rate) then
            b_arvalid <= '1';
        elsif (b_arready = '1') then
            b_arvalid <= '0';
        end if;

        -- The write-response "ready" strobes don't require any state.
        uniform(seed1, seed2, rand);
        a_bready <= bool2bit(rand < a_rate);

        uniform(seed1, seed2, rand);
        b_bready <= bool2bit(rand < b_rate);

        -- Count transactions on each pipe (AW, W, B, AR, R)
        a_awcount   <= a_awcount + u2i(a_awvalid and a_awready);
        a_wcount    <= a_wcount  + u2i(a_wvalid  and a_wready);
        a_bcount    <= a_bcount  + u2i(a_bvalid  and a_bready);
        a_arcount   <= a_arcount + u2i(a_arvalid and a_arready);
        a_rcount    <= a_rcount  + u2i(a_rvalid  and a_rready);
        b_awcount   <= b_awcount + u2i(b_awvalid and b_awready);
        b_wcount    <= b_wcount  + u2i(b_wvalid  and b_wready);
        b_bcount    <= b_bcount  + u2i(b_bvalid  and b_bready);
        b_arcount   <= b_arcount + u2i(b_arvalid and b_arready);
        b_rcount    <= b_rcount  + u2i(b_rvalid  and b_rready);

        -- Sanity check on the running-disparity counts.
        assert ( equal_pm2(a_awcount, a_wcount)
             and equal_pm2(a_awcount, a_bcount)
             and equal_pm2(a_wcount,  a_bcount) )
            report "Running A-write disparity." severity error;
        assert ( equal_pm2(a_arcount, a_rcount) )
            report "Running A-read disparity." severity error;
        assert ( equal_pm2(b_awcount, b_wcount)
             and equal_pm2(b_awcount, b_bcount)
             and equal_pm2(b_wcount,  b_bcount) )
            report "Running B-write disparity." severity error;
        assert ( equal_pm2(b_arcount, b_rcount) )
            report "Running B-read disparity." severity error;

        -- Set A/B polling rates using sine^2 and cosine^2,
        -- so we gradually transition between edge cases.
        phase := phase + 0.0001;
        a_rate <= sin(phase)**2;
        b_rate <= cos(phase)**2;
    end if;
end process;

-- Streaming source and sink for each link:
u_src_a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a,
    txctrl  => txctrl_a,
    rxdata  => rxdata_b,
    rxdone  => rxdone_b,
    rxcount => RX_PACKETS);

u_src_b2a : entity work.port_test_common
    generic map(
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b,
    txctrl  => txctrl_b,
    rxdata  => rxdata_a,
    rxdone  => rxdone_a,
    rxcount => RX_PACKETS);

-- Two units under test, connected back-to-back.
uut_a : entity work.port_axi_mailbox
    generic map(
    ADDR_WIDTH  => ADDR_WIDTH,
    REG_ADDR    => REG_ADDR_I)
    port map(
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    axi_clk     => clk_100,
    axi_aresetn => reset_n,
    axi_awaddr  => REG_ADDR_U,
    axi_awvalid => a_awvalid,
    axi_awready => a_awready,
    axi_wdata   => a_wdata,
    axi_wvalid  => a_wvalid,
    axi_wready  => a_wready,
    axi_bresp   => open,    -- Not tested
    axi_bvalid  => a_bvalid,
    axi_bready  => a_bready,
    axi_araddr  => REG_ADDR_U,
    axi_arvalid => a_arvalid,
    axi_arready => a_arready,
    axi_rdata   => a_rdata,
    axi_rresp   => open,    -- Not tested
    axi_rvalid  => a_rvalid,
    axi_rready  => a_rready);

uut_b : entity work.port_axi_mailbox
    generic map(
    ADDR_WIDTH  => ADDR_WIDTH,
    REG_ADDR    => REG_ADDR_I)
    port map(
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    axi_clk     => clk_100,
    axi_aresetn => reset_n,
    axi_awaddr  => REG_ADDR_U,
    axi_awvalid => b_awvalid,
    axi_awready => b_awready,
    axi_wdata   => b_wdata,
    axi_wvalid  => b_wvalid,
    axi_wready  => b_wready,
    axi_bresp   => open,    -- Not tested
    axi_bvalid  => b_bvalid,
    axi_bready  => b_bready,
    axi_araddr  => REG_ADDR_U,
    axi_arvalid => b_arvalid,
    axi_arready => b_arready,
    axi_rdata   => b_rdata,
    axi_rresp   => open,    -- Not tested
    axi_rvalid  => b_rvalid,
    axi_rready  => b_rready);

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
