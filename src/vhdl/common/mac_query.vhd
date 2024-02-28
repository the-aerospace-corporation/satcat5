--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus interface for manual read/write of the MAC-lookup table
--
-- This block uses a pair of ConfigBus registers to provide software
-- access to the contents of the MAC-lookup table, as well as opcodes
-- to clear the table and enable/disable specific modes.  It includes
-- all required clock-crossing logic.
--
-- To read a value from the lookup table:
--  * Read REGADDR_QUERY_CTRL until OPCODE is zero (idle).
--  * Write the table-index and opcode 0x01 to REGADDR_QUERY_CTRL.
--  * Read REGADDR_QUERY_CTRL until OPCODE is zero (done).
--    (Port-index will replace the "argument" field.)
--  * Read reported MAC address from REGADDR_QUERY_MAC_MSB and _LSB.
--    A value of FF:FF:FF:FF:FF:FF indicates the entry was empty.
--
-- To write a new value to the lookup table:
--  * Read REGADDR_QUERY_CTRL until OPCODE is zero (idle).
--  * Write the 32 LSBs of the MAC address to REGADDR_QUERY_MAC_LSB.
--  * Write the 16 MSBs of the MAC address to REGADDR_QUERY_MAC_MSB.
--  * Write the port-index and opcode 0x02 to REGADDR_QUERY_CTRL.
--  * Read REGADDR_QUERY_CTRL until OPCODE is zero (DONE).
--
-- The full register definitions are as follows:
--  * REGADDR_QUERY_MAC_LSB (Read/Write):
--      Bits 31-00: 32 LSBs of MAC address
--  * REGADDR_QUERY_MAC_MSB (Read/Write):
--      Bits 15-00: 16 MSBs of MAC address
--      Bits 31-16: Reserved (write zeros)
--  * REGADDR_QUERY_CTRL (Read/Write):
--      Bits 15-00: Argument / Response (see below)
--      Bits 23-16: Reserved (write zeros)
--      Bits 31-24: Opcode
--          0x00: No-op / Idle / Done
--          0x01: Read table entry (Arg = Table index, Rep = Port index)
--          0x02: Write MAC address to table (Arg = Port index)
--          0x03: Clear table contents (Arg = Ignored)
--          0x04: Set learning mode (Arg = 1 enable, 0 disable)
--          (All other opcodes reserved)
--      Writes to this register execute the designated operation:
--      Reads will echo the opcode if busy, zero if done/idle.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity mac_query is
    generic (
    DEV_ADDR    : integer;      -- Device address for mac_core
    PORT_COUNT  : positive;     -- Number of Ethernet ports
    TABLE_SIZE  : positive);    -- Max cached MAC addresses
    port (
    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- General configuration.
    mac_clk     : in  std_logic;
    mac_clear   : out std_logic;
    mac_learn   : out std_logic;

    -- Manual read from table contents.
    read_index  : out integer range 0 to TABLE_SIZE-1;
    read_valid  : out std_logic;
    read_ready  : in  std_logic;
    read_addr   : in  mac_addr_t;
    read_psrc   : in  integer range 0 to PORT_COUNT-1;

    -- Manual write to table contents.
    write_addr  : out mac_addr_t;
    write_psrc  : out integer range 0 to PORT_COUNT-1;
    write_valid : out std_logic;
    write_ready : in  std_logic);
end mac_query;

architecture mac_query of mac_query is

constant OPCODE_IDLE    : byte_t := x"00";
constant OPCODE_READ    : byte_t := x"01";
constant OPCODE_WRITE   : byte_t := x"02";
constant OPCODE_CLEAR   : byte_t := x"03";
constant OPCODE_LEARN   : byte_t := x"04";

-- ConfigBus interface and clock-domain transition.
signal cfg_ack_i        : cfgbus_ack := cfgbus_idle;
signal cfg_opcode       : byte_t := OPCODE_IDLE;
signal cfg_oparg        : unsigned(15 downto 0) := (others => '0');
signal cfg_macaddr      : mac_addr_t := (others => '0');
signal cfg_start_t      : std_logic := '0';     -- Toggle in ConfigBus domain
signal cfg_start_i      : std_logic;            -- Strobe in mac_clk domain
signal cfg_done_t       : std_logic := '0';     -- Toggle in mac_clk domain
signal cfg_done_c       : std_logic;            -- Strobe in ConfigBus domain

-- Control functions.
signal ctrl_reset       : std_logic;
signal mac_clear_i      : std_logic := '0';
signal mac_learn_i      : std_logic := '1';
signal read_index_i     : integer range 0 to TABLE_SIZE-1 := 0;
signal read_valid_i     : std_logic := '0';
signal write_psrc_i     : integer range 0 to PORT_COUNT-1 := 0;
signal write_valid_i    : std_logic := '0';

begin

