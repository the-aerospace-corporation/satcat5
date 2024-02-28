--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- A simple byte-by-byte SPI controller (clock output).
--
-- This block is an SPI controller that drives clock and data signals
-- for a remote SPI peripheral.  It can optionally accept input data
-- from that peripheral.
--
-- For more information on naming conventions, refer to:
-- https://www.oshwa.org/a-resolution-to-redefine-spi-signal-names/
--
-- The state machine generates SCK, CSB, and COPI, at a fixed baud rate.
-- All SPI clock-phase and clock-polarity modes are supported.  Chip-select
-- is automatically asserted (i.e., driven low) before each data byte, then
-- released after transfer of a byte with the "last" flag asserted.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.eth_frame_common.all;

entity io_spi_controller is
    port (
    -- Command stream
    cmd_data    : in  byte_t;
    cmd_last    : in  std_logic;
    cmd_valid   : in  std_logic;
    cmd_ready   : out std_logic;

    -- Received data (optional)
    rcvd_data   : out byte_t;
    rcvd_write  : out std_logic;

    -- SPI interface with output clock
    spi_csb     : out std_logic;        -- Chip select
    spi_sck     : out std_logic;        -- Serial clock out (SCK)
    spi_sdo     : out std_logic;        -- Serial data out (COPI)
    spi_sdi     : in  std_logic := '0'; -- Serial data in (CIPO, if present)

    -- Configuration interface.
    cfg_mode    : in  integer range 0 to 3;
    cfg_rate    : in  byte_u;           -- SPI_SCK = REF_CLK / 2N

    -- System interface
    ref_clk     : in  std_logic;        -- Reference clock
    reset_p     : in  std_logic);
end io_spi_controller;

architecture io_spi_controller of io_spi_controller is

-- Break down SPI mode index into CPOL and CPHA.
signal cpol, cpha   : std_logic;

-- Write signals
signal spi_csb_i    : std_logic := '1';
signal spi_sck_i    : std_logic := '0';
signal spi_sdo_i    : std_logic := '0';
signal spi_final    : std_logic := '1';
signal spi_ready    : std_logic := '1';
signal cmd_write    : std_logic;

-- Read signals
signal sync_sdi     : std_logic;
signal read_en      : std_logic := '0';
signal rcvd_data_i  : byte_t := (others => '0');
signal rcvd_write_i : std_logic := '0';

begin

-- Break down SPI mode index into CPOL and CPHA.
cpol <= bool2bit(cfg_mode = 2 or cfg_mode = 3);
cpha <= bool2bit(cfg_mode = 1 or cfg_mode = 3);

-- Synchronize the input signal
u_ibuf : sync_buffer
    port map(
    in_flag  => spi_sdi,
    out_flag => sync_sdi,
    out_clk  => ref_clk);

-- Drive all output signals.
spi_csb <= spi_csb_i;
spi_sck <= spi_sck_i xor cpol;
spi_sdo <= spi_sdo_i;

rcvd_data   <= rcvd_data_i;
rcvd_write  <= rcvd_write_i;

-- Upstream flow control.
cmd_ready <= spi_ready;
cmd_write <= spi_ready and cmd_valid;

-- Main SPI state machine.
p_spi : process(ref_clk)
    -- Which half-bit should sample the CIPO signal?
    function bit_read(cpha : std_logic; bc : integer) return boolean is
        variable bc2 : integer := bc mod 2;
    begin
        if (cpha = '0') then
            return (bc2 = 0);
        else
            return (bc < 17 and bc2 = 1);
        end if;
    end function;

    -- Which half-bit phases result in data changes?
    function bit_change(cpha : std_logic; bc : integer) return boolean is
        variable bc2 : integer := bc mod 2;
    begin
        if (cpha = '0') then
            return (bc > 2 and bc2 = 0);
        else
            return (bc > 1 and bc < 17 and bc2 = 1);
        end if;
    end function;

    -- Local state.
    variable out_sreg   : byte_t := (others => '0');
    variable bit_count  : integer range 0 to 17 := 0;
    variable clk_count  : byte_u := (others => '0');
