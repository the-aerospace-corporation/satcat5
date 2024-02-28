--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Port Test / Packet Error Measurement Tool
--
-- This block tests the Port Test / Packet Error Measurement Tool by
-- connecting two ports in a back-to-back configuration.  It then
-- injects occasional bit errors and confirms that the correct number
-- of good and bad packets are reported.
--
-- The complete test takes just under 3.1 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity config_port_test_tb is
    generic (SLIP_UART : boolean := true);
    -- Unit testbench top level, no I/O ports
end config_port_test_tb;

architecture tb of config_port_test_tb is

-- Normally unit under test sends data once per second.
-- We lie about the clock rate to get a report every millisecond;
-- just make sure to adjust UART "baud rate" proportionally.
constant TEST_EVERY : positive := 100_000;
constant UART_CKDIV : positive := 10;

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Flow control randomization.
signal a2b_bitflip  : byte_t := (others => '0');
signal b2a_bitflip  : byte_t := (others => '0');
signal a2b_ready    : std_logic := '0';
signal b2a_ready    : std_logic := '0';

-- Loopback connection for the two ports.
signal rxa_data     : port_rx_m2s;
signal rxb_data     : port_rx_m2s;
signal txa_data     : port_tx_s2m;
signal txb_data     : port_tx_s2m;
signal txa_ctrl     : port_tx_m2s;
signal txb_ctrl     : port_tx_m2s;
signal uart_txd     : std_logic;

-- Reference counters.
signal refctr_a2b   : unsigned(31 downto 0) := (others => '0');
signal refctr_a2b0  : unsigned(31 downto 0) := (others => '0');
signal refctr_a2b1  : unsigned(31 downto 0) := (others => '0');
signal refctr_b2a   : unsigned(31 downto 0) := (others => '0');
signal refctr_b2a0  : unsigned(31 downto 0) := (others => '0');
signal refctr_b2a1  : unsigned(31 downto 0) := (others => '0');
signal ref_report   : unsigned(191 downto 0);

-- Receive UART and optional SLIP decoder.
signal raw_byte     : byte_t;
signal raw_write    : std_logic;

signal rx_report    : unsigned(191 downto 0) := (others => '0');
signal rx_byte      : byte_t;
signal rx_last      : std_logic;
signal rx_write     : std_logic;
signal rx_done      : std_logic := '0';

-- Test control.
signal test_index   : natural := 0;
signal test_done    : std_logic := '0';
signal rate_data    : real := 0.0;
signal rate_errs    : real := 0.0;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Flow control and error randomization.
p_flow : process(clk_100)
    variable seed1 : positive := 1871025;
    variable seed2 : positive := 6871041;
    variable rand  : real := 0.0;
begin
    if rising_edge(clk_100) then
        -- Fully random flow control on the READY signal.
        uniform(seed1, seed2, rand);
        a2b_ready <= bool2bit(rand < rate_data);
        uniform(seed1, seed2, rand);
        b2a_ready <= bool2bit(rand < rate_data);

        -- BITFLIP signal must change in sync with corresponding VALID strobe.
        if (a2b_ready = '1') then
            for n in a2b_bitflip'range loop
                uniform(seed1, seed2, rand);
                a2b_bitflip(n) <= bool2bit(rand < rate_errs);
            end loop;
        end if;
        if (b2a_ready = '1') then
            for n in b2a_bitflip'range loop
                uniform(seed1, seed2, rand);
                b2a_bitflip(n) <= bool2bit(rand < rate_errs);
            end loop;
        end if;
    end if;
end process;

-- Loopback connection for the two ports.
-- (Inverting RX clock prevents simulation artifacts.)
rxa_data.clk        <= not clk_100;
rxa_data.data       <= txb_data.data xor b2a_bitflip;
rxa_data.last       <= txb_data.last;
rxa_data.write      <= txb_data.valid and b2a_ready;
rxa_data.rxerr      <= '0';
rxa_data.reset_p    <= reset_p;
txa_ctrl.clk        <= clk_100;
txa_ctrl.ready      <= a2b_ready;
txa_ctrl.txerr      <= '0';
txa_ctrl.reset_p    <= reset_p;

rxb_data.clk        <= not clk_100;
rxb_data.data       <= txa_data.data xor a2b_bitflip;
rxb_data.last       <= txa_data.last;
rxb_data.write      <= txa_data.valid and a2b_ready;
rxb_data.rxerr      <= '0';
rxb_data.reset_p    <= reset_p;
txb_ctrl.clk        <= clk_100;
txb_ctrl.ready      <= b2a_ready;
txb_ctrl.txerr      <= '0';
txb_ctrl.reset_p    <= reset_p;

-- Unit under test.
uut : entity work.config_port_test
    generic map(
    BAUD_HZ     => TEST_EVERY / 10,
    CLKREF_HZ   => TEST_EVERY,
    ETYPE_TEST  => x"5C09",
    PORT_COUNT  => 2,
    SLIP_UART   => SLIP_UART)
    port map(
    -- Ports under test
    rx_data(0)  => rxa_data,
    rx_data(1)  => rxb_data,
    tx_data(0)  => txa_data,
    tx_data(1)  => txb_data,
    tx_ctrl(0)  => txa_ctrl,
    tx_ctrl(1)  => txb_ctrl,
    uart_txd    => uart_txd,
    refclk      => clk_100,
    reset_p     => reset_p);

