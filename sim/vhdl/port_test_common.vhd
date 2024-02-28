--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Helper logic for testing external interface ports
--
-- This is a shared-logic module for testing xMII and similar interfaces
-- back-to-back.  (e.g., port_rgmii_tb, port_rmii_tb, etc.)  It uses the
-- generic logical port interfaces defined in switch_types.
--
-- This block generates one input stream (for transmission by unit A or B)
-- and checks the other unit's output stream (i.e., from unit B or A.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_test_common is
    generic (
    FIFO_SZ : positive := 1024;     -- FIFO depth (>= max latency)
    DSEED1  : positive := 1234;     -- Initial seed #1 for test data
    DSEED2  : positive := 5678);    -- Initial seed #2 for test data
    port (
    rxdata  : in  port_rx_m2s;      -- Received data from UUT (B/A)
    txdata  : out port_tx_s2m;      -- Transmit data to UUT (A/B)
    txctrl  : in  port_tx_m2s;      -- Transmit control from UUT (A/B)
    txnow   : in  tstamp_t := (others => '0');  -- Current time (if needed)
    txrun   : in  std_logic := '1'; -- Allow transmission? (optional)
    rxcount : in  integer;          -- Number of Rx packets before "done"
    rxdone  : out std_logic);       -- Received at least rxcount packets?
end port_test_common;

architecture tb of port_test_common is

-- Delayed copies of rxdata signals.
signal rxdata_data  : std_logic_vector(7 downto 0) := (others => '0');
signal rxdata_write : std_logic := '0';
signal rxdata_last  : std_logic := '0';
signal rxdata_rxerr : std_logic := '0';
signal rxdata_reset : std_logic := '1';

-- Internal signals
signal src_port : port_rx_m2s;
signal ref_data : std_logic_vector(7 downto 0) := (others => '0');
signal ref_last : std_logic := '0';
signal txdata_i : port_tx_s2m;
signal rcvd_pkt : integer := 0;
signal rxdone_i : std_logic := '0';

-- Reference data FIFO.
type array_t is array(0 to FIFO_SZ-1) of std_logic_vector(7 downto 0);
shared variable fifo_data : array_t := (others => (others => '0'));
shared variable fifo_last : std_logic_vector(FIFO_SZ-1 downto 0) := (others => '0');
shared variable rd_addr, wr_addr : integer range 0 to FIFO_SZ-1 := 0;

begin

-- Delayed copies of rxdata signals, to better handle simulator
-- artifacts where the clock arrives one or two timesteps early.
rxdata_data  <= rxdata.data     after 0.1 ns;
rxdata_write <= rxdata.write    after 0.1 ns;
rxdata_last  <= rxdata.last     after 0.1 ns;
rxdata_rxerr <= rxdata.rxerr    after 0.1 ns;
rxdata_reset <= rxdata.reset_p  after 0.1 ns;

-- Streaming input data for each unit:
-- Note: Source is designed for testing switch, must adapt port type.
u_src : entity work.eth_traffic_sim
    generic map(
    AUTO_START  => false,
    INIT_SEED1  => DSEED1,
    INIT_SEED2  => DSEED2)
    port map(
    clk         => txctrl.clk,
    reset_p     => txctrl.reset_p,
    pkt_start   => txrun,
    mac_src     => x"01",
    mac_dst     => x"02",
    out_port    => src_port,
    out_valid   => txdata_i.valid,
    out_ready   => txctrl.ready);

txdata_i.data   <= src_port.data;
txdata_i.last   <= src_port.last;
txdata          <= txdata_i;

-- Asynchronous FIFO for buffering reference data.
-- Note: Must support first-word fallthrough.
p_write : process(txctrl.clk)
begin
    if rising_edge(txctrl.clk) then
        if (txctrl.reset_p = '1') then
            wr_addr := 0;
        elsif (src_port.write = '1') then
            fifo_data(wr_addr) := src_port.data;
            fifo_last(wr_addr) := src_port.last;
            wr_addr := (wr_addr + 1) mod FIFO_SZ;
            assert (wr_addr /= rd_addr)
                report "Internal overflow." severity error;
        end if;
    end if;
end process;

p_read : process(rxdata.clk)
begin
    if rising_edge(rxdata.clk) then
        if (rxdata_reset = '1') then
            rd_addr := 0;
        elsif (rxdata_write = '1') then
            rd_addr := (rd_addr + 1) mod FIFO_SZ;
        end if;
        ref_data <= fifo_data(rd_addr);
        ref_last <= fifo_last(rd_addr);
    end if;
end process;

-- Check output stream matches expectations.
-- Note: Use falling edge to avoid weird simulation issues where
--       clock arrives one picosecond earlier than associated data.
p_checka : process(rxdata.clk)
begin
    if falling_edge(rxdata.clk) then
        assert (rxdata_rxerr = '0')
            report "Rx: Unexpected error strobe" severity error;
        assert (rxdata_reset = '1' or rxdata_write = '0' or rxdata_write = '1')
            report "Rx: Invalid write strobe" severity error;
        if (rxdata_reset = '1') then
            rcvd_pkt <= 0;
        elsif (rxdata_write = '1') then
            assert (rxdata_data = ref_data)
                report "Rx: Data mismatch" severity error;
            assert (rxdata_last = ref_last)
                report "Rx: Last mismatch" severity error;
            if (ref_last = '1') then
                rcvd_pkt <= rcvd_pkt + 1;
            end if;
        end if;

        rxdone <= bool2bit(rcvd_pkt >= rxcount);
    end if;
end process;

end tb;
