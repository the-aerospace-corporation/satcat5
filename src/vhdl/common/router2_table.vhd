--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Combined routing table and ARP cache for the IPv4 router.
--
-- This block is a wrapper for the TCAM block, implementing next-hop and
-- final-hop routing indexed by destination IP address.  It combines the
-- functions of a static routing table and an address-resolution cache.
--
-- The static routing table uses classless inter-domain routing (CIDR)
-- to find the rule with the longest matching prefix.  (e.g., Matching
-- for wildcards like "192.168.1.*".)  The cache is used for final-hop
-- routing to a specific device on the LAN.  In both cases, the input
-- is the destination IP address, and the output is the next-hop MAC
-- address and port-number.
--
-- The block also provides a matched delay for additional metadata.  If
-- this input is connected, it will be propagated verbatim to the output.
--
-- Table contents are managed using a ConfigBus interface:
--  RT_ADDR_CIDR_DATA: Write only shift register
--      Write to this register three times to preload metadata.
--      1st write: Bits 31-24 = Prefix length (0-32)
--                 Bits 23-16 = Next-hop port number
--                 Bits 15-00 = Bits 47-32 of next-hop MAC
--      2nd write: Bits 31-00 = Bits 31-00 of next-hop MAC
--      3rd write: Bits 31-00 = IP address or subnet address
--  RT_ADDR_CIDR_CTRL: Read/write register
--      Read from this register to report status:
--          Bit  31    = Busy (1) or idle (0)
--          Bits 30-16 = Reserved
--          Bits 15-00 = Table size
--          Do not issue a "write" command while the busy flag is set.
--      Write to this register issue a command:
--          Bit  31-28 = Opcode
--              1 = Write one table row (data x 3, then ctrl)
--              2 = Write default route (data x 3, then ctrl)
--              3 = Clear table contents
--              (All other opcodes reserved.)
--          Bits 27-16 = Reserved (write zeros)
--          Bits 15-00 = Row index to update, if applicable
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.router2_common.all;
use     work.tcam_constants.all;

