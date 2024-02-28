--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic SPI interface with clock input
--
-- This module implements a generic four-wire SPI interface.  This variant
-- acts as an SPI peripheral, used when the remote device drives the clock.
--
-- To minimize required FPGA resources, the input clock is treated as a regular
-- signal, oversampled by the global reference clock.  (Typically 50-125 MHz vs.
-- ~10 Mbps max for a typical SPI interface.)  As a result, all inputs are
-- asynchronous and must use metastability buffers for safe operation.
--
-- For good signal integrity, the input clock should have sharp edges.  Slow
-- edges can lead to double-counting; byte-boundaries will be misaligned until
-- the next activation of chip-select.  (For this reason, we recommend cycling
-- chip-select occasionally.)  A glitch-prevention filter is included to help
-- mitigate double-clocking glitches; the configuration of this filter limits
-- the minimum ratio of REFCLK to SCLK:
--      GLITCH_DLY  Min clock ratio (REFCLK / SCLK)
--      0           ~3.5 (limited by clock-synchronization)
--      1           ~4.1 (default)
--      2           ~6.1
--
-- In both modes, the clock source sets the rate of data transmission.
-- If either end of the link does not currently have data to transmit,
-- it should repeatedly send the SLIP inter-frame token (0xC0).
--
-- Received data is written a byte at a time with no option for flow-control.
-- Transmit data uses an AXI-style valid/ready handshake.  HOWEVER, if a byte
-- is not ready in time then it will instead send the value set in IDLE_BYTE.
--
-- NOTE: Microsemi Libero/Polarfire does not allow both async and sync process  
-- on io input signal (sclk). so need to disable using SYNC_MODE parameter  
-- (set to true). Note that this will increase turnaround latency and reduce
-- max SPI rate of data transmission. Actual throughput numbers have not 
-- been analyzed in simulation yet.
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
-- See also: https://www.oshwa.org/a-resolution-to-redefine-spi-signal-names/
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.ddr_input;
use     work.eth_frame_common.byte_t;
use     work.eth_frame_common.byte_u;

entity io_spi_peripheral is
    generic (
    IDLE_BYTE   : byte_t := x"00";  -- Fixed pattern when idle
    OUT_REG     : boolean := true;  -- Enable register on SDO, SDT signals?
    SYNC_MODE   : boolean := false);-- Disable both sync and async process on sclk? 
    port (
    -- External SPI interface.
    spi_csb     : in  std_logic;    -- Chip-select bar
    spi_sclk    : in  std_logic;    -- Serial clock in (SCK)
    spi_sdi     : in  std_logic;    -- Serial data in (COPI)
    spi_sdo     : out std_logic;    -- Serial data out (CIPO)
    spi_sdt     : out std_logic;    -- Tristate signal for SDO (optional).

    -- Internal byte interface.
    tx_data     : in  byte_t;
    tx_valid    : in  std_logic;
    tx_ready    : out std_logic;
    rx_data     : out byte_t;
    rx_write    : out std_logic;

    -- Configuration interface
    cfg_mode    : in  integer range 0 to 3;
    cfg_gdly    : in  byte_u;       -- Glitch-delay filter

    -- Clock and reset
    refclk      : in  std_logic);   -- Reference clock (refclk >> spi_sck*)
end io_spi_peripheral;

architecture io_spi_peripheral of io_spi_peripheral is

-- Break down SPI mode index into CPOL and CPHA.
signal cpol, cpha, xor_mode : std_logic;

-- Buffered inputs, sclk delay, manipulatable output
signal sclk0, sclk1, sclk2  : std_logic;
signal xclk0, xclk1, xclk2  : std_logic;
signal xcsb, csb1, csb2     : std_logic;
signal rx1, rx2             : std_logic;
signal tx0, tx1, tx2        : std_logic := '0';
signal tmp_sdo, out_sdo     : std_logic := '0';
signal tmp_sdt, out_sdt     : std_logic := '1';

-- SPI Mode configurability
signal ptr_sample1  : std_logic := '0';
signal ptr_sample2  : std_logic := '0';
signal ptr_sample   : std_logic := '0';
signal ptr_change   : std_logic := '0';

