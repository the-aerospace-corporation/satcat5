--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-Testing / Packet-Error Measurement Tool
--
-- This module is used to measure packet-error rate (PER) statistics on an
-- attached port, typically used for loopback tests.  Each port is connected
-- directly to a port_xx block (i.e., without a switch).  Attached ports
-- send traffic at max bandwidth (eth_traffic_src), and any received data
-- is inspected to count valid and invalid packets.  (Frame contents are
-- not tested; only a valid FCS is required.)
--
-- Results for all ports are sent via UART, once per second.
-- Each report frame contains an array of big-endian unsigned 32-bit
-- integers, with a total of 2*N words (where N is the number of ports).
-- The first word in each pair is the number of invalid packets since the
-- last report; the second word in each pair is the number of valid packets.
-- The frames can be sent with SLIP encoding (default) or as raw bytes.
--
-- An optional non-encoded copy of this output is available for other
-- display options, such as the AC701's LCD display.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_pulse2pulse;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity config_port_test is
    generic (
    BAUD_HZ     : positive;                         -- UART baud rate
    CLKREF_HZ   : positive;                         -- Refclk frequency (Hz)
    ETYPE_TEST  : std_logic_vector(15 downto 0);    -- EtherType (Test traffic)
    PORT_COUNT  : positive;                         -- Number of attached ports
    SLIP_UART   : boolean := true);                 -- SLIP encode UART?
    port (
    -- Ports under test
    rx_data     : in  array_rx_m2s(PORT_COUNT-1 downto 0);
    tx_data     : out array_tx_s2m(PORT_COUNT-1 downto 0);
    tx_ctrl     : in  array_tx_m2s(PORT_COUNT-1 downto 0);

    -- Reporting interface(s)
    uart_txd    : out std_logic;                    -- Binary data over UART
    aux_data    : out byte_t;                       -- AUX: Binary data (no SLIP)
    aux_wr      : out std_logic;                    -- AUX: Write-enable
    refclk      : in  std_logic;
    reset_p     : in  std_logic);
end config_port_test;

architecture config_port_test of config_port_test is

-- UART clock-divider is fixed at build-time.
constant UART_CLKDIV : unsigned(15 downto 0) :=
    to_unsigned(clocks_per_baud_uart(CLKREF_HZ, BAUD_HZ), 16);

-- Define convenience types.
subtype bit_array is std_logic_vector(PORT_COUNT-1 downto 0);

subtype stats_word is unsigned(31 downto 0);
type stats_array is array(0 to PORT_COUNT-1) of stats_word;
constant STATS_ZERO : stats_word := (others => '0');

constant REPORT_BYTES : positive := 4*3;

-- Define MAC addresses for each port.
function get_src_mac(n : natural) return mac_addr_t is
    constant SRC : mac_addr_t := x"DEADBEEF" & i2s(n, 16);
begin
    return SRC;
end function;

-- Per-port signals and event strobes.
signal tx_clk       : bit_array;
signal rx_clk       : bit_array;
signal tx_commit_t  : bit_array;    -- Toggle in port-Tx domain
signal rx_commit_i  : bit_array;    -- Strobe in port-Rx domain
signal rx_revert_i  : bit_array;    -- Strobe in port-Rx domain
signal tx_commit_r  : bit_array;    -- Strobe in refclk domain
signal rx_commit_r  : bit_array;    -- Strobe in refclk domain
signal rx_revert_r  : bit_array;    -- Strobe in refclk domain

-- Per-port frame counters.
signal tx_count     : stats_array := (others => STATS_ZERO);
signal rx_count0    : stats_array := (others => STATS_ZERO);
signal rx_count1    : stats_array := (others => STATS_ZERO);

-- Report generation state machine.
signal report_start : std_logic := '0';
signal report_busy  : std_logic := '0';
signal report_next  : std_logic;
signal report_pidx  : integer range 0 to PORT_COUNT-1 := 0;
signal report_bidx  : integer range 0 to REPORT_BYTES-1 := 0;
signal report_word  : std_logic_vector(8*REPORT_BYTES-1 downto 0);

-- One-word buffer.
signal buff_data    : byte_t := (others => '0');
signal buff_last    : std_logic := '0';
signal buff_valid   : std_logic := '0';
signal buff_ready   : std_logic;

-- Optional SLIP encoding.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

begin