entity router2_table is
    generic (
    DEVADDR     : integer;          -- ConfigBus address
    TABLE_SIZE  : positive;         -- Number of table entries
    META_WIDTH  : positive := 1);   -- Metadata word size
    port (
    -- Input is the destination IP address, with optional metadata.
    in_dst_ip   : in  ip_addr_t;    -- Address to be searched
    in_next     : in  std_logic;    -- Enable strobe
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');

    -- Output reads the row with the longest matching prefix, if any.
    out_dst_ip  : out ip_addr_t;    -- Matched delay from input
    out_dst_idx : out unsigned(7 downto 0);
    out_dst_mac : out mac_addr_t;   -- Metadata from table
    out_found   : out std_logic;    -- Search found a match?
    out_next    : out std_logic;    -- Search result ready
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    tcam_error  : out std_logic;

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_table;

architecture router2_table of router2_table is

-- Opcodes for various commands.
subtype opcode_t is std_logic_vector(3 downto 0);
constant OPCODE_WRITE   : opcode_t := x"1";
constant OPCODE_DROUTE  : opcode_t := x"2";
constant OPCODE_CLEAR   : opcode_t := x"3";

-- Metadata for each row = MAC address (48 bits) + Port number (8 bits)
constant TABLE_WIDTH : integer := 48 + 8;
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype table_t is std_logic_vector(TABLE_WIDTH-1 downto 0);

-- TCAM output and default-route logic.
signal tcam_dst_ip  : ip_addr_t;
signal tcam_result  : table_t;
signal tcam_found   : std_logic;    -- Search result valid?
signal tcam_meta    : meta_t;
signal tcam_next    : std_logic;
signal def_route    : table_t := (others => '0');
signal def_write    : std_logic := '0';
signal out_result   : table_t := (others => '0');
signal out_dst_ip_i : ip_addr_t := (others => '0');
signal out_found_i  : std_logic := '0';
signal out_next_i   : std_logic := '0';
signal out_meta_i   : meta_t := (others => '0');

-- Command interface in the primary clock domain.
signal cfg_write    : std_logic;
signal cfg_clear1    : std_logic := '0';
signal cfg_clear2    : std_logic := '0';
signal cfg_clear3    : std_logic := '0';
signal cfg_clear    : std_logic := '0';
signal cfg_valid    : std_logic := '0';
signal cfg_ready    : std_logic;
signal cfg_index    : integer range 0 to TABLE_SIZE-1 := 0;
signal cfg_plen     : integer range 0 to ip_addr_t'length := 0;
signal cfg_search   : ip_addr_t := (others => '0');
signal cfg_result   : table_t := (others => '0');
signal cfg_plen_u   : unsigned(7 downto 0) := (others => '0');
signal cfg_done_t   : std_logic := '0';

-- Command interface in the ConfigBus clock domain.
signal cpu_clear_t  : std_logic := '0';
signal cpu_busy     : std_logic := '0';
signal cpu_done     : std_logic := '0';
signal cpu_index    : unsigned(15 downto 0) := (others => '0');
signal cpu_sreg     : std_logic_vector(95 downto 0) := (others => '0');
signal cpu_opcode   : opcode_t := (others => '0');
signal cpu_status   : cfgbus_word;
signal cfg_ack_i    : cfgbus_ack := cfgbus_idle;

begin

-- Instantiate the TCAM unit:
u_tcam : entity work.tcam_table
    generic map(
    IN_WIDTH    => ip_addr_t'length,
    META_WIDTH  => META_WIDTH,
    OUT_WIDTH   => TABLE_WIDTH,
    TABLE_SIZE  => TABLE_SIZE,
    REPL_MODE   => TCAM_REPL_WRAP,
    TCAM_MODE   => TCAM_MODE_MAXLEN)
    port map(
    in_search   => in_dst_ip,
    in_meta     => in_meta,
    in_next     => in_next,
    out_search  => tcam_dst_ip,
    out_result  => tcam_result,
    out_meta    => tcam_meta,
    out_found   => tcam_found,
    out_next    => tcam_next,
    out_error   => tcam_error,
    cfg_clear   => cfg_clear1,
    cfg_suggest => open,
    cfg_index   => cfg_index,
    cfg_plen    => cfg_plen,
    cfg_search  => cfg_search,
    cfg_result  => cfg_result,
    cfg_valid   => cfg_valid,
    cfg_ready   => cfg_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Output register and default route.
p_droute : process(clk)
begin
    if rising_edge(clk) then
        -- Use search result or revert to the default route?
        -- In either case, use the result only if the MAC address is valid.
        if (tcam_found = '1') then
            out_result  <= tcam_result;
            out_found_i <= or_reduce(tcam_result(47 downto 0));
        else
            out_result  <= def_route;
            out_found_i <= or_reduce(def_route(47 downto 0));
        end if;

        -- Matched delay for other output signals.
        out_dst_ip_i    <= tcam_dst_ip;
        out_meta_i      <= tcam_meta;
        out_next_i      <= tcam_next;
    end if;
end process;

out_dst_ip  <= out_dst_ip_i;
out_dst_idx <= unsigned(out_result(55 downto 48));
out_dst_mac <= out_result(47 downto 0);
out_found   <= out_found_i;
out_meta    <= out_meta_i;
out_next    <= out_next_i;

-- Command interface in the primary clock domain.
p_cfg : process(clk)
begin
    if rising_edge(clk) then
        -- Handle the clear command.
        cfg_clear2 <= cfg_write and bool2bit(cpu_opcode = OPCODE_CLEAR);

        -- Handle writes to individual rows.
        if (reset_p = '1') then
            cfg_valid <= '0';   -- System reset
        elsif (cfg_write = '1' and cpu_opcode = OPCODE_WRITE) then
            cfg_valid <= '1';   -- Start write
        elsif (cfg_ready = '1') then
            cfg_valid <= '0';   -- Finish write
        end if;

        -- Update the default-route.
        -- (It is enabled if the destination MAC address is non-zero.)
        if (cfg_write = '1' and cpu_opcode = OPCODE_DROUTE) then
            def_route <= cfg_result;
        elsif (cfg_write = '1' and cpu_opcode = OPCODE_CLEAR) then
            def_route <= (others => '0');
        elsif (reset_p = '1') then
            def_route <= (others => '0');
        end if;

        -- Bounds checks for integer parameters.
        if (cfg_write = '1') then
            if (cpu_index < TABLE_SIZE) then
                cfg_index <= to_integer(cpu_index);
            else
                report "Index out of bounds." severity error;
                cfg_index <= 0;
            end if;
            if (cfg_plen_u <= ip_addr_t'length) then
                cfg_plen <= to_integer(cfg_plen_u);
            else
                report "Prefix out of bounds." severity error;
                cfg_plen <= 0;
            end if;
        end if;

        -- Send the "done" signal depending on the opcode:
        if (cfg_valid = '1' and cfg_ready = '1') then
            cfg_done_t <= not cfg_done_t;   -- Write completed after a delay.
        elsif (cfg_write = '1' and cpu_opcode /= OPCODE_WRITE) then
            cfg_done_t <= not cfg_done_t;   -- Other opcodes execute immediately.
        end if;
    end if;
end process;

cfg_search <= cpu_sreg(31 downto 0);            -- Destination IP
cfg_result <= cpu_sreg(87 downto 32);           -- Port + MAC
cfg_plen_u <= unsigned(cpu_sreg(95 downto 88)); -- Prefix length

-- Clock domain transition.
u_sync_clear : sync_toggle2pulse
    port map(
    in_toggle   => cpu_clear_t,
    out_strobe  => cfg_clear3,
    out_clk     => clk);

u_sync_write : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => cpu_busy,
    out_strobe  => cfg_write,
    out_clk     => clk);

u_sync_done : sync_toggle2pulse
    port map(
    in_toggle   => cfg_done_t,
    out_strobe  => cpu_done,
    out_clk     => cfg_cmd.clk);

cfg_clear <= cfg_clear1 or cfg_clear2 or cfg_clear3;

-- Command interface in the ConfigBus clock domain.
p_cpu : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Handle writes to the shift-register.
        if (cfgbus_wrcmd(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA)) then
            cpu_sreg <= cpu_sreg(63 downto 0) & cfg_cmd.wdata;
        end if;

        -- Handle writes to the control register.
        if (cfg_cmd.reset_p = '1') then
            cpu_busy  <= '0';
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, RT_ADDR_CIDR_CTRL)) then
            assert (cpu_busy = '0')
                report "Unexpected write command" severity error;
            cpu_busy  <= '1';
            cpu_index <= unsigned(cfg_cmd.wdata(15 downto 0));
        elsif (cpu_done = '1') then
            cpu_busy  <= '0';
        end if;

        -- Reads from control register.
        if (cfgbus_rdcmd(cfg_cmd, DEVADDR, RT_ADDR_CIDR_CTRL)) then
            cfg_ack_i <= cfgbus_reply(cpu_status);
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

cpu_opcode <= cfg_cmd.wdata(31 downto 28);
cpu_status <= cpu_busy & i2s(TABLE_SIZE, 31);
cfg_ack    <= cfg_ack_i;

end router2_table;