-- Reference counters.
ref_report <= refctr_a2b & refctr_b2a0 & refctr_b2a1
            & refctr_b2a & refctr_a2b0 & refctr_a2b1;

refctr_a2b <= refctr_a2b0 + refctr_a2b1;
refctr_b2a <= refctr_b2a0 + refctr_b2a1;

u_refctr : process(clk_100)
    variable a_ok, b_ok : std_logic := '1';
begin
    if rising_edge(clk_100) then
        if (test_done = '1') then
            refctr_a2b1 <= (others => '0');
            refctr_a2b0 <= (others => '0');
        elsif (txa_data.valid = '1' and a2b_ready = '1') then
            if (or_reduce(a2b_bitflip) = '1') then
                -- A bit flip at any time invalidates the whole packet.
                a_ok := '0';    -- Clear packet-OK flag
            end if;
            if (txa_data.last = '1') then
                -- End of packet?
                refctr_a2b1 <= refctr_a2b1 + u2i(a_ok);
                refctr_a2b0 <= refctr_a2b0 + u2i(not a_ok);
                a_ok := '1';    -- Reset packet-OK flag.
            end if;
        end if;

        if (test_done = '1') then
            refctr_b2a1 <= (others => '0');
            refctr_b2a0 <= (others => '0');
        elsif (txb_data.valid = '1' and b2a_ready = '1') then
            if (or_reduce(b2a_bitflip) = '1') then
                -- A bit flip at any time invalidates the whole packet.
                b_ok := '0';    -- Clear packet-OK flag
            end if;
            if (txb_data.last = '1') then
                -- End of packet?
                refctr_b2a1 <= refctr_b2a1 + u2i(b_ok);
                refctr_b2a0 <= refctr_b2a0 + u2i(not b_ok);
                b_ok := '1';    -- Reset packet-OK flag.
            end if;
        end if;
    end if;
end process;

-- Receive UART, optional decoder, and shift-register.
u_uart : entity work.io_uart_rx
    port map(
    uart_rxd    => uart_txd,
    rx_data     => raw_byte,
    rx_write    => raw_write,
    rate_div    => to_unsigned(UART_CKDIV, 16),
    refclk      => clk_100,
    reset_p     => reset_p);

-- Optional SLIP decoder.
gen_slip1 : if SLIP_UART generate
    u_slip : entity work.slip_decoder
        port map(
        in_data     => raw_byte,
        in_write    => raw_write,
        out_data    => rx_byte,
        out_last    => rx_last,
        out_write   => rx_write,
        decode_err  => open,
        refclk      => clk_100,
        reset_p     => reset_p);
end generate;

gen_slip0 : if not SLIP_UART generate
    rx_byte  <= raw_byte;
    rx_write <= raw_write;
    rx_last  <= '0';
end generate;

-- Shift-register for received data.
p_sreg : process(clk_100)
    -- Count bytes to tell when we reach end.
    constant REPORT_LEN : integer := 24;
    variable rx_count : integer := 0;
begin
    if rising_edge(clk_100) then
        if (reset_p = '1') then
            rx_report <= (others => '0');
            rx_done   <= '0';
            rx_count  := 0;
        elsif (rx_write = '1') then
            -- If SLIP mode is enabled, verify "last" strobe.
            if (SLIP_UART and rx_count = REPORT_LEN-1) then
                assert (rx_last = '1')
                    report "Missing LAST" severity error;
            else
                assert (rx_last = '0')
                    report "Unexpected LAST" severity error;
            end if;
            -- Read in each byte, MSW-first.
            rx_report <= rx_report(183 downto 0) & unsigned(rx_byte);
            rx_done   <= bool2bit(rx_count = REPORT_LEN-1);
            rx_count  := (rx_count + 1) mod REPORT_LEN;
        end if;
    end if;
end process;

-- Test control.
p_test : process
    procedure run_test(rd, re : real) is
    begin
        -- Set test conditions and run for a while.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        rate_data   <= rd;
        rate_errs   <= re;
        wait for 900 us;

        -- Before the report starts, pause data to flush all pipelines.
        rate_data   <= 0.0;
        wait until rising_edge(rx_done);

        -- Confirm report contents.
        assert (ref_report = rx_report)
            report "Report mismatch" severity error;

        -- Clear counters for next time.
        wait until rising_edge(clk_100);
        test_done <= '1';
        wait until rising_edge(clk_100);
        test_done <= '0';
    end procedure;
begin
    test_index  <= 0;
    rate_data   <= 0.0;
    rate_errs   <= 0.0;
    wait until (reset_p = '0');
    wait for 1 us;

    run_test(1.0, 0.0);
    run_test(0.5, 0.0);
    run_test(0.5, 0.00001);
    report "All tests completed!";
    wait;
end process;

end tb;
