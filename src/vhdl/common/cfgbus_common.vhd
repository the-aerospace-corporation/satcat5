--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Package definition: Config-Bus memory map interface
--
-- This package defines the "Config-Bus" interface, which is a simple
-- memory-mapped interface for configuration registers.  This interface
-- is used for configuring a variety of SatCat5 systems.
--
-- The design is optimized for simplicity over throughput.  A single "host"
-- issues commands on a shared bus with up to 256 peripherals.  Responses
-- from all attached peripherals are OR'd together; this method is simpler
-- than a priority-encoder but requires that only one peripheral respond
-- to any read.  See also: "cfgbus_idle" and "cfgbus_reply".
--
-- Each peripheral may have up to 1024 registers of 32-bits each.
-- (This size matches 4 kiB cache-line sizes on many common processors,
--  and it's large enough to memory-map a complete Ethernet frame.)
--
-- Adapters from ConfigBus to other common interfaces (including AXI4 and
-- Ethernet network ports) are provided elsewhere.  This file defines the
-- core interface and related essential functions.
--
-- Other important notes:
--  * Commands are issued from a single host to any number of peripherals.
--  * Each register is a 32-bit word.
--      * Single-word reads are always atomic.
--      * Per-byte write-enables are optional.
--        Hosts should provide access to this feature when practical.
--        Peripherals may disregard this signal at their discretion.
--  * An "address" is a combination of an outer "device-address"
--    and an inner "register-address", together specifying a register.
--      * Hosts must present a specific device and register address to
--        attached peripherals.  (i.e., No wildcards, see below.)
--      * Hosts must provide means of accessing every register address (0-1023).
--      * Hosts should provide means of accessing multiple device addresses.
--        Where practical, use the maximum range 0-255.
--      * Peripherals may match each address field against specific
--        address(es) or against the reserved wildcard address (-1).
--        (See also: "cfgbus_match", "cfgbus_wrcmd", "cfgbus_rdcmd")
--      * Peripherals should provide a build-time device-address parameter,
--        so upstream users can control use of the overall address space.
--      * Peripherals that only require a small number of registers may
--        provide parameters to set those register-addresses, so that
--        multiple peripherals can share a single device-address.
--  * Some hosts may define an additional "system-address" field (0-4095).
--      * This brings the maximum addressable space up to 4 GiB.
--      * Hosts that do not use this field must drive it to constant zero.
--      * Most peripherals should disregard this field.
--  * Each register may be read-only, write-only, or read-write.
--  * Both reads and writes may have side-effects.
--      * Hosts must be configured so that read and write operations are
--        one-to-one for each 32-bit word.  (i.e., No cacheing, no prefetch)
--  * A single interrupt line is shared amongst all ConfigBus peripherals.
--  * All bus signals are synchronous to the provided clock.
--  * Peripherals must execute writes promptly.  (No flow-control is possible.)
--  * Round-trip read-to-acknowledge delay is variable.
--      * Only one transaction may be in-flight at any given time.
--      * Hosts may assume a reasonable timeout to recover from missing ACK.
--        (Refer to "cfgbus_timeout" for reference implementation.)
--      * Peripherals must acknowledge reads immediately on the next clock.
--      * Additional delays may be incurred on the command or reply path,
--        but should be kept to a minimum for acceptable throughput.
--  * Peripherals should minimize read latency.  Acknowledge (RDACK) can be
--    asserted on the same clock cycle as RDCMD, or on next clock cycle.
--  * Hosts should be able to tolerate additional delays on the reply path.
--
-- For usage examples, refer to "cfgbus_register" and "cfgbus_readonly".
-- These blocks can also be used for many common configuration-register tasks.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package cfgbus_common is
    -- Data is fixed at 32 bits.
    constant CFGBUS_WORD_SIZE : positive := 32;
    subtype cfgbus_word is std_logic_vector(31 downto 0);
    subtype cfgbus_wstrb is std_logic_vector(3 downto 0);

    -- Bit-mask functions: Set the N LSBs or MSBs
    function cfgbus_mask_lsb(n : natural) return cfgbus_word;
    function cfgbus_mask_msb(n : natural) return cfgbus_word;

    -- Max 256 peripheral devices, each 1024 words.
    -- Note: -1 acts as a wildcard for matching any address field.
    subtype cfgbus_sysaddr is integer range 0 to 4095;
    subtype cfgbus_devaddr is integer range 0 to 255;
    subtype cfgbus_regaddr is integer range 0 to 1023;
    constant CFGBUS_ADDR_ANY    : integer := -1;
    constant CFGBUS_ADDR_NONE   : integer := -2;

    -- Return device-address if enabled, CFGBUS_ADDR_NONE otherwise.
    function cfgbus_devaddr_if(
        devaddr : cfgbus_devaddr;
        enable  : boolean)
        return integer;

    -- Signals from the host to each peripheral.
    type cfgbus_cmd is record
        clk     : std_logic;        -- Interface clock
        sysaddr : cfgbus_sysaddr;   -- System address (optional)
        devaddr : cfgbus_devaddr;   -- Device/peripheral address
        regaddr : cfgbus_regaddr;   -- Register address
        wdata   : cfgbus_word;      -- Write data
        wstrb   : cfgbus_wstrb;     -- Per-byte write-enable (optional)
        wrcmd   : std_logic;        -- Write command strobe
        rdcmd   : std_logic;        -- Read command strobe
        reset_p : std_logic;        -- Synchronous reset
    end record;

    -- Signals from each peripheral to the host.
    type cfgbus_ack is record
        rdata   : cfgbus_word;      -- Read data
        rdack   : std_logic;        -- Read acknowledge strobe
        rderr   : std_logic;        -- Read error strobe (internal use only)
        irq     : std_logic;        -- Interrupt request (active-high, level-sensitive)
    end record;

    type cfgbus_ack_array is array(natural range<>) of cfgbus_ack;

    -- Should a register be enabled? (i.e., neither address is "none")
    function cfgbus_reg_enable(
        devaddr : integer;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean;

    -- Does an address match? (-1 = Wildcard)
    function cfgbus_match(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean;

    -- Wrappers for "cfgbus_match" plus WRCMD or RDCMD strobe.
    function cfgbus_wrcmd(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean;

    function cfgbus_rdcmd(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean;

    -- Null termination for unused command ports.
    constant CFGBUS_CMD_NULL : cfgbus_cmd := (
        clk     => '0',
        sysaddr => 0,
        devaddr => 0,
        regaddr => 0,
        wdata   => (others => '0'),
        wstrb   => (others => '0'),
        wrcmd   => '0',
        rdcmd   => '0',
        reset_p => '1');

    -- Useful shotcuts for constructing replies:
    function cfgbus_idle(
        irq     : std_logic := '0')
        return cfgbus_ack;

    function cfgbus_reply(
        data    : cfgbus_word;
        irq     : std_logic := '0')
        return cfgbus_ack;

    function cfgbus_error(
        irq     : std_logic := '0')
        return cfgbus_ack;

    -- Combine reply signals from multiple peripherals.
    function cfgbus_merge(ack_array : cfgbus_ack_array)
        return cfgbus_ack;

    function cfgbus_merge(ack1, ack2 : cfgbus_ack)
        return cfgbus_ack;

    -- Single-cycle delay buffer in each direction.
    -- (Useful when pipelining for better timing, etc.)
    component cfgbus_buffer is
        port (
        -- Interface to host
        host_cmd    : in  cfgbus_cmd;
        host_ack    : out cfgbus_ack;
        -- Buffered interface
        buff_cmd    : out cfgbus_cmd;
        buff_ack    : in  cfgbus_ack);
    end component;

    -- Timeout system for ConfigBus hosts.
    -- Asserts ERR strobe if no ACK within N clocks of RDCMD.
    -- Ensures exactly one ACK, ERR, or concurrent ACK+ERR for each RDCMD.
    -- The optional "host_wait" flag indicates RDCMD will not be accepted.
    component cfgbus_timeout is
        generic (
        RD_TIMEOUT  : positive := 16);
        port (
        -- Interface to host
        host_cmd    : in  cfgbus_cmd;
        host_ack    : out cfgbus_ack;
        host_wait   : out std_logic;
        host_error  : out std_logic;
        -- Interface to peripherals
        cfg_cmd     : out cfgbus_cmd;
        cfg_ack     : in  cfgbus_ack);
    end component;

    -- Simple read/writeable ConfigBus register.
    -- Optionally, WR_MASK = '0' makes specific bits constant.
    component cfgbus_register is
        generic (
        DEVADDR     : integer;          -- Peripheral address
        REGADDR     : integer := CFGBUS_ADDR_ANY;
        WR_ATOMIC   : boolean := false; -- Ignore per-byte write strobes?
        WR_MASK     : cfgbus_word := (others => '1');
        RSTVAL      : cfgbus_word := (others => '0'));
        port (
        -- ConfigBus interface
        cfg_cmd     : in  cfgbus_cmd;
        cfg_ack     : out cfgbus_ack;
        -- Local interface
        reg_val     : out cfgbus_word;  -- Register value
        -- Event indicators (optional)
        evt_wr_str  : out std_logic;    -- Strobe on write
        evt_wr_tog  : out std_logic;    -- Toggle on write
        evt_rd_str  : out std_logic;    -- Strobe on read
        evt_rd_tog  : out std_logic);   -- Toggle on read
    end component;

    -- Clock-crossing wrapper for cfgbus_register.
    -- Note: Register writes must be four cycles apart in both clock domains.
    component cfgbus_register_sync is
        generic (
        DEVADDR     : integer;          -- Peripheral address
        REGADDR     : integer := CFGBUS_ADDR_ANY;
        WR_ATOMIC   : boolean := false; -- Ignore per-byte strobes?
        WR_MASK     : cfgbus_word := (others => '1');
        RSTVAL      : cfgbus_word := (others => '0'));
        port (
        -- ConfigBus interface
        cfg_cmd     : in  cfgbus_cmd;
        cfg_ack     : out cfgbus_ack;
        -- Local interface
        sync_clk    : in  std_logic;    -- I/O reference clock
        sync_val    : out cfgbus_word;  -- Register value
        sync_wr     : out std_logic;    -- Strobe on write
        sync_rd     : out std_logic);   -- Strobe on read
    end component;

    -- Read-only ConfigBus register (e.g., for status indicators)
    component cfgbus_readonly is
        generic (
        DEVADDR     : integer;          -- Peripheral address
        REGADDR     : integer := CFGBUS_ADDR_ANY);
        port (
        -- ConfigBus interface
        cfg_cmd     : in  cfgbus_cmd;
        cfg_ack     : out cfgbus_ack;
        -- Local interface
        reg_val     : in  cfgbus_word;  -- Read-only value
        -- Event indicators (optional)
        evt_wr_str  : out std_logic;    -- Strobe on write
        evt_wr_tog  : out std_logic;    -- Toggle on write
        evt_rd_str  : out std_logic;    -- Strobe on read
        evt_rd_tog  : out std_logic);   -- Toggle on read
    end component;

    -- Clock-crossing wrapper for cfgbus_readonly.
    -- In AUTO_UPDATE mode, the input register is sampled at regular
    -- intervals.  Otherwise, it is sampled on each write event.
    -- (i.e., Write before read, to prevent "tearing".)
    component cfgbus_readonly_sync is
        generic (
        DEVADDR     : integer;          -- Peripheral address
        REGADDR     : integer := CFGBUS_ADDR_ANY;
        AUTO_UPDATE : boolean := true); -- Automatically sample input?
        port (
        -- ConfigBus interface
        cfg_cmd     : in  cfgbus_cmd;
        cfg_ack     : out cfgbus_ack;
        -- Local interface
        sync_clk    : in  std_logic;    -- I/O reference clock
        sync_val    : in  cfgbus_word;  -- Read-only value
        sync_wr     : out std_logic;    -- Strobe on write
        sync_rd     : out std_logic);   -- Strobe on read
    end component;

    -- Interrupt controller using a single register.
    --
    -- An external event (flag or toggle) raises the "service-requested"
    -- flag.  Writing any value to the register clears this flag.
    --
    -- If interrupts are enabled, this flag will also raise the shared
    -- ConfigBus interrupt signal. (Most hosts will need to poll various
    -- ConfigBus peripherals to find the source that needs service.)
    -- By default, interrupts are disabled on reset.
    --
    -- Register contents:
    --  * Bits 31-02: Reserved (zeros)
    --  * Bit     01: Service-request flag (read-only)
    --  * Bit     00: Interrupt enabled? (read-write)
    component cfgbus_interrupt is
        generic (
        DEVADDR     : integer;                  -- Peripheral address
        REGADDR     : integer := CFGBUS_ADDR_ANY;
        INITMODE    : std_logic := '0');        -- Enabled by default?
        port (
        -- ConfigBus interface
        cfg_cmd     : in  cfgbus_cmd;
        cfg_ack     : out cfgbus_ack;
        -- Asynchronous interrupt triggers (choose one)
        ext_flag    : in  std_logic := '0';     -- Persistent flag
        ext_toggle  : in  std_logic := '0');    -- Toggle-event
    end component;
end package;

------------------------------ Package body ------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

package body cfgbus_common is
    function cfgbus_devaddr_if(
        devaddr : cfgbus_devaddr;
        enable  : boolean)
        return integer is
    begin
        if enable then
            return devaddr;
        else
            return CFGBUS_ADDR_NONE;
        end if;
    end function;

    function cfgbus_mask_lsb(n : natural) return cfgbus_word is
        variable mask : cfgbus_word := (others => '0');
    begin
        for b in mask'range loop
            mask(b) := bool2bit(b < n);
        end loop;
        return mask;
    end function;

    function cfgbus_mask_msb(n : natural) return cfgbus_word is
        variable mask : cfgbus_word := (others => '0');
    begin
        for b in mask'range loop
            mask(mask'left-n) := bool2bit(b < n);
        end loop;
        return mask;
    end function;

    function cfgbus_reg_enable(
        devaddr : integer;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean is
    begin
        return (devaddr > CFGBUS_ADDR_NONE)
           and (regaddr > CFGBUS_ADDR_NONE);
    end function;

    function cfgbus_match(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean is
    begin
        return (devaddr = CFGBUS_ADDR_ANY or cmd.devaddr = devaddr)
           and (regaddr = CFGBUS_ADDR_ANY or cmd.regaddr = regaddr);
    end function;

    function cfgbus_wrcmd(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean is
    begin
        return (cmd.wrcmd = '1') and cfgbus_match(cmd, devaddr, regaddr);
    end function;

    function cfgbus_rdcmd(
        cmd     : cfgbus_cmd;
        devaddr : integer := CFGBUS_ADDR_ANY;
        regaddr : integer := CFGBUS_ADDR_ANY)
        return boolean is
    begin
        return (cmd.rdcmd = '1') and cfgbus_match(cmd, devaddr, regaddr);
    end function;

    function cfgbus_idle(
        irq     : std_logic := '0')
        return cfgbus_ack
    is
        variable result : cfgbus_ack := (
            rdata   => (others => '0'),
            rdack   => '0',
            rderr   => '0',
            irq     => irq);
    begin
        return result;
    end function;

    function cfgbus_reply(
        data    : cfgbus_word;
        irq     : std_logic := '0')
        return cfgbus_ack
    is
        variable result : cfgbus_ack := (
            rdata   => data,
            rdack   => '1',
            rderr   => '0',
            irq     => irq);
    begin
        return result;
    end function;

    function cfgbus_error(
        irq     : std_logic := '0')
        return cfgbus_ack
    is
        variable result : cfgbus_ack := (
            rdata   => (others => '0'),
            rdack   => '0',
            rderr   => '1',
            irq     => irq);
    begin
        return result;
    end function;

    function cfgbus_merge(ack_array : cfgbus_ack_array)
        return cfgbus_ack
    is
        constant ZERO   : cfgbus_word := (others => '0');
        variable result : cfgbus_ack := cfgbus_idle;
    begin
        for x in ack_array'range loop
            -- Check for error conditions.
            if (ack_array(x).rdack = '0' and ack_array(x).rdata /= ZERO) then
                result.rderr := '1';    -- Data without ACK
            elsif (ack_array(x).rdack = '1' and result.rdack = '1') then
                result.rderr := '1';    -- Multiple ACKs
            elsif (ack_array(x).rderr = '1') then
                result.rderr := '1';    -- Upstream error
            end if;
            -- Bitwise-OR each other signal.
            result.rdata := result.rdata or ack_array(x).rdata;
            result.rdack := result.rdack or ack_array(x).rdack;
            result.irq   := result.irq   or ack_array(x).irq;
        end loop;
        return result;
    end function;

    function cfgbus_merge(ack1, ack2 : cfgbus_ack)
        return cfgbus_ack
    is
        constant ack_array : cfgbus_ack_array(0 to 1) := (0 => ack1, 1 => ack2);
    begin
        return cfgbus_merge(ack_array);
    end function;
end package body;

------------------------- Component definitions --------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_buffer is
    port (
    -- Interface to host
    host_cmd    : in  cfgbus_cmd;
    host_ack    : out cfgbus_ack;
    -- Buffered interface
    buff_cmd    : out cfgbus_cmd;
    buff_ack    : in  cfgbus_ack);
end cfgbus_buffer;

architecture cfgbus_buffer of cfgbus_buffer is

signal sysaddr  : cfgbus_sysaddr := 0;
signal devaddr  : cfgbus_devaddr := 0;
signal regaddr  : cfgbus_regaddr := 0;
signal wdata    : cfgbus_word := (others => '0');
signal wstrb    : cfgbus_wstrb := (others => '0');
signal wrcmd    : std_logic := '0';
signal rdcmd    : std_logic := '0';
signal rdata    : cfgbus_word := (others => '0');
signal rdack    : std_logic := '0';
signal rderr    : std_logic := '0';
signal irq      : std_logic := '0';

begin

-- Command path
buff_cmd.clk     <= host_cmd.clk;
buff_cmd.sysaddr <= sysaddr;
buff_cmd.devaddr <= devaddr;
buff_cmd.regaddr <= regaddr;
buff_cmd.wdata   <= wdata;
buff_cmd.wstrb   <= wstrb;
buff_cmd.wrcmd   <= wrcmd;
buff_cmd.rdcmd   <= rdcmd;
buff_cmd.reset_p <= host_cmd.reset_p;

-- Reply path
host_ack.rdata   <= rdata;
host_ack.rdack   <= rdack;
host_ack.rderr   <= rderr;
host_ack.irq     <= irq;

-- Buffer signals in each direction.
p_buff : process(host_cmd.clk)
begin
    if rising_edge(host_cmd.clk) then
        sysaddr <= host_cmd.sysaddr;
        devaddr <= host_cmd.devaddr;
        regaddr <= host_cmd.regaddr;
        wdata   <= host_cmd.wdata;
        wstrb   <= host_cmd.wstrb;
        wrcmd   <= host_cmd.wrcmd and not host_cmd.reset_p;
        rdcmd   <= host_cmd.rdcmd and not host_cmd.reset_p;
        rdata   <= buff_ack.rdata;
        rdack   <= buff_ack.rdack and not host_cmd.reset_p;
        rderr   <= buff_ack.rderr;
        irq     <= buff_ack.irq;
    end if;
end process;

end cfgbus_buffer;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_timeout is
    generic (
    RD_TIMEOUT  : positive := 16);
    port (
    -- Interface to host
    host_cmd    : in  cfgbus_cmd;
    host_ack    : out cfgbus_ack;
    host_wait   : out std_logic;    -- RDCMD pending, host should wait
    host_error  : out std_logic;    -- Flow-control violation by host
    -- Interface to peripherals
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack);
end cfgbus_timeout;

architecture cfgbus_timeout of cfgbus_timeout is

signal passthru : std_logic;        -- Allow upstream ACK / ERR strobes?
signal pending  : std_logic := '0'; -- Waiting for ACK
signal timeout  : std_logic := '0'; -- Timeout (RDCMD without ACK)
signal tcount   : integer range 0 to RD_TIMEOUT-1 := 0;

begin

-- Command path
cfg_cmd.clk     <= host_cmd.clk;
cfg_cmd.sysaddr <= host_cmd.sysaddr;
cfg_cmd.devaddr <= host_cmd.devaddr;
cfg_cmd.regaddr <= host_cmd.regaddr;
cfg_cmd.wdata   <= host_cmd.wdata;
cfg_cmd.wstrb   <= host_cmd.wstrb;
cfg_cmd.wrcmd   <= host_cmd.wrcmd;
cfg_cmd.rdcmd   <= host_cmd.rdcmd;
cfg_cmd.reset_p <= host_cmd.reset_p;

-- Reply path
passthru        <= host_cmd.rdcmd or pending;
host_wait       <= pending or timeout;
host_error      <= (pending or timeout) and host_cmd.rdcmd;
host_ack.rdata  <= cfg_ack.rdata;
host_ack.rdack  <= (cfg_ack.rdack and passthru);
host_ack.rderr  <= (cfg_ack.rderr and passthru) or timeout;
host_ack.irq    <= cfg_ack.irq;

-- Timeout state machine.
p_timeout : process(host_cmd.clk)
begin
    if rising_edge(host_cmd.clk) then
        -- Update the "pending" flag (one read at a time).
        if (host_cmd.reset_p = '1' or cfg_ack.rdack = '1' or cfg_ack.rderr = '1') then
            pending <= '0'; -- Reset, command completed, or upstream error
            timeout <= '0';
            tcount  <= 0;
        elsif (host_cmd.rdcmd = '1') then
            assert (pending = '0' and timeout = '0')
                report "Command still busy." severity error;
            pending <= '1'; -- Read command issued
            timeout <= '0';
            tcount  <= RD_TIMEOUT-1;
        elsif (tcount > 0) then
            pending <= '1'; -- Waiting for response
            timeout <= '0';
            tcount  <= tcount - 1;
        else
            pending <= '0'; -- Read timeout
            timeout <= pending;
        end if;
    end if;
end process;

end cfgbus_timeout;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_register is
    generic (
    DEVADDR     : integer;          -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    WR_ATOMIC   : boolean := false; -- Ignore per-byte enable strobes?
    WR_MASK     : cfgbus_word := (others => '1');
    RSTVAL      : cfgbus_word := (others => '0'));
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Local interface
    reg_val     : out cfgbus_word;  -- Register value
    -- Event indicators (optional)
    evt_wr_str  : out std_logic;    -- Strobe on write
    evt_wr_tog  : out std_logic;    -- Toggle on write
    evt_rd_str  : out std_logic;    -- Strobe on read
    evt_rd_tog  : out std_logic);   -- Toggle on read
end cfgbus_register;

architecture cfgbus_register of cfgbus_register is

signal reg      : cfgbus_word := RSTVAL;
signal ack      : cfgbus_ack := cfgbus_idle;
signal wr_str   : std_logic := '0';
signal wr_tog   : std_logic := '0';
signal rd_str   : std_logic := '0';
signal rd_tog   : std_logic := '0';

begin

-- If this register is disabled, output is fixed at RSTVAL.
gen0 : if not cfgbus_reg_enable(DEVADDR, REGADDR) generate
    cfg_ack     <= cfgbus_idle;
    reg_val     <= RSTVAL;
    evt_wr_str  <= '0';
    evt_wr_tog  <= '0';
    evt_rd_str  <= '0';
    evt_rd_tog  <= '0';
end generate;

-- In the normal case...
gen1 : if cfgbus_reg_enable(DEVADDR, REGADDR) generate
    -- Drive top-level outputs.
    cfg_ack     <= ack;
    reg_val     <= reg;
    evt_wr_str  <= wr_str;
    evt_wr_tog  <= wr_tog;
    evt_rd_str  <= rd_str;
    evt_rd_tog  <= rd_tog;

    -- Main state machine.
    p_reg : process(cfg_cmd.clk)
    begin
        if rising_edge(cfg_cmd.clk) then
            -- Handle writes
            if (cfg_cmd.reset_p = '1') then
                reg <= RSTVAL;
            elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
                for n in reg'range loop
                    if ((WR_MASK(n) = '1') and (WR_ATOMIC or cfg_cmd.wstrb(n/8) = '1')) then
                        reg(n) <= cfg_cmd.wdata(n);
                    end if;
                end loop;
            end if;

            if (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
                wr_str  <= '1';
                wr_tog  <= not wr_tog;
            else
                wr_str  <= '0';
            end if;

            -- Handle reads.
            if (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR)) then
                ack     <= cfgbus_reply(reg);
                rd_str  <= '1';
                rd_tog  <= not rd_tog;
            else
                ack     <= cfgbus_idle;
                rd_str  <= '0';
            end if;
        end if;
    end process;
end generate;

end cfgbus_register;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.sync_reset;
use     work.common_primitives.sync_toggle2pulse;

entity cfgbus_register_sync is
    generic (
    DEVADDR     : integer;          -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    WR_ATOMIC   : boolean := false; -- Ignore per-byte enable strobes?
    WR_MASK     : cfgbus_word := (others => '1');
    RSTVAL      : cfgbus_word := (others => '0'));
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Local interface
    sync_clk    : in  std_logic;    -- I/O reference clock
    sync_val    : out cfgbus_word;  -- Register value
    sync_wr     : out std_logic;    -- Strobe on write
    sync_rd     : out std_logic);   -- Strobe on read
end cfgbus_register_sync;

architecture cfgbus_register_sync of cfgbus_register_sync is

-- ConfigBus clock domain
signal reg_val      : cfgbus_word;
signal evt_wr_tog   : std_logic;
signal evt_rd_tog   : std_logic;

-- Local clock domain
signal sync_rst     : std_logic;
signal sync_wr_d    : std_logic;
signal sync_wr_i    : std_logic;
signal sync_rd_i    : std_logic;
signal sync_val_i   : cfgbus_word := RSTVAL;

begin

-- If this register is disabled, output is fixed at RSTVAL.
gen0 : if not cfgbus_reg_enable(DEVADDR, REGADDR) generate
    cfg_ack     <= cfgbus_idle;
    sync_val    <= RSTVAL;
    sync_wr     <= '0';
    sync_rd     <= '0';
end generate;

-- In the normal case...
gen1 : if cfgbus_reg_enable(DEVADDR, REGADDR) generate
    -- Drive top-level outputs.
    sync_val    <= sync_val_i;
    sync_wr     <= sync_wr_d;
    sync_rd     <= sync_rd_i;

    -- Inner block does most of the work.
    u_reg : cfgbus_register
        generic map(
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR,
        WR_ATOMIC   => WR_ATOMIC,
        WR_MASK     => WR_MASK,
        RSTVAL      => RSTVAL)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_ack,
        reg_val     => reg_val,
        evt_wr_tog  => evt_wr_tog,
        evt_rd_tog  => evt_rd_tog);

    -- Clock-domain crossing for the reset, read, and write strobes.
    u_rst : sync_reset
        port map(
        in_reset_p  => cfg_cmd.reset_p,
        out_reset_p => sync_rst,
        out_clk     => sync_clk);
    u_rd : sync_toggle2pulse
        port map(
        in_toggle   => evt_rd_tog,
        out_strobe  => sync_rd_i,
        out_clk     => sync_clk);
    u_wr : sync_toggle2pulse
        port map(
        in_toggle   => evt_wr_tog,
        out_strobe  => sync_wr_i,
        out_clk     => sync_clk);

    -- After each write, latch the updated value.
    -- (With matched delay for the write strobe.)
    p_reg : process(sync_clk)
    begin
        if rising_edge(sync_clk) then
            sync_wr_d <= sync_wr_i and not sync_rst;
            if (sync_rst = '1') then
                sync_val_i <= RSTVAL;
            elsif (sync_wr_i = '1') then
                sync_val_i <= reg_val;
            end if;
        end if;
    end process;
end generate;

end cfgbus_register_sync;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_readonly is
    generic (
    DEVADDR     : integer;          -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY);
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Local interface
    reg_val     : in  cfgbus_word;  -- Read-only value
    -- Event indicators (optional)
    evt_wr_str  : out std_logic;    -- Strobe on write
    evt_wr_tog  : out std_logic;    -- Toggle on write
    evt_rd_str  : out std_logic;    -- Strobe on read
    evt_rd_tog  : out std_logic);   -- Toggle on read
end cfgbus_readonly;

architecture cfgbus_readonly of cfgbus_readonly is

signal ack      : cfgbus_ack := cfgbus_idle;
signal wr_str   : std_logic := '0';
signal wr_tog   : std_logic := '0';
signal rd_str   : std_logic := '0';
signal rd_tog   : std_logic := '0';

begin

-- If this register is disabled, output is fixed at RSTVAL.
gen0 : if not cfgbus_reg_enable(DEVADDR, REGADDR) generate
    cfg_ack     <= cfgbus_idle;
    evt_wr_str  <= '0';
    evt_wr_tog  <= '0';
    evt_rd_str  <= '0';
    evt_rd_tog  <= '0';
end generate;

-- In the normal case...
gen1 : if cfgbus_reg_enable(DEVADDR, REGADDR) generate
    -- Drive top-level outputs.
    cfg_ack     <= ack;
    evt_wr_str  <= wr_str;
    evt_wr_tog  <= wr_tog;
    evt_rd_str  <= rd_str;
    evt_rd_tog  <= rd_tog;

    -- Main state machine.
    p_reg : process(cfg_cmd.clk)
    begin
        if rising_edge(cfg_cmd.clk) then
            -- Handle writes (event only)
            if (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
                wr_str  <= '1';
                wr_tog  <= not wr_tog;
            end if;

            -- Handle reads.
            if (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR)) then
                ack     <= cfgbus_reply(reg_val);
                rd_str  <= '1';
                rd_tog  <= not rd_tog;
            else
                ack     <= cfgbus_idle;
                rd_str  <= '0';
            end if;
        end if;
    end process;
end generate;

end cfgbus_readonly;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.sync_toggle2pulse;

entity cfgbus_readonly_sync is
    generic (
    DEVADDR     : integer;          -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    AUTO_UPDATE : boolean := true); -- Automatically sample input?
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Local interface
    sync_clk    : in  std_logic;    -- I/O reference clock
    sync_val    : in  cfgbus_word;  -- Read-only value
    sync_wr     : out std_logic;    -- Strobe on write
    sync_rd     : out std_logic);   -- Strobe on read
end cfgbus_readonly_sync;

architecture cfgbus_readonly_sync of cfgbus_readonly_sync is

-- ConfigBus clock domain
signal cfg_reg      : cfgbus_word := (others => '0');
signal evt_wr_tog   : std_logic;
signal evt_rd_tog   : std_logic;
signal evt_update   : std_logic := '0';

-- Local clock domain
signal sync_reg     : cfgbus_word := (others => '0');
signal sync_wr_i    : std_logic;
signal sync_rd_i    : std_logic;
signal sync_evt_t   : std_logic := '0';

begin

-- If this register is disabled, output is fixed at RSTVAL.
gen0 : if not cfgbus_reg_enable(DEVADDR, REGADDR) generate
    cfg_ack <= cfgbus_idle;
    sync_wr <= '0';
    sync_rd <= '0';
end generate;

-- In the normal case...
gen1 : if cfgbus_reg_enable(DEVADDR, REGADDR) generate
    -- Drive top-level outputs.
    sync_wr <= sync_wr_i;
    sync_rd <= sync_rd_i;

    -- Inner block does most of the work.
    u_reg : cfgbus_readonly
        generic map(
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_ack,
        reg_val     => cfg_reg,
        evt_wr_tog  => evt_wr_tog,
        evt_rd_tog  => evt_rd_tog);

    -- Clock-domain crossing for the read and write strobes.
    u_rd : sync_toggle2pulse
        port map(
        in_toggle   => evt_rd_tog,
        out_strobe  => sync_rd_i,
        out_clk     => sync_clk);
    u_wr : sync_toggle2pulse
        port map(
        in_toggle   => evt_wr_tog,
        out_strobe  => sync_wr_i,
        out_clk     => sync_clk);

    -- Automatic update mode:
    --  * In the SYNC_CLK domain, latch new value every N clock cycles.
    --    (This ensures the value is stable for the required duration.)
    --  * This event is transitioned to the ConfigBus clock domain,
    --    and then causes a second latch to store the new value.
    --  * CPU may read the latter latched value at any time.
    gen_auto : if AUTO_UPDATE generate
        p_ctr : process(sync_clk)
            variable ctr : unsigned(3 downto 0) := (others => '0');
        begin
            if rising_edge(sync_clk) then
                if (ctr = 0) then
                    sync_reg <= sync_val;
                    sync_evt_t <= not sync_evt_t;
                end if;
                ctr := ctr + 1;
            end if;
        end process;

        u_sync : sync_toggle2pulse
            port map(
            in_toggle   => sync_evt_t,
            out_strobe  => evt_update,
            out_clk     => cfg_cmd.clk);

        p_reg : process(cfg_cmd.clk)
        begin
            if rising_edge(cfg_cmd.clk) then
                if (evt_update = '1') then
                    cfg_reg <= sync_reg;
                end if;
            end if;
        end process;
    end generate;

    -- Manual update mode:
    --  * Write event is transitioned to SYNC_CLK domain.
    --  * This event latches the new register value.
    --  * CPU may read the latched value once process is completed.
    gen_manual : if not AUTO_UPDATE generate
        p_reg : process(sync_clk)
        begin
            if rising_edge(sync_clk) then
                if (sync_wr_i = '1') then
                    sync_reg <= sync_val;
                end if;
            end if;
        end process;

        cfg_reg     <= sync_reg;
        evt_update  <= '0'; -- Unused
        sync_evt_t  <= '0'; -- Unused
    end generate;
end generate;

end cfgbus_readonly_sync;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.sync_buffer;
use     work.common_primitives.sync_toggle2pulse;

entity cfgbus_interrupt is
    generic (
    DEVADDR     : integer;                  -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    INITMODE    : std_logic := '0');        -- Enabled by default?
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Asynchronous interrupt triggers (choose one)
    ext_flag    : in  std_logic := '0';     -- Persistent flag
    ext_toggle  : in  std_logic := '0');    -- Toggle-event
end cfgbus_interrupt;

architecture cfgbus_interrupt of cfgbus_interrupt is

signal irq_sync_a   : std_logic;
signal irq_sync_b   : std_logic;
signal irq_enable   : std_logic := INITMODE;
signal irq_flag     : std_logic := '0';
signal irq_out      : std_logic;
signal status       : cfgbus_word;
signal ack          : cfgbus_ack := cfgbus_idle;

begin

-- Drive top-level output.
cfg_ack <= ack;

-- Synchronize both input triggers.
u_sync_a : sync_buffer
    port map(
    in_flag     => ext_flag,
    out_flag    => irq_sync_a,
    out_clk     => cfg_cmd.clk);
u_sync_b : sync_toggle2pulse
    port map(
    in_toggle   => ext_toggle,
    out_strobe  => irq_sync_b,
    out_clk     => cfg_cmd.clk);

-- Combinational logic for the status word.
irq_out <= irq_enable and irq_flag;
status  <= (0 => irq_enable, 1 => irq_flag, others => '0');

-- Interrupt state machine.
u_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Update the service-request flag:
        --  * Any external event sets the flag.
        --  * Any ConfigBus write clears it.
        if (cfg_cmd.reset_p = '1') then
            irq_flag    <= '0';
        elsif (irq_sync_a = '1' or irq_sync_b = '1') then
            irq_flag    <= '1';
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
            irq_flag    <= '0';
        end if;

        -- Update the interrupt-enabled flag.
        if (cfg_cmd.reset_p = '1') then
            irq_enable  <= INITMODE;
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
            irq_enable  <= cfg_cmd.wdata(0);
        end if;

        -- Handle ConfigBus reads:
        if (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR)) then
            ack <= cfgbus_reply(status, irq_out);
        else
            ack <= cfgbus_idle(irq_out);
        end if;
    end if;
end process;

end cfgbus_interrupt;
