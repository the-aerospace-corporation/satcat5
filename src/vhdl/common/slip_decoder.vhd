--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SLIP DECODER
--
--  This module takes in a byte of data from the serial port (SPI
--  or UART) that is coded using the Serial Line Internet Protocol.
--  It then decodes the data, and writes the data and a "last" flag
--  to the data core.
--
--  SLIP Encoding includes END and ESC bytes (0xC0 and 0xDB) that
--  indicate the last byte in a series of bytes. Therefore, the
--  decoder scans for these bytes, and when it reads them, outputs
--  a "last" signal along with the data, decode_last.
--
--  Data transfer occurs on valid and ready signals.
--  o in_write means there is a new byte to be read in.
--  o the decoder must always be ready to accept this new data, since
--    the serial port cannot have a backlog of data.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity slip_decoder is
    generic(
    -- Optionally suppress output until the first valid FEND token.
    WAIT_LOCK   : boolean := true);
    port(
    -- Input signals
    in_data     : in  byte_t;
    in_write    : in  std_logic;

    -- Output signals
    out_data    : out byte_t;
    out_write   : out std_logic;
    out_last    : out std_logic;
    decode_err  : out std_logic;

    -- Clock & Reset
    reset_p     : in std_logic;
    refclk      : in std_logic);
end slip_decoder;

architecture slip_decoder of slip_decoder is

-- State from previously received bytes.
type decode_state_t is (DECODE_WAIT, DECODE_EMPTY, DECODE_DATA, DECODE_ESC);
function init_state return decode_state_t is
begin
    if (WAIT_LOCK) then
        return DECODE_WAIT;
    else
        return DECODE_EMPTY;
    end if;
end function;

signal dec_state    : decode_state_t := init_state;
signal dec_value    : byte_t := (others => '0');
signal dec_error    : std_logic := '0';

-- Delayed output (internal signals)
signal dly_data     : byte_t := (others => '0');
signal dly_write    : std_logic := '0';
signal dly_last     : std_logic := '0';

-- Sustain async error strobe for a few clock cycles.
signal err_dlyct    : unsigned(2 downto 0) := (others => '0');

begin

-- Drive block-level outputs.
out_data    <= dly_data;
out_write   <= dly_write;
out_last    <= dly_last;
decode_err  <= bool2bit(err_dlyct > 0);

p_decode : process(refclk)
    constant DONT_CARE : byte_t := (others => '-');
begin
    if rising_edge(refclk) then
        -- Set defaults for momentary strobes.
        dly_write   <= '0';
        dec_error   <= '0';

        -- Emit decoded values on a one-byte delay, so LAST is aligned.
        if (in_write = '1') then
            dly_data <= dec_value;      -- No reset required
            dly_last <= bool2bit(in_data = SLIP_FEND);
            if (reset_p = '0' and dec_state = DECODE_DATA) then
                dly_write <= '1';       -- Data is valid
            end if;
        end if;

        -- Decoded byte stream. (No reset required.)
        if (in_write = '1') then
            if (dec_state /= DECODE_ESC) then
                dec_value <= in_data;   -- Trivial case
            elsif (in_data = SLIP_ESC_END) then
                dec_value <= SLIP_FEND; -- Escaped EOF
            elsif (in_data = SLIP_ESC_ESC) then
                dec_value <= SLIP_ESC;  -- Escaped ESC
            else
                dec_value <= DONT_CARE;
                dec_error <= '1';       -- Invalid escape
            end if;
        end if;

        -- Update decoder state.
        if (reset_p = '1') then
            -- Global reset
            dec_state <= init_state;
        elsif (in_write = '1') then
            if (in_data = SLIP_FEND) then
                dec_state <= DECODE_EMPTY;  -- End of frame, revert to empty
            elsif (dec_state = DECODE_WAIT) then
                dec_state <= DECODE_WAIT;   -- Waiting for EOF token
            elsif (in_data = SLIP_ESC) then
                dec_state <= DECODE_ESC;    -- Escape character
            else
                dec_state <= DECODE_DATA;   -- Normal or escaped data
            end if;
        end if;

        -- Sustain async error strobe for a few clock cycles.
        if (reset_p = '1') then
            err_dlyct <= (others => '0');
        elsif (dec_error = '1') then
            err_dlyct <= (others => '1');
        elsif (err_dlyct > 0) then
            err_dlyct <= err_dlyct - 1;
        end if;
    end if;
end process;

end slip_decoder;
