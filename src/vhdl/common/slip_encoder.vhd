--------------------------------------------------------------------------
-- Copyright 2019-2020 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SLIP ENCODER
--
--  This modules takes in a byte of data and outputs a byte or bytes
--  of data corresponding to the Serial Line Internet Protocol
--  encoding. These bytes will be transmitted serially over the UART
--  or SPI.
--
--  SLIP Encoding includes END and ESC bytes (0xC0 and 0xDB) that
--  indicate the last byte in a series of bytes. Therefore, the
--  encoder takes in a "last" bit along with the data.
--
--  Data transfer occurs on valid and ready signals.
--  o in_write valid means data is available for the encoder.
--  o in_ready means that the interface is ready to accept encoded data.
--  o out_ready means that the encoder is ready to accept new data.
--  o out_valid means that the encoder has encoded data available
--    to send to the serial interface.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity slip_encoder is
    generic (
    START_TOKEN : std_logic := '1');    -- Emit END token on startup?
    port (
    in_data     : in  byte_t;
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    out_data    : out byte_t;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    refclk      : in  std_logic;
    reset_p     : in  std_logic);
end slip_encoder;

architecture slip_encoder of slip_encoder is

-- Encoder signals
signal rem_bytes    : integer range 0 to 3 := 0;
signal out_data_i   : byte_t := SLIP_FEND;
signal out_next     : byte_t := SLIP_FEND;

begin

-- Upstream and downstream flow control
in_ready  <= bool2bit(rem_bytes = 0);
out_valid <= bool2bit(rem_bytes > 0);
out_data  <= out_data_i;

-- Main state machine
p_enc : process(refclk)
    function one_if(last : std_logic) return integer is
    begin
        if (last = '1') then
            return 1;
        else
            return 0;
        end if;
    end function;
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            -- Port reset
            rem_bytes   <= one_if(START_TOKEN);
            out_data_i  <= SLIP_FEND;
            out_next    <= SLIP_FEND;
        elsif (rem_bytes > 0) then
            -- Continue with previous output.
            if (out_ready = '1') then
                -- Drive next output byte when requested.
                out_data_i <= out_next;
                out_next   <= SLIP_FEND;
                rem_bytes  <= rem_bytes - 1;
            end if;
        elsif (in_valid = '1') then
            -- Start of new byte, escape/encode as needed.
            if (in_data = SLIP_FEND) then
                -- Escape for FEND in input.
                out_data_i  <= SLIP_ESC;
                out_next    <= SLIP_ESC_END;
                rem_bytes   <= 2 + one_if(in_last);
            elsif (in_data = SLIP_ESC) then
                -- Escape for ESC in input.
                out_data_i  <= SLIP_ESC;
                out_next    <= SLIP_ESC_ESC;
                rem_bytes   <= 2 + one_if(in_last);
            else
                -- Regular character.
                out_data_i  <= in_data;
                out_next    <= SLIP_FEND;
                rem_bytes   <= 1 + one_if(in_last);
            end if;
        end if;
    end if;
end process;

end slip_encoder;
