--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet logging system (UART interface)
--
-- This testbench generates a series of simulated events and confirms
-- output stream is correct, even in the presence of collissions and
-- buffer overruns.
--
-- The complete test takes 1.3 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity mac_log_uart_tb is
    -- Testbench has no top-level I/O.
end mac_log_uart_tb;

architecture tb of mac_log_uart_tb is

constant CORE_CLK_HZ: positive := 100_000_000;
constant PORT_COUNT : positive := 4;
constant UART_BAUD  : integer := 10_000_000;
constant UART_CKDIV : unsigned(15 downto 0) :=
    to_unsigned(clocks_per_baud_uart(CORE_CLK_HZ, UART_BAUD), 16);

signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

signal mac_data     : log_meta_t := LOG_META_NULL;
signal mac_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal mac_dmask    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal mac_write    : std_logic := '0';
signal port_data    : log_meta_array(PORT_COUNT-1 downto 0) := (others => LOG_META_NULL);
signal port_write   : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');

signal uart_txd     : std_logic;
signal slip_data    : byte_t;
signal slip_read    : std_logic;
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_read     : std_logic;

signal test_done    : std_logic;

begin

-- Clock and reset generation.
clk100  <= not clk100 after 5.0 ns;
reset_p <= '0' after 1 us;

-- Unit under test.
uut : entity work.mac_log_uart
    generic map(
    UART_BAUD   => UART_BAUD,
    CORE_CLK_HZ => CORE_CLK_HZ,
    PORT_COUNT  => PORT_COUNT)
    port map(
    mac_data    => mac_data,
    mac_psrc    => mac_psrc,
    mac_dmask   => mac_dmask,
    mac_write   => mac_write,
    port_data   => port_data,
    port_write  => port_write,
    uart_txd    => uart_txd,
    core_clk    => clk100,
    reset_p     => reset_p);

-- Receive UART and SLIP decoder.
u_uart : entity work.io_uart_rx
    port map(
    uart_rxd    => uart_txd,
    rx_data     => slip_data,
    rx_write    => slip_read,
    rate_div    => UART_CKDIV,
    refclk      => clk100,
    reset_p     => reset_p);

u_slip : entity work.slip_decoder
    port map(
    in_data     => slip_data,
    in_write    => slip_read,
    out_data    => out_data,
    out_write   => out_read,
    out_last    => out_last,
    decode_err  => open,
    refclk      => clk100,
    reset_p     => reset_p);

-- Validation of the output stream.
u_check : entity work.mac_log_validate
    generic map(
    CORE_CLK_HZ => CORE_CLK_HZ,
    LEN_HISTORY => 256,
    OUT_BYTES   => 1,
    PORT_COUNT  => PORT_COUNT)
    port map(
    mac_data    => mac_data,
    mac_psrc    => mac_psrc,
    mac_dmask   => mac_dmask,
    mac_write   => mac_write,
    port_data   => port_data,
    port_write  => port_write,
    out_clk     => clk100,
    out_data    => out_data,
    out_last    => out_last,
    out_read    => out_read,
    test_done   => test_done,
    core_clk    => clk100,
    reset_p     => reset_p);

-- High-level test control.
p_test : process
    procedure log_idle is
    begin
        mac_data    <= LOG_META_NULL;
        mac_psrc    <= 0;
        mac_dmask   <= (others => '0');
        mac_write   <= '0';
        port_data   <= (others => LOG_META_NULL);
        port_write  <= (others => '0');
    end procedure;
        
    procedure log_wait(count: positive := 1) is
    begin
        for n in 1 to count loop
            wait until rising_edge(clk100) and (reset_p = '0');
            log_idle;
        end loop;
    end procedure;

    procedure mac_keep(psrc: natural) is
    begin
        mac_data.dst_mac    <= rand_vec(MAC_ADDR_WIDTH);
        mac_data.src_mac    <= rand_vec(MAC_ADDR_WIDTH);
        mac_data.etype      <= rand_vec(MAC_TYPE_WIDTH);
        mac_data.vtag       <= rand_vec(VLAN_HDR_WIDTH);
        mac_data.reason     <= REASON_KEEP;
        mac_psrc            <= psrc;
        mac_dmask           <= (others => '1');
        mac_write           <= '1';
    end procedure;

    procedure mac_drop(psrc: natural) is
    begin
        mac_data.dst_mac    <= rand_vec(MAC_ADDR_WIDTH);
        mac_data.src_mac    <= rand_vec(MAC_ADDR_WIDTH);
        mac_data.etype      <= rand_vec(MAC_TYPE_WIDTH);
        mac_data.vtag       <= rand_vec(VLAN_HDR_WIDTH);
        mac_data.reason     <= rand_vec(REASON_WIDTH);
        mac_psrc            <= psrc;
        mac_dmask           <= (others => '0');
        mac_write           <= '1';
    end procedure;

    procedure port_drop(psrc: natural) is
    begin
        port_data(psrc).dst_mac <= rand_vec(MAC_ADDR_WIDTH);
        port_data(psrc).src_mac <= rand_vec(MAC_ADDR_WIDTH);
        port_data(psrc).etype   <= rand_vec(MAC_TYPE_WIDTH);
        port_data(psrc).vtag    <= rand_vec(VLAN_HDR_WIDTH);
        port_data(psrc).reason  <= rand_vec(REASON_WIDTH);
        port_write(psrc)        <= '1';
    end procedure;
begin
    log_idle; log_wait(32);

    report "Test #1: Consecutive packets.";
    for n in 1 to 5 loop
        mac_keep(rand_int(PORT_COUNT));
        log_wait(24);
        mac_drop(rand_int(PORT_COUNT));
        log_wait(23);
        port_drop(rand_int(PORT_COUNT));
        log_wait(25);
    end loop;
    wait until rising_edge(test_done);

    report "Test #2: Packet bursts.";
    for n in 1 to 5 loop
        mac_keep(rand_int(PORT_COUNT));
        port_drop(rand_int(PORT_COUNT));
        log_wait(1);
        port_drop(rand_int(PORT_COUNT));
        log_wait(100);
    end loop;
    mac_drop(rand_int(PORT_COUNT));
    log_wait(1);
    wait until rising_edge(test_done);

    report "Test #3: Fill output FIFO.";
    for n in 1 to 100 loop
        mac_keep(rand_int(PORT_COUNT));
        log_wait(30);
    end loop;
    wait until rising_edge(test_done);

    report "All tests completed!";
    wait;
end process;

end tb;
