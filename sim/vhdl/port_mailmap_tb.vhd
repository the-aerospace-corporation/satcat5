--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus "MailMap" port
--
-- This is a unit test for "MailMap" virtual port.  This block is typically
-- controlled by a soft-core microcontroller; in this test a scan controller
-- monitors two MailMap ports and quickly copies data from one to the other
-- when it is safe to do so.
--
-- The complete test takes about 2.2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM, SIN, COS
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.switch_types.all;

entity port_mailmap_tb is
    generic (
    BIG_ENDIAN  : boolean := false;     -- Big-endian byte order?
    CHECK_FCS   : boolean := true);     -- Always check FCS?
    -- Unit testbench top level, no I/O ports
end port_mailmap_tb;

architecture tb of port_mailmap_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS     : integer := 100;

-- Control register address
constant DEVADDR_A      : integer := 42;
constant DEVADDR_B      : integer := 47;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Shared control signals.
type cstate_t is (
    COPY_START,
    COPY_POLL_TX,
    COPY_POLL_RX,
    COPY_A2B,
    COPY_B2A);

signal cstate               : cstate_t := COPY_START;
signal a_cfgcmd, b_cfgcmd   : cfgbus_cmd;
signal a_cfgack, b_cfgack   : cfgbus_ack;
signal a_busy,   b_busy     : std_logic := '0';
signal a_avail,  b_avail    : natural := 0;
signal rdidx,    wridx      : natural := 0;
signal read_rate            : real := 0.0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Poll status and copy data through ConfigBus.
a_cfgcmd.clk     <= clk_100;
a_cfgcmd.devaddr <= DEVADDR_A;
a_cfgcmd.wstrb   <= (others => '1');
a_cfgcmd.reset_p <= reset_p;

b_cfgcmd.clk     <= clk_100;
b_cfgcmd.devaddr <= DEVADDR_B;
b_cfgcmd.wstrb   <= (others => '1');
b_cfgcmd.reset_p <= reset_p;

p_ctrl : process(a_cfgcmd.clk)
    constant REG_RXBASE     : cfgbus_regaddr := 0;
    constant REG_RXSTATUS   : cfgbus_regaddr := 511;
    constant REG_TXBASE     : cfgbus_regaddr := 512;
    constant REG_TXSTATUS   : cfgbus_regaddr := 1023;

    variable seed1 : positive := 678109;
    variable seed2 : positive := 167190;
    variable rand  : real := 0.0;
    variable phase : real := 0.0;
