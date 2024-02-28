--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus "Mailbox" port
--
-- This is a unit test for "Mailbox" virtual port.  This block is typically
-- controlled by a soft-core microcontroller, but in this test it is simply
-- connected back-to-back with another identical port.  Both are polled
-- at random intervals to evaluate flow control corner cases.
--
-- The complete test takes about 1.8 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM, SIN, COS
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.switch_types.all;

entity port_mailbox_tb is
    -- Unit testbench top level, no I/O ports
end port_mailbox_tb;

architecture tb of port_mailbox_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS     : integer := 100;

-- Control register address
constant DEV_ADDR       : integer := 42;

-- Define the register-write opcodes.
subtype opcode_t is std_logic_vector(23 downto 0);
constant OPCODE_NOOP    : opcode_t := (others => '0');
constant OPCODE_WRITE   : opcode_t := x"020000";
constant OPCODE_FINAL   : opcode_t := x"030000";
constant OPCODE_RESET   : opcode_t := x"FF0000";

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Intermediate control signals.
signal a_cfg_cmd, b_cfg_cmd : cfgbus_cmd;
signal a_cfg_ack, b_cfg_ack : cfgbus_ack;
signal a_wr_cmd,  b_wr_cmd  : opcode_t;
signal a_rate,    b_rate    : real := 0.0;
signal exec_a2b,  exec_b2a  : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Cross-connect the two ConfigBus command and data streams.
a_wr_cmd <= OPCODE_NOOP when (b_cfg_ack.rdata(31) = '0')
       else OPCODE_WRITE when (b_cfg_ack.rdata(30) = '0')
       else OPCODE_FINAL;
b_wr_cmd <= OPCODE_NOOP when (a_cfg_ack.rdata(31) = '0')
       else OPCODE_WRITE when (a_cfg_ack.rdata(30) = '0')
       else OPCODE_FINAL;

a_cfg_cmd.clk       <= clk_100;
a_cfg_cmd.devaddr   <= DEV_ADDR;
a_cfg_cmd.regaddr   <= 0;   -- Don't-care
a_cfg_cmd.wdata     <= a_wr_cmd & b_cfg_ack.rdata(7 downto 0);
a_cfg_cmd.wstrb     <= (others => '1');
a_cfg_cmd.wrcmd     <= b_cfg_ack.rdack;
a_cfg_cmd.rdcmd     <= exec_a2b;
a_cfg_cmd.reset_p   <= reset_p;

b_cfg_cmd.clk       <= clk_100;
b_cfg_cmd.devaddr   <= DEV_ADDR;
b_cfg_cmd.regaddr   <= 0;   -- Don't-care
b_cfg_cmd.wdata     <= b_wr_cmd & a_cfg_ack.rdata(7 downto 0);
b_cfg_cmd.wstrb     <= (others => '1');
b_cfg_cmd.wrcmd     <= a_cfg_ack.rdack;
b_cfg_cmd.rdcmd     <= exec_b2a;
b_cfg_cmd.reset_p   <= reset_p;

-- Randomly issue read and write commands at designated rate.
p_poll : process(clk_100)
    variable seed1 : positive := 678109;
    variable seed2 : positive := 167190;
    variable rand  : real := 0.0;
    variable phase : real := 0.0;
begin
    if rising_edge(clk_100) then
        -- Randomly decide if we should issue each command type.
        uniform(seed1, seed2, rand);
        exec_a2b <= bool2bit(rand < a_rate);

        uniform(seed1, seed2, rand);
        exec_b2a <= bool2bit(rand < b_rate);

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
uut_a : entity work.port_mailbox
    generic map(DEV_ADDR => DEV_ADDR)
    port map(
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    cfg_cmd     => a_cfg_cmd,
    cfg_ack     => a_cfg_ack);

uut_b : entity work.port_mailbox
    generic map(DEV_ADDR => DEV_ADDR)
    port map(
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    cfg_cmd     => b_cfg_cmd,
    cfg_ack     => b_cfg_ack);

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