-- For each port...
-- TODO: Should we do anything with the txerr and rxerr strobes?
gen_ports : for p in 0 to PORT_COUNT-1 generate
    -- Force clock assignment / simulator workaround.
    -- (See further discussion in "switch_core".)
    tx_clk(p) <= to_01_std(tx_ctrl(p).clk);
    rx_clk(p) <= to_01_std(rx_data(p).clk);

    -- Traffic generator.
    u_tx : entity work.eth_traffic_src
        generic map(
        HDR_DST     => MAC_ADDR_BROADCAST,
        HDR_SRC     => get_src_mac(p),
        HDR_ETYPE   => ETYPE_TEST,
        FRM_NBYTES  => 1000)
        port map(
        out_data    => tx_data(p).data,
        out_last    => tx_data(p).last,
        out_valid   => tx_data(p).valid,
        out_ready   => tx_ctrl(p).ready,
        out_pkt_t   => tx_commit_t(p),
        clk         => tx_clk(p),
        reset_p     => tx_ctrl(p).reset_p);

    -- Check incoming frames.
    u_rx : entity work.eth_frame_check
        generic map(
        ALLOW_JUMBO => true,
        ALLOW_RUNT  => true)
        port map(
        in_data     => rx_data(p).data,
        in_last     => rx_data(p).last,
        in_write    => rx_data(p).write,
        out_data    => open,
        out_write   => open,
        out_commit  => rx_commit_i(p),
        out_revert  => rx_revert_i(p),
        clk         => rx_clk(p),
        reset_p     => rx_data(p).reset_p);

    -- Clock-domain crossing:
    u_sync_tx : sync_toggle2pulse
        port map(
        in_toggle   => tx_commit_t(p),
        out_strobe  => tx_commit_r(p),
        out_clk     => refclk);
    
    u_sync_rx0 : sync_pulse2pulse
        port map(
        in_strobe   => rx_revert_i(p),
        in_clk      => rx_clk(p),
        out_strobe  => rx_revert_r(p),
        out_clk     => refclk);

    u_sync_rx1 : sync_pulse2pulse
        port map(
        in_strobe   => rx_commit_i(p),
        in_clk      => rx_clk(p),
        out_strobe  => rx_commit_r(p),
        out_clk     => refclk);

    -- Count good and bad frames.
    p_count : process(refclk)
        variable tmp_count_tx   : stats_word := (others => '0');
        variable tmp_count_rx0  : stats_word := (others => '0');
        variable tmp_count_rx1  : stats_word := (others => '0');
    begin
        if rising_edge(refclk) then
            -- Stable output counters.
            if (reset_p = '1') then
                tx_count(p)  <= STATS_ZERO;
                rx_count0(p) <= STATS_ZERO;
                rx_count1(p) <= STATS_ZERO;
            elsif (report_start = '1') then
                tx_count(p)  <= tmp_count_tx;
                rx_count0(p) <= tmp_count_rx0;
                rx_count1(p) <= tmp_count_rx1;
            end if;

            -- Working counters.
            if (reset_p = '1') then
                tmp_count_tx  := STATS_ZERO;
                tmp_count_rx0 := STATS_ZERO;
                tmp_count_rx1 := STATS_ZERO;
            elsif (report_start = '1') then
                tmp_count_tx  := STATS_ZERO + u2i(tx_commit_r(p));
                tmp_count_rx0 := STATS_ZERO + u2i(rx_revert_r(p));
                tmp_count_rx1 := STATS_ZERO + u2i(rx_commit_r(p));
            else
                tmp_count_tx  := tmp_count_tx  + u2i(tx_commit_r(p));
                tmp_count_rx0 := tmp_count_rx0 + u2i(rx_revert_r(p));
                tmp_count_rx1 := tmp_count_rx1 + u2i(rx_commit_r(p));
            end if;
        end if;
    end process;
end generate;

-- Generate a "start" strobe once per second.
p_start : process(refclk)
    variable ctr : integer range 0 to CLKREF_HZ-1 := CLKREF_HZ-1;
begin
    if rising_edge(refclk) then
        report_start <= bool2bit(ctr = 0);

        if (reset_p = '1' or ctr = 0) then
            ctr := CLKREF_HZ - 1;
        else
            ctr := ctr - 1;
        end if;
    end if;
end process;

-- Report generation state machine.
report_word <= std_logic_vector(tx_count(report_pidx))
             & std_logic_vector(rx_count0(report_pidx))
             & std_logic_vector(rx_count1(report_pidx));
report_next <= report_busy and (buff_ready or not buff_valid);

p_report : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            -- Global reset
            report_pidx     <= 0;   -- Port index
            report_bidx     <= 0;   -- Byte index
            report_busy     <= '0';
        elsif (report_start = '1') then
            -- Get ready to start new report.
            report_pidx     <= 0;
            report_bidx     <= 0;
            report_busy     <= '1';
        elsif (report_next = '1') then
            -- Move to next output byte.
            if (report_bidx < REPORT_BYTES-1) then
                report_bidx <= report_bidx + 1;
            elsif (report_pidx < PORT_COUNT-1) then
                report_bidx <= 0;
                report_pidx <= report_pidx + 1;
            else
                report_bidx <= 0;
                report_pidx <= 0;
                report_busy <= '0'; -- End of report
            end if;
        end if;
    end if;
end process;

-- One-word buffer for improved timing.
p_buff : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            buff_data   <= (others => '0');
            buff_last   <= '0';
            buff_valid  <= '0';
        elsif (report_next = '1') then
            buff_data   <= report_word(report_word'left-8*report_bidx
                                downto report_word'left-8*report_bidx-7);
            buff_last   <= bool2bit(report_bidx = REPORT_BYTES-1 and report_pidx = PORT_COUNT-1);
            buff_valid  <= '1';
        elsif (buff_ready = '1') then
            buff_valid  <= '0';
        end if;
    end if;
end process;

-- Auxiliary data is tapped before SLIP encoder.
aux_data <= buff_data;
aux_wr   <= buff_valid and buff_ready;

-- Optional SLIP encoding for output.
gen_slip1 : if SLIP_UART generate
    u_slip : entity work.slip_encoder
        port map(
        in_data     => buff_data,
        in_last     => buff_last,
        in_valid    => buff_valid,
        in_ready    => buff_ready,
        out_data    => enc_data,
        out_valid   => enc_valid,
        out_ready   => enc_ready,
        refclk      => refclk,
        reset_p     => reset_p);
end generate;

gen_slip0 : if not SLIP_UART generate
    enc_data    <= buff_data;
    enc_valid   <= buff_valid;
    buff_ready  <= enc_ready;
end generate;

-- UART interface.
u_uart : entity work.io_uart_tx
    port map(
    uart_txd    => uart_txd,
    tx_data     => enc_data,
    tx_valid    => enc_valid,
    tx_ready    => enc_ready,
    rate_div    => UART_CLKDIV,
    refclk      => refclk,
    reset_p     => reset_p);

end config_port_test;