-- Drive top-level outputs.
cfg_ack     <= cfg_ack_i;
mac_clear   <= mac_clear_i;
mac_learn   <= mac_learn_i;
read_index  <= read_index_i;
read_valid  <= read_valid_i;
write_addr  <= cfg_macaddr;
write_psrc  <= write_psrc_i;
write_valid <= write_valid_i;

-- ConfigBus clock domain:
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Update the OPCODE register, including clear when done.
        if (cfg_cmd.reset_p = '1' or cfg_done_c = '1') then
            cfg_opcode <= OPCODE_IDLE;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL) and cfg_cmd.wstrb(3) = '1') then
            cfg_opcode <= cfg_cmd.wdata(31 downto 24);
            cfg_start_t <= not cfg_start_t;
        end if;

        -- Update the MAC-address and argument registers.
        if (cfg_done_c = '1' and cfg_opcode = OPCODE_READ) then
            cfg_macaddr <= read_addr;
            cfg_oparg   <= to_unsigned(read_psrc, cfg_oparg'length);
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_LSB)) then
            for n in 31 downto 0 loop
                if (cfg_cmd.wstrb(n/8) = '1') then
                    cfg_macaddr(n) <= cfg_cmd.wdata(n);
                end if;
            end loop;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_MSB)) then
            for n in 15 downto 0 loop
                if (cfg_cmd.wstrb(n/8) = '1') then
                    cfg_macaddr(n+32) <= cfg_cmd.wdata(n);
                end if;
            end loop;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL)) then
            for n in 15 downto 0 loop
                if (cfg_cmd.wstrb(n/8) = '1') then
                    cfg_oparg(n) <= cfg_cmd.wdata(n);
                end if;
            end loop;
        end if;

        -- Register reads:
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_LSB)) then
            cfg_ack_i <= cfgbus_reply(cfg_macaddr(31 downto 0));
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_MSB)) then
            cfg_ack_i <= cfgbus_reply(x"0000" & cfg_macaddr(47 downto 32));
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL)) then
            cfg_ack_i <= cfgbus_reply(cfg_opcode & x"00" & std_logic_vector(cfg_oparg));
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

-- Clock domain transition
u_sync_start : sync_toggle2pulse
    port map(
    in_toggle   => cfg_start_t,
    out_strobe  => cfg_start_i,
    out_clk     => mac_clk);

u_sync_done : sync_toggle2pulse
    port map(
    in_toggle   => cfg_done_t,
    out_strobe  => cfg_done_c,
    out_clk     => cfg_cmd.clk);

u_sync_reset : sync_reset
    port map(
    in_reset_p  => cfg_cmd.reset_p,
    out_reset_p => ctrl_reset,
    out_clk     => mac_clk);

-- MAC-pipeline clock domain.
p_mac : process(mac_clk)
begin
    if rising_edge(mac_clk) then
        -- Send the "DONE" signal back to the ConfigBus domain.
        if (read_valid_i = '1' and read_ready = '1') then
            cfg_done_t <= not cfg_done_t;       -- Read completed
        elsif (write_valid_i = '1' and write_ready = '1') then
            cfg_done_t <= not cfg_done_t;       -- Write completed
        elsif (cfg_start_i = '1') then
            if (cfg_opcode = OPCODE_READ or cfg_opcode = OPCODE_WRITE) then
                null;                           -- Delayed response
            else
                cfg_done_t <= not cfg_done_t;   -- Finished immediately
            end if;
        end if;

        -- Update each of the AXI-style VALID flags.
        if (ctrl_reset = '1') then
            read_valid_i <= '0';    -- Global reset
        elsif (cfg_start_i = '1' and cfg_opcode = OPCODE_READ) then
            read_valid_i <= '1';    -- New read command
        elsif (read_ready = '1') then
            read_valid_i <= '0';    -- Command completed
        end if;

        if (ctrl_reset = '1') then
            write_valid_i <= '0';   -- Global reset
        elsif (cfg_start_i = '1' and cfg_opcode = OPCODE_WRITE) then
            write_valid_i <= '1';   -- New write command
        elsif (write_ready = '1') then
            write_valid_i <= '0';   -- Command completed
        end if;

        -- Latch new command arguments, if valid.
        mac_clear_i <= cfg_start_i and bool2bit(cfg_opcode = OPCODE_CLEAR);

        if (cfg_start_i = '1' and cfg_opcode = OPCODE_LEARN) then
            mac_learn_i <= cfg_oparg(0);
        end if;

        if (cfg_start_i = '1' and cfg_oparg < TABLE_SIZE) then
            read_index_i <= to_integer(cfg_oparg);
        end if;

        if (cfg_start_i = '1' and cfg_oparg < PORT_COUNT) then
            write_psrc_i <= to_integer(cfg_oparg);
        end if;
    end if;
end process;

end mac_query;