begin
    if rising_edge(ref_clk) then
        -- Sanity check on rate-divider setting.
        assert (reset_p = '1' or cfg_rate /= 0)
            report "Invalid rate-divider setting." severity error;

        -- Upstream flow control.
        if (cmd_write = '1' or clk_count > 1) then
            -- Force low while we handle the current bit.
            spi_ready <= '0';
        elsif (spi_final = '0') then
            -- Normal byte --> stop at B=2 or B=1, depending on CPHA.
            spi_ready <= bool2bit(cpha = '0' and bit_count = 2)
                      or bool2bit(cpha = '1' and bit_count = 1);
        else
            -- Final byte --> stop once fully idle.
            spi_ready <= bool2bit(bit_count = 0);
        end if;

        -- Determine the sample time for the CIPO signal.
        read_en <= bool2bit(clk_count = 1 and bit_read(cpha, bit_count));

        -- Data signal (COPI) is a simple shift register.
        if (cmd_write = '1') then
            out_sreg := cmd_data;
        elsif ((clk_count = 0) and bit_change(cpha, bit_count)) then
            out_sreg := out_sreg(6 downto 0) & '0';
        end if;
        spi_sdo_i <= out_sreg(7);       -- MSB first

        -- Simple state machine for CSB.
        if (reset_p = '1') then
            spi_csb_i <= '1';  -- Reset = Idle
            spi_final <= '1';
        elsif (cmd_write = '1') then
            spi_csb_i <= '0';  -- Start of any byte
            spi_final <= cmd_last;
        elsif (bit_count = 1 and clk_count = 0 and spi_final = '1') then
            spi_csb_i <= '1';  -- End of transaction
        end if;

        -- Update CLK and counter state.
        if (reset_p = '1') then
            -- Global reset = Idle
            spi_sck_i   <= '0';
            bit_count   := 0;
            clk_count   := (others => '0');
        elsif (cmd_write = '1') then
            -- Start of next byte.
            clk_count   := cfg_rate - 1;
            if (cpha = '1' and spi_final = '0') then
                spi_sck_i <= '1';
                bit_count := 16;    -- Continued byte if CPHA = 1
            else
                spi_sck_i <= '0';
                bit_count := 17;    -- All other cases
            end if;
        elsif (clk_count > 0) then
            -- Countdown to next half-bit transition
            clk_count   := clk_count - 1;
        elsif (spi_final = '1' and bit_count > 0) then
            -- Final byte --> Countdown to zero.
            if (bit_count > 1) then
                spi_sck_i <= not spi_sck_i;
            end if;
            bit_count   := bit_count - 1;
            clk_count   := cfg_rate - 1;
        elsif ((cpha = '0' and bit_count > 2)
            or (cpha = '1' and bit_count > 1)) then
            -- Normal byte --> Stop at B=2 or B=1, depending on CPHA.
            spi_sck_i   <= not spi_sck_i;
            bit_count   := bit_count - 1;
            clk_count   := cfg_rate - 1;
        end if;
    end if;
end process;

-- Auxliary state machine for reads.
p_read : process(ref_clk)
    variable bit_count : integer range 0 to 7 := 7;
begin
    if rising_edge(ref_clk) then
        -- Simple shift register, MSB first.
        if (read_en = '1') then
            rcvd_data_i <= rcvd_data_i(6 downto 0) & sync_sdi;
        end if;

        -- Count down to the end of each byte.
        rcvd_write_i <= read_en and bool2bit(bit_count = 0);
        if (cmd_write = '1' and spi_csb_i = '1') then
            bit_count := 7; -- Start of a new transaction
        elsif (read_en = '1') then
            if (bit_count > 0) then
                bit_count := bit_count - 1;
            else
                bit_count := 7;
            end if;
        end if;
    end if;
end process;

end io_spi_controller;
