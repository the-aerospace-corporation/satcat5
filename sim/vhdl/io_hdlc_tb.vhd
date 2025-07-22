--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the HDLC interface blocks (Tx, Rx)
--
-- This testbench connects the transmit and receive HDLCs back-to-back, to
-- confirm successful communication at different baud rates. The u_ref FIFO is
-- used to apply backpressure to the Tx block. When u_ref is half full, the Tx
-- block will finish outputting the current frame, then stop until fifo_hfull
-- is deasserted.
--
-- The complete test takes 200 microseconds.
--

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.common_functions.log2_ceil;
use work.common_functions.U2I;
use work.eth_frame_common.byte_t;
use work.router_sim_tools.all;

entity io_hdlc_tb is
    -- Unit test has no top-level I/o.
end io_hdlc_tb;

architecture tb of io_hdlc_tb is

constant REF_DEPTH_LOG2 : positive := 7;

constant FRAME_BYTES   : natural   := 0;     -- Variable width frame size
constant MSB_FIRST     : boolean   := false; -- lsb first
constant RATE_WIDTH    : positive  := 8;
constant BUFFER_KBYTES : positive  := 2;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Tx and Rx streams.
signal tx_data      : byte_t    := (others => 'X');
signal tx_valid     : std_logic := '0';
signal tx_last      : std_logic := '0';
signal tx_ready     : std_logic;

signal rx_data      : byte_t;
signal rx_write     : std_logic;
signal rx_last      : std_logic;

-- Other test and control signals.
signal hdlc_clk   : std_logic;
signal hdlc_data  : std_logic;
signal hdlc_ready : std_logic := '0';

signal rate_div   : unsigned(RATE_WIDTH-1 downto 0) := (others => '1');
signal ref_data   : byte_t;
signal ref_wren   : std_logic;
signal ref_valid  : std_logic;
signal ref_hfull  : std_logic;
signal ref_empty  : std_logic;
signal test_index : natural := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- FIFO for reference data
ref_wren <= tx_valid and tx_ready;

u_ref : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH   => 8,
    DEPTH_LOG2 => REF_DEPTH_LOG2)
    port map(
    in_data    => tx_data,
    in_write   => ref_wren,
    out_data   => ref_data,
    out_valid  => ref_valid,
    out_read   => rx_write,
    fifo_hfull => ref_hfull,
    fifo_empty => ref_empty,
    clk        => clk_100,
    reset_p    => reset_p);

hdlc_ready <= not ref_hfull;

-- Unit under test.
uut_tx : entity work.io_hdlc_tx
    generic map (
    FRAME_BYTES => FRAME_BYTES,
    MSB_FIRST   => MSB_FIRST,
    RATE_WIDTH  => RATE_WIDTH)
    port map(
    hdlc_clk   => hdlc_clk,
    hdlc_data  => hdlc_data,
    hdlc_ready => hdlc_ready,
    tx_data    => tx_data,
    tx_last    => tx_last,
    tx_valid   => tx_valid,
    tx_ready   => tx_ready,
    rate_div   => rate_div,
    refclk     => clk_100,
    reset_p    => reset_p);

uut_rx : entity work.io_hdlc_rx
    generic map(
    BUFFER_KBYTES => BUFFER_KBYTES,
    MSB_FIRST     => MSB_FIRST)
    port map(
    hdlc_clk  => hdlc_clk,
    hdlc_data => hdlc_data,
    rx_data   => rx_data,
    rx_write  => rx_write,
    rx_last   => rx_last,
    refclk    => clk_100,
    reset_p   => reset_p);

-- Check received data against reference stream.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (ref_valid = '0') then
            assert (rx_write = '0') report "DATA unexpected" severity error;
        elsif (rx_write = '1') then
            assert (rx_data = ref_data) report "DATA mismatch: "
                & integer'image(U2I(rx_data)) & " != "
                & integer'image(U2I(ref_data)) severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Transmit a few bytes at the current baud rate.
    procedure test_one(data: std_logic_vector) is
        variable tx_len  : natural := data'length / 8;
        variable tx_idx  : natural := 0;
    begin
        -- Check data will fit in ref fifo
        assert (tx_len < (2**REF_DEPTH_LOG2)) report "Ref FIFO too small."
            severity error;

        -- Update the test index.
        report "Starting test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;

        -- Transmit each byte in the sequence, with a parallel state machine.
        wait until rising_edge(clk_100);
        while (tx_idx < tx_len) loop
            -- Transmit stream flow-control.
            if (tx_valid = '0' or tx_ready = '1') then
                tx_data  <= get_packet_bytes(data, tx_idx, 1);
                tx_valid <= '1';
                if (tx_idx = tx_len - 1) then
                    tx_last <= '1';
                end if;
                tx_idx   := tx_idx + 1;
            end if;

            wait until rising_edge(clk_100);
        end loop;

        wait until (tx_ready = '1');
        wait until rising_edge(clk_100);
        tx_valid <= '0';
        tx_last  <= '0';
    end procedure;

    -- Run a sequence of tests at the specified rate divider.
    procedure run_all(rate : positive) is
        constant almost_full : integer := 2**REF_DEPTH_LOG2 - 1;
        constant half_full   : integer := 2**REF_DEPTH_LOG2/2;
    begin
        -- Set the baud-rate for this series of tests.
        rate_div <= to_unsigned(rate, RATE_WIDTH);
        -- Run a few basic tests with data only.
        test_one(rand_bytes(almost_full));
        test_one(rand_bytes(half_full));
        wait until (ref_empty = '1');
    end procedure;

begin
    -- Drive all signals controlled by this process.
    rate_div    <= (others => '1');
    tx_data     <= (others => 'X');
    tx_valid    <= '0';
    wait until reset_p = '0';
    wait for 1 us;

    -- Repeat the test series at different baud rates.
    run_all(2);
    run_all(10);

    report "All tests completed!";
    wait;
end process;

end tb;