-- Glitch-prevention filter.
signal glitch_ctr   : byte_u := (others => '0');

-- Transmit/Receive internal logic signals/registers
signal tx_rden      : std_logic := '0';
signal tx_next      : byte_t := IDLE_BYTE;
signal rx_sreg      : byte_t := IDLE_BYTE;
signal rx_wren      : std_logic := '0';
signal tx_delay     : std_logic := '0';

begin

-- Break down SPI mode index into CPOL and CPHA.
cpol <= bool2bit(cfg_mode = 2 or cfg_mode = 3);
cpha <= bool2bit(cfg_mode = 1 or cfg_mode = 3);
xor_mode <= cpol xor cpha;

-- Buffer asynchronous inputs.  Use of pipelined DDR input is functionally
-- equivalent to the usual double-flop method of synchronization, but it
-- also allows for more precise sampling of the received signal.
u_buf1: ddr_input
    port map (d_pin => spi_csb, clk => refclk, q_re => csb1, q_fe => csb2);
u_buf2: ddr_input
    port map (d_pin => spi_sdi, clk => refclk, q_re => rx1, q_fe => rx2);
u_buf3: ddr_input
    port map (d_pin => spi_sclk, clk => refclk, q_re => sclk1, q_fe => sclk2);

-- SPI Mode: Configure when the system should sample values (Rx):
--  o Sample on rising edge (modes 0, 3) --> XOR_MODE = 0
--  o Sample on falling edge (modes 1, 2) --> XOR_MODE = 1
-- Output (Tx) always changes on the opposite edge.
xcsb  <= csb1 or csb2;
xclk0 <= sclk0 xor xor_mode;    -- Delayed from previous cycle (earliest)
xclk1 <= sclk1 xor xor_mode;    -- DDR rising-edge (middle)
xclk2 <= sclk2 xor xor_mode;    -- DDR falling-edge (latest)
ptr_sample1 <= bool2bit(xclk0 = '0' and xclk1 = '1' and glitch_ctr = 0);
ptr_sample2 <= bool2bit(xclk1 = '0' and xclk2 = '1' and glitch_ctr = 0);
ptr_sample <= ptr_sample1 or ptr_sample2;
ptr_change <= bool2bit((xclk0 = '1' and xclk1 = '0' and glitch_ctr = 0)
                    or (xclk1 = '1' and xclk2 = '0' and glitch_ctr = 0));

-- Final output uses combinational logic on unsynchronized SCLK.
-- This allows substantially faster turnaround time at high baud rates.
-- This mixed sync/async logic should be safe since tx0/tx1/tx2 transitions
-- are structured (see below) and there is no feedback to internal state.
tmp_sdo <= tx0 when (ptr_change = '1') else 
           tx1 when (SYNC_MODE or spi_sclk = xor_mode) else tx2;
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

-- Glitch-prevention filter:
-- After any SCLK-change, ignore subsequent changes for next N refclk cycles.
-- This helps prevent accidental double-counting of a noisy clock edge.
p_glitch : process (refclk)
begin
    if rising_edge(refclk) then
        if (csb1 = '1' or csb2 = '1') then
            glitch_ctr <= (others => '0');  -- Reset / idle
        elsif (ptr_sample = '1' or ptr_change = '1') then
            glitch_ctr <= cfg_gdly;         -- Change event
        elsif (glitch_ctr > 0) then
            glitch_ctr <= glitch_ctr - 1;   -- Countdown
        end if;
    end if;
end process;

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
        -- tx0 = Sent during change events (updates after falling edge XCLK)
        --       (Earliest to change, typically 1 full bit ahead.)
        -- tx1 = Sent while XCLK = 0 (updates after rising edge XCLK)
        -- tx2 = Sent while XCLK = 1 (updates after falling edge XCLK)
        if (xcsb = '1') then
            tx2 <= tx_next(7);      -- MSB first
            if (cpha = '1') then
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
            tx1 <= tx_next(7);      -- MSB first
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
            tx_delay <= cpha;
        elsif (ptr_change = '1') then
            tx_delay <= '0';
        end if;
    end if;
end process;

end io_spi_peripheral;