--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet traffic generator
--
-- This block generates an endless stream of Ethernet frames filled with
-- pseudorandom data (PRBS ITU-T O.160, Section 5.6).  Frame parameters
-- (destination, source, EtherType, length) are fixed at build-time.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_traffic_src is
    generic (
    HDR_DST     : mac_addr_t;           -- Destination MAC
    HDR_SRC     : mac_addr_t;           -- Source MAC
    HDR_ETYPE   : mac_type_t;           -- EtherType
    FRM_NBYTES  : positive := 1000);    -- Payload bytes per frame
    port (
    -- Output stream.
    out_data    : out byte_t;
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Cross-clock toggle signal for each output frame.
    out_pkt_t   : out std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_traffic_src;

architecture eth_traffic_src of eth_traffic_src is

-- PRNG
subtype lfsr_word is std_logic_vector(22 downto 0);
signal prng_state   : lfsr_word := (others => '1');
signal prng_data    : byte_t := (others => '0');
signal prng_next    : std_logic := '0';

-- Framing and header insertion.
constant FRM_HEADER : std_logic_vector(111 downto 0) := HDR_DST & HDR_SRC & HDR_ETYPE;
signal frm_hcount   : integer range 0 to 14 := 14;
signal frm_bcount   : integer range 0 to FRM_NBYTES-1 := FRM_NBYTES-1;
signal frm_next     : std_logic := '0';

signal frm_data     : byte_t := (others => '0');
signal frm_last     : std_logic := '0';
signal frm_valid    : std_logic := '0';
signal frm_ready    : std_logic;
signal frm_end_t    : std_logic := '0';

begin

-- Pseudorandom number generator using a "leap-forward" LFSR.
-- See also: P.P. Chu and R.E. Jones, "Design Techniques of FPGA Based Random Number Generator"
prng_data <= not prng_state(7 downto 0);    -- PRBS 23 inverts output signal

p_prng : process(clk)
    -- Jump-ahead table for eight bits per clock, polynomial x^23+x^18+1
    type jump_table_t is array(22 downto 0) of lfsr_word;
    constant JUMP_TABLE : jump_table_t := (
        "00000000001000010000000", "00000000000100001000000", "00000000000010000100000",
        "00000000000001000010000", "00000000000000100001000", "00000000000000010000100",
        "00000000000000001000010", "00000000000000000100001", "10000000000000000000000",
        "01000000000000000000000", "00100000000000000000000", "00010000000000000000000",
        "00001000000000000000000", "00000100000000000000000", "00000010000000000000000",
        "00000001000000000000000", "00000000100000000000000", "00000000010000000000000",
        "00000000001000000000000", "00000000000100000000000", "00000000000010000000000",
        "00000000000001000000000", "00000000000000100000000");
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            prng_state <= (others => '1');
        elsif (prng_next = '1') then
            for n in prng_state'range loop
                prng_state(n) <= xor_reduce(prng_state and JUMP_TABLE(n));
            end loop;
        end if;
    end if;
end process;

-- Framing and header insertion.
out_pkt_t <= frm_end_t;
frm_next  <= frm_ready or not frm_valid;
prng_next <= frm_ready and bool2bit(frm_hcount = 0);

p_frm : process(clk)
begin
    if rising_edge(clk) then
        -- Byte-counting state machine.
        if (reset_p = '1') then
            frm_hcount <= 14;   -- 6 bytes DST + 6 bytes SRC + 2 bytes Etype
            frm_bcount <= FRM_NBYTES - 1;
        elsif (frm_next = '0') then
            null;               -- Flow control paused
        elsif (frm_hcount > 0) then
            frm_hcount <= frm_hcount - 1;
        elsif (frm_bcount > 0) then
            frm_bcount <= frm_bcount - 1;
        else
            frm_hcount <= 14;   -- Start of next frame
            frm_bcount <= FRM_NBYTES - 1;
        end if;

        -- Insert header, then pull remaining data from PRNG.
        if (reset_p = '1') then
            frm_data    <= (others => '0');
            frm_last    <= '0';
            frm_valid   <= '0';
        elsif (frm_next = '0') then
            null;               -- Flow control paused
        elsif (frm_hcount > 0) then
            frm_data    <= FRM_HEADER(8*frm_hcount-1 downto 8*frm_hcount-8);
            frm_last    <= '0';
            frm_valid   <= '1';
        else
            frm_data    <= prng_data;
            frm_last    <= bool2bit(frm_bcount = 0);
            frm_valid   <= '1';
        end if;

        -- Generate the new-packet toggle.
        if (frm_valid = '1' and frm_ready = '1' and frm_last = '1') then
            frm_end_t <= not frm_end_t;
        end if;
    end if;
end process;

-- Append checksum.
u_fcs : entity work.eth_frame_adjust
    generic map(
    APPEND_FCS  => true,
    STRIP_FCS   => false)
    port map(
    in_data     => frm_data,
    in_last     => frm_last,
    in_valid    => frm_valid,
    in_ready    => frm_ready,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

end eth_traffic_src;
