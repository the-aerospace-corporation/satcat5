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
-- Generic SPI interface with clock input
--
-- This module implements a generic four-wire SPI interface.  This variant
-- acts as an SPI follower, used when the remote device drives the clock.
--
-- To minimize required FPGA resources, the input clock is treated as a regular
-- signal, oversampled by the global reference clock.  (Typically 50-125 MHz vs.
-- ~10 Mbps max for a typical SPI interface.)  As a result, all inputs are
-- asynchronous and must use metastability buffers for safe operation.
--
-- In both modes, the clock source sets the rate of data transmission.
-- If either end of the link does not currently have data to transmit,
-- it should repeatedly send the SLIP inter-frame token (0xC0).
--
-- Received data is written a byte at a time with no option for flow-control.
-- Transmit data uses an AXI-style valid/ready handshake.  HOWEVER, if a byte
-- is not ready in time then it will instead send the value set in IDLE_BYTE.
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
--
-- NOTE: Reference clock must be at least 3.0 times faster than sclk
--      because of the synchronization buffers, which delay sclk by two
--      cycles of the reference clock.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.synchronization.all;

entity io_spi_clkin is
    generic (
    IDLE_BYTE   : byte_t := x"00";  -- Fixed pattern when idle
    OUT_REG     : boolean := true;  -- Enable register on SDO, SDT signals?
    SPI_MODE    : integer := 3);    -- SPI clock phase & polarity
    port (
    -- External SPI interface.
    spi_csb     : in  std_logic;    -- Chip-select bar (from clock-source)
    spi_sclk    : in  std_logic;    -- Serial clock in (from clock-source)
    spi_sdi     : in  std_logic;    -- Serial data in (from clock-source)
    spi_sdo     : out std_logic;    -- Serial data out (to clock-source)
    spi_sdt     : out std_logic;    -- Tristate signal for SDO (optional).

    -- Internal byte interface.
    tx_data     : in  byte_t;
    tx_valid    : in  std_logic;
    tx_ready    : out std_logic;
    rx_data     : out byte_t;
    rx_write    : out std_logic;

    -- Clock and reset
    refclk      : in  std_logic);   -- Reference clock (refclk >> spi_sck*)
end io_spi_clkin;

architecture io_spi_clkin of io_spi_clkin is

-- Break down SPI mode index into CPOL and CPHA.
constant CPOL : std_logic := bool2bit(SPI_MODE = 2 or SPI_MODE = 3);
constant CPHA : std_logic := bool2bit(SPI_MODE = 1 or SPI_MODE = 3);
constant XOR_MODE : std_logic := CPOL xor CPHA;

-- Buffered inputs, sclk delay, manipulatable output
signal sclk0, sclk1, sclk2  : std_logic;
signal xclk0, xclk1, xclk2  : std_logic;
signal xcsb, csb1, csb2     : std_logic;
signal rx1, rx2             : std_logic;
signal tx0, tx1, tx2        : std_logic := '0';
signal tmp_sdo, tmp_sdt     : std_logic := '1';
signal out_sdo, out_sdt     : std_logic := '1';

-- SPI Mode configurability
signal ptr_sample1  : std_logic := '0';
signal ptr_sample2  : std_logic := '0';
signal ptr_sample   : std_logic := '0';
signal ptr_change   : std_logic := '0';

-- Transmit/Receive internal logic signals/registers
signal tx_rden      : std_logic := '0';
signal tx_next      : byte_t := IDLE_BYTE;
signal rx_sreg      : byte_t := IDLE_BYTE;
signal rx_wren      : std_logic := '0';
signal tx_delay     : std_logic := CPHA;

begin

-- Buffer asynchronous inputs.  Use of pipelined DDR input is functionally
-- equivalent to the usual double-flop method of synchronization, but it
-- also allows for more precise sampling of the received signal.
u_buf1: entity work.ddr_input
    port map (d_pin => spi_csb, clk => refclk, q_re => csb1, q_fe => csb2);
u_buf2: entity work.ddr_input
    port map (d_pin => spi_sdi, clk => refclk, q_re => rx1, q_fe => rx2);
u_buf3: entity work.ddr_input
    port map (d_pin => spi_sclk, clk => refclk, q_re => sclk1, q_fe => sclk2);

-- SPI Mode: Configure when the system should sample values (Rx):
--  o Sample on rising edge (modes 0, 3) --> XOR_MODE = 0
--  o Sample on falling edge (modes 1, 2) --> XOR_MODE = 1
-- Output (Tx) always changes on the opposite edge.
xcsb  <= csb1 or csb2;
xclk0 <= sclk0 xor XOR_MODE;    -- Delayed from previous cycle (earliest)
xclk1 <= sclk1 xor XOR_MODE;    -- DDR rising-edge (middle)
xclk2 <= sclk2 xor XOR_MODE;    -- DDR falling-edge (latest)
ptr_sample1 <= bool2bit(xclk0 = '0' and xclk1 = '1');
ptr_sample2 <= bool2bit(xclk1 = '0' and xclk2 = '1');
ptr_sample <= ptr_sample1 or ptr_sample2;
ptr_change <= bool2bit((xclk0 = '1' and xclk1 = '0')
                    or (xclk1 = '1' and xclk2 = '0'));

-- Final output uses combinational logic on unsynchronized SCLK.
-- This allows substantially faster turnaround time at high baud rates.
-- This mixed sync/async logic should be safe since tx0/tx1/tx2 transitions
-- are structured (see below) and there is no feedback to internal state.
tmp_sdo <= tx0 when (ptr_change = '1') else tx1 when (spi_sclk = XOR_MODE) else tx2;
tmp_sdt <= xcsb; -- '1' = Tristate / inactive, '0' = Drive / active

-- Optionally instantiate an output register for the SDO and SDT signals.
-- This prevents glitches but increases turnaround latency by 1/2 cycle.
gen_reg : if OUT_REG generate
    p_out : process(refclk)
    begin
        if falling_edge(refclk) then
            out_sdo <= tmp_sdo;
            out_sdt <= tmp_sdt;
        end if;
    end process;
end generate;

gen_noreg : if not OUT_REG generate
    out_sdo <= tmp_sdo;
    out_sdt <= tmp_sdt;
end generate;

-- Drive external copies of internal signals.
spi_sdo  <= out_sdo;
spi_sdt  <= out_sdt;
rx_data  <= rx_sreg;
rx_write <= rx_wren;
tx_ready <= tx_rden;

-- Replace transmit data with the SLIP idle token as needed.
tx_next <= tx_data when (tx_valid = '1') else IDLE_BYTE;

-- SPI state machine.
p_spi : process (refclk)
    variable tx_sreg : byte_t := IDLE_BYTE;
    variable is_data : std_logic := '0';
    variable bit_ctr : integer range 0 to 7 := 7;
begin
    if rising_edge(refclk) then
        --Delayed SCLK for edge-detection.
        sclk0 <= sclk2;

        -- Receive shift register (MSB-first).
        if (csb1 = '0' and ptr_sample1 = '1') then
            rx_sreg <= rx_sreg(6 downto 0) & rx1;
            rx_wren <= bool2bit(bit_ctr = 0);
        elsif (csb2 = '0' and ptr_sample2 = '1') then
            rx_sreg <= rx_sreg(6 downto 0) & rx2;
            rx_wren <= bool2bit(bit_ctr = 0);
        else
            rx_wren <= '0';
        end if;

        -- Update the 3-bit predicted transmit state in a rolling wave:
        -- tx0 = Sent during change events (updates after faling edge XCLK)
        --       (Earliest to change, typically 1 full bit ahead.)
        -- tx1 = Sent while XCLK = 0 (updates after rising edge XCLK)
        -- tx2 = Sent while XCLK = 1 (updates after falling edge XCLK)
        if (xcsb = '1') then
            tx2 <= tx_next(7);      -- MSB first
            if (CPHA = '1') then
                tx0 <= tx_next(7);  -- Repeat first bit
            else
                tx0 <= tx_next(6);  -- Ready for next bit
            end if;
        elsif (ptr_change = '1') then
            if (tx_delay = '0') then
                tx2 <= tx_sreg(7);  -- Current SREG bit
            end if;
            if (bit_ctr > 0) then
                tx0 <= tx_sreg(6);  -- Next SREG bit
            else
                tx0 <= tx_next(7);  -- Start of next byte
            end if;
        end if;

        if (xcsb = '1') then
            tx1 <= tx_next(7);  -- MSB first
        elsif (ptr_sample = '1') then
            if (bit_ctr > 0) then
                tx1 <= tx_sreg(6);  -- Next SREG bit
            else
                tx1 <= tx_next(7);  -- Start of next byte
            end if;
        end if;

        -- Consume input byte during transmission, so the next is ready in time
        -- for the predictive transmit logic (see above).
        tx_rden <= is_data and ptr_sample and bool2bit(bit_ctr = 3) and not xcsb;

        -- Update the transmit shift-register.
        if ((xcsb = '1') or (bit_ctr = 0 and ptr_sample = '1')) then
            -- Start of new byte, choose real data or placeholder.
            tx_sreg := tx_next;
            is_data := tx_valid;
            bit_ctr := 7;
        elsif (ptr_sample = '1') then
            -- Shift to next bit (MSB-first).
            tx_sreg := tx_sreg(6 downto 0) & '0';
            bit_ctr := bit_ctr - 1;
        end if;

        -- Half-cycle delay if CPHA = 1.
        if (xcsb = '1') then
            tx_delay <= CPHA;
        elsif (ptr_change = '1') then
            tx_delay <= '0';
        end if;
    end if;
end process;

end io_spi_clkin;
