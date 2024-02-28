--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- MAC-layer packet prioritization based on EtherType
--
-- This block allows a ConfigBus host to designate a list of "high-priority"
-- EtherType values.  It then inspects the EtherType of each incoming packet
-- in order to classify it as high or low priority.  It is typically placed
-- alongside the "mac_lookup" block in the switch's shared datapath.
--
-- The search function uses a small TCAM as a lookup table.  Each entry in
-- this table is a contiguous range of EtherTypes, where the LSBs can be
-- treated as a wildcard.  The size of this table, set at build-time, sets
-- the maximum number contiguous ranges that can be loaded.
--
-- The ConfigBus control uses a single register:
--  Writes to this register set new table entries:
--  * Bits 31-24: Table index to be written (0 to TABLE_SIZE-1).
--  * Bits 23-16: Wildcard length (0 = Exact match, N = Ignore N LSBs)
--  * Bits 15-00: New high-priority EtherType or first in range.
--  Reads from this register report the build-time configuration:
--  * Bits 31-08: Reserved
--  * Bits 07-00: TABLE_SIZE
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.tcam_constants.all;

entity mac_priority is
    generic (
    DEVADDR     : integer;          -- ConfigBus device address
    REGADDR     : integer;          -- ConfigBus register address
    IO_BYTES    : positive;         -- Width of main data port
    TABLE_SIZE  : positive);        -- Max unique EtherTypes
    port (
    -- Main input (Ethernet frame) does not require flow-control.
    in_wcount   : in  mac_bcount_t;
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- Search result is the priority flag ('1' = High-priority)
    out_pri     : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;
    out_error   : out std_logic;

    -- Configuration interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    cfg_done    : out std_logic;    -- Optional (for testing)

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end mac_priority;

architecture mac_priority of mac_priority is

-- Safely convert std_logic_vector to integer, modulo max.
function safe_int(x: std_logic_vector; max: positive) return natural is
    constant y : unsigned(x'range) := unsigned(to_01_vec(x));
begin
    return to_integer(y) mod max;
end function;

-- Wrapper for calculating prefix-length from number of don't-care bits.
-- (The two widths should add up to the full 16-bit EtherType field.)
subtype plen_t is integer range 1 to MAC_TYPE_WIDTH;
function safe_plen(x: byte_t) return plen_t is
begin
    return MAC_TYPE_WIDTH - safe_int(x, MAC_TYPE_WIDTH);
end function;

-- Status word is a constant.
constant STATUS_WORD : cfgbus_word := i2s(TABLE_SIZE, 32);

-- Ethertype matching
signal pkt_etype    : mac_type_t := (others => '0');
signal pkt_rdy      : std_logic := '0';
signal tbl_found    : std_logic;
signal tbl_rdy      : std_logic;

-- ConfigBus interface
signal cfg_index    : integer range 0 to TABLE_SIZE-1 := 0;
signal cfg_plen     : plen_t := MAC_TYPE_WIDTH;
signal cfg_etype    : mac_type_t := (others => '0');
signal cfg_word     : cfgbus_word;
signal cfg_valid    : std_logic;
signal cfg_ready    : std_logic;
signal cfg_fifowr   : std_logic;

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

-- CAM table executes the search.
u_cam : entity work.tcam_core
    generic map(
    INPUT_WIDTH => MAC_TYPE_WIDTH,
    TABLE_SIZE  => TABLE_SIZE,
    REPL_MODE   => TCAM_REPL_WRAP,
    TCAM_MODE   => TCAM_MODE_SIMPLE)
    port map(
    in_data     => pkt_etype,
    in_next     => pkt_rdy,
    out_index   => open,
    out_found   => tbl_found,
    out_next    => tbl_rdy,
    cfg_index   => cfg_index,
    cfg_data    => cfg_etype,
    cfg_plen    => cfg_plen,
    cfg_valid   => cfg_valid,
    cfg_ready   => cfg_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Small FIFO for output flow-control.
u_fifo_tbl : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 1)
    port map(
    in_data(0)  => tbl_found,
    in_write    => tbl_rdy,
    out_data(0) => out_pri,
    out_valid   => out_valid,
    out_read    => out_ready,
    fifo_error  => out_error,
    clk         => clk,
    reset_p     => reset_p);

-- Cross-clock FIFO for configuration changes.
-- (Alternative is a single-word buffer, which is slightly smaller but
--  requires the upstream controller to wait ~100 clocks after each write.)
cfg_fifowr  <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR));

u_fifo_cfg : entity work.fifo_smol_async
    generic map(IO_WIDTH => 32)
    port map(
    in_clk      => cfg_cmd.clk,
    in_data     => cfg_cmd.wdata,
    in_valid    => cfg_fifowr,
    in_ready    => open,
    out_clk     => clk,
    out_data    => cfg_word,
    out_valid   => cfg_valid,
    out_ready   => cfg_ready,
    reset_p     => cfg_cmd.reset_p);

cfg_index   <= safe_int(cfg_word(31 downto 24), TABLE_SIZE);
cfg_plen    <= safe_plen(cfg_word(23 downto 16));
cfg_etype   <= cfg_word(15 downto 0);
cfg_done    <= not cfg_valid;

-- Report configuration metadata.
u_read_cfg : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => STATUS_WORD);

end mac_priority;