begin
    if rising_edge(a_cfgcmd.clk) then
        -- Set defaults.
        a_cfgcmd.regaddr <= 0;
        a_cfgcmd.wdata   <= (others => '0');
        a_cfgcmd.wrcmd   <= '0';
        a_cfgcmd.rdcmd   <= '0';

        b_cfgcmd.regaddr <= 0;
        b_cfgcmd.wdata   <= (others => '0');
        b_cfgcmd.wrcmd   <= '0';
        b_cfgcmd.rdcmd   <= '0';

        -- Gradual transitions between flow-control edge cases.
        if (reset_p = '1') then
            phase := 0.0;
        else
            phase := phase + 0.0001;
        end if;
        read_rate <= cos(phase)**2;

        -- Next command depends on state.
        if (reset_p = '1') then
            cstate  <= COPY_START;
            a_avail <= 0;
            b_avail <= 0;
            a_busy  <= '0';
            b_busy  <= '0';
            rdidx   <= 0;
            wridx   <= 0;
        elsif (cstate = COPY_START) then
            -- Start copy if possible, otherwise begin polling.
            rdidx   <= 0;
            wridx   <= 0;
            if (a_avail > 0 and b_busy = '0') then
                cstate  <= COPY_A2B;
            elsif (b_avail > 0 and a_busy = '0') then
                cstate  <= COPY_B2A;
            else
                cstate  <= COPY_POLL_TX;
                a_cfgcmd.regaddr <= REG_TXSTATUS;
                b_cfgcmd.regaddr <= REG_TXSTATUS;
                a_cfgcmd.rdcmd   <= '1';
                b_cfgcmd.rdcmd   <= '1';
            end if;
        elsif (cstate = COPY_POLL_TX) then
            -- Accept Tx status, then read Rx status.
            assert (a_cfgack.rdack = b_cfgack.rdack);
            if (a_cfgack.rdack = '1') then
                a_busy  <= or_reduce(a_cfgack.rdata);
                b_busy  <= or_reduce(b_cfgack.rdata);
                cstate  <= COPY_POLL_RX;
                a_cfgcmd.regaddr <= REG_RXSTATUS;
                b_cfgcmd.regaddr <= REG_RXSTATUS;
                a_cfgcmd.rdcmd   <= '1';
                b_cfgcmd.rdcmd   <= '1';
            end if;
        elsif (cstate = COPY_POLL_RX) then
            -- Accept Rx status, then loop.
            assert (a_cfgack.rdack = b_cfgack.rdack);
            if (a_cfgack.rdack = '1') then
                a_avail <= u2i(a_cfgack.rdata);
                b_avail <= u2i(b_cfgack.rdata);
                cstate  <= COPY_START;
            end if;
        elsif (cstate = COPY_A2B) then
            -- Issue each read command.
            uniform(seed1, seed2, rand);
            if (4*rdidx < a_avail and rand < read_rate) then
                rdidx <= rdidx + 1;
                a_cfgcmd.regaddr <= REG_RXBASE + rdidx;
                a_cfgcmd.rdcmd   <= '1';
            end if;
            -- As replies arrive, issue each write.
            -- Once done, issue the send and clear commands.
            if (a_cfgack.rdack = '1') then
                wridx <= wridx + 1;
                b_cfgcmd.regaddr <= REG_TXBASE + wridx;
                b_cfgcmd.wdata   <= a_cfgack.rdata;
                b_cfgcmd.wrcmd   <= '1';
            elsif (4*wridx >= a_avail) then
                cstate  <= COPY_START;
                a_avail <= 0;
                a_cfgcmd.regaddr <= REG_RXSTATUS;   -- Clear
                a_cfgcmd.wdata   <= (others => '1');
                a_cfgcmd.wrcmd   <= '1';
                b_cfgcmd.regaddr <= REG_TXSTATUS;   -- Send
                b_cfgcmd.wdata   <= i2s(a_avail, 32);
                b_cfgcmd.wrcmd   <= '1';
            end if;
        elsif (cstate = COPY_B2A) then
            -- Issue each read command.
            uniform(seed1, seed2, rand);
            if (4*rdidx < b_avail and rand < read_rate) then
                rdidx <= rdidx + 1;
                b_cfgcmd.regaddr <= REG_RXBASE + rdidx;
                b_cfgcmd.rdcmd   <= '1';
            end if;
            -- As replies arrive, issue each write.
            -- Once done, issue the send and clear commands.
            if (b_cfgack.rdack = '1') then
                wridx <= wridx + 1;
                a_cfgcmd.regaddr <= REG_TXBASE + wridx;
                a_cfgcmd.wdata   <= b_cfgack.rdata;
                a_cfgcmd.wrcmd   <= '1';
            elsif (4*wridx >= b_avail) then
                cstate  <= COPY_START;
                b_avail <= 0;
                b_cfgcmd.regaddr <= REG_RXSTATUS;   -- Clear
                b_cfgcmd.wdata   <= (others => '1');
                b_cfgcmd.wrcmd   <= '1';
                a_cfgcmd.regaddr <= REG_TXSTATUS;   -- Send
                a_cfgcmd.wdata   <= i2s(b_avail, 32);
                a_cfgcmd.wrcmd   <= '1';
            end if;
        end if;
    end if;
end process;

-- Streaming source and sink for each link:
u_src_a2b : entity work.port_test_common
    generic map(
    FIFO_SZ => 4096,
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
    FIFO_SZ => 4096,
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b,
    txctrl  => txctrl_b,
    rxdata  => rxdata_a,
    rxdone  => rxdone_a,
    rxcount => RX_PACKETS);

-- Two units under test, connected to the same ConfigBus.
uut_a : entity work.port_mailmap
    generic map(
    DEV_ADDR    => DEVADDR_A,
    BIG_ENDIAN  => BIG_ENDIAN,
    CHECK_FCS   => CHECK_FCS)
    port map(
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    cfg_cmd     => a_cfgcmd,
    cfg_ack     => a_cfgack);

uut_b : entity work.port_mailmap
    generic map(
    DEV_ADDR    => DEVADDR_B,
    BIG_ENDIAN  => BIG_ENDIAN,
    CHECK_FCS   => CHECK_FCS)
    port map(
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    cfg_cmd     => b_cfgcmd,
    cfg_ack     => b_cfgack);

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
