--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Basic traffic-counting diagnostic for the MAC pipeline
--
-- This block counts frames as they enter the MAC pipeline, to provide
-- basic diagnostic statistics.  It can filter by a specific EtherType or
-- simply count all frames.
--
-- Control is through a single ConfigBus register:
--  1)  Write the desired filter mode:
--          0  = Any EtherType
--          1+ = Matching EtherType only
--  2)  Wait for the desired interval.
--  3)  Write to the control register again.
--      (This sets the filter mode for the next interval)
--  4)  Wait a few clock cycles
--  5)  Read from the register to report the number of matching
--      frames received during that interval.
--  6)  Repeat from Step 2 as needed.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity mac_counter is
    generic (
    DEV_ADDR    : integer;          -- ConfigBus device address
    REG_ADDR    : integer;          -- ConfigBus register address
    IO_BYTES    : positive);        -- Width of main data port
    port (
    -- Main input
    -- PSRC is the input port-index and must be held for the full frame.
    in_wcount   : in  mac_bcount_t;
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- Configuration interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end mac_counter;

architecture mac_counter of mac_counter is

constant ETYPE_ANY : mac_type_t := (others => '0');
subtype count_t is unsigned(23 downto 0);

signal pkt_etype    : mac_type_t := (others => '0');
signal pkt_rdy      : std_logic := '0';
signal pkt_match    : std_logic;
signal pkt_incr     : count_t;

signal cfg_word     : cfgbus_word;
signal cfg_etype    : mac_type_t;
signal cfg_write    : std_logic;

signal ctr_word     : cfgbus_word;
signal ctr_reg      : count_t := (others => '0');
signal ctr_temp     : count_t := (others => '0');

begin

-- Extract EtherType from incoming packets.
-- (Depending on bus width, this might happen in sequence or all at once.)
p_etype : process(clk)
begin
    if rising_edge(clk) then
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+0, in_wcount)) then
            pkt_etype(15 downto 8) <= strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+0, in_data);
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+1, in_wcount)) then
            pkt_etype(7 downto 0) <= strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+1, in_data);
            pkt_rdy <= not reset_p;
        else
            pkt_rdy <= '0';
        end if;
    end if;
end process;

-- EtherType filter and packet counter.
pkt_match <= pkt_rdy and bool2bit(cfg_etype = ETYPE_ANY or cfg_etype = pkt_etype);
pkt_incr  <= (0 => pkt_match, others => '0');

p_filter : process(clk)
begin
    if rising_edge(clk) then
        if (cfg_write = '1') then
            ctr_reg  <= ctr_temp;
            ctr_temp <= pkt_incr;
        elsif (pkt_rdy = '1') then
            ctr_temp <= ctr_temp + pkt_incr;
        end if;
    end if;
end process;

-- Type conversion
cfg_etype   <= cfg_word(MAC_TYPE_WIDTH-1 downto 0);
ctr_word    <= std_logic_vector(resize(ctr_reg, CFGBUS_WORD_SIZE));

-- ConfigBus register writes:
u_regwr : cfgbus_register_sync
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_ADDR,
    WR_ATOMIC   => true,
    WR_MASK     => cfgbus_mask_lsb(MAC_TYPE_WIDTH))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,
    sync_clk    => clk,
    sync_val    => cfg_word,
    sync_wr     => cfg_write);

-- ConfigBus register reads:
u_regrd : cfgbus_readonly
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_ADDR)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => ctr_word);

end mac_counter;
