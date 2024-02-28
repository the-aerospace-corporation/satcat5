--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with Advanced Peripheral Bus (APB) interface
--
-- This module acts as a ConfigBus host, accepting read and write commands
-- over an AMBA Advanced Peripheral Bus (APB) interface and acting as a
-- bridge for those commands.
--
-- The bridge is compatible with both AMBA3 (APB v1.0) and with AMBA4
-- (APB v2.0).  The only difference is the addition of the PPROT signal
-- (unused) and the PSTRB signal (supported but optional).  Leave either
-- or both signals disconnected if they are not used.
--
-- The APB address space is divided as follows:
--  * 2 bits    Padding (byte to word conversion)
--  * 10 bits   Register address (0-1023)
--  * 8 bits    Device address (0-255)
--  * All remaining MSBs are ignored.
--
-- If possible, this device should be given a 20-bit address space (1 MiB).
-- If this space is reduced, then the block will operate correctly but upper
-- device addresses may not be accessible.
--
-- Write operations have no wait states; reads may wait depending on
-- command-to-ack latency.  The SLVERR strobe is fired if:
--  * Read or write address is not aligned to a 32-bit word boundary.
--  * Read operations return multiple replies (address conflict).
--  * Read operations return no reply (no response / timeout).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_apb is
    generic (
    RD_TIMEOUT  : positive := 16;       -- ConfigBus read timeout (clocks)
    ADDR_WIDTH  : positive := 32;       -- APB address width
    BASE_ADDR   : natural := 0);        -- APB base address
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- Interrupt flag.
    interrupt   : out std_logic;

    -- APB slave interface.
    apb_pclk    : in  std_logic;
    apb_presetn : in  std_logic;
    apb_paddr   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    apb_psel    : in  std_logic;
    apb_penable : in  std_logic;
    apb_pwrite  : in  std_logic;
    apb_pwdata  : in  std_logic_vector(31 downto 0);
    apb_pprot   : in  std_logic_vector(2 downto 0) := (others => '0');
    apb_pstrb   : in  std_logic_vector(3 downto 0) := (others => '1');
    apb_pready  : out std_logic;
    apb_prdata  : out std_logic_vector(31 downto 0);
    apb_pslverr : out std_logic);
end cfgbus_host_apb;

architecture cfgbus_host_apb of cfgbus_host_apb is

-- Address word = 8-bit device + 10-bit register.
subtype sub_addr_u is unsigned(29 downto 0);
signal addr_trim    : sub_addr_u;
signal addr_error   : std_logic := '0';

-- Timeouts and error detection.
signal dly_cmd      : cfgbus_cmd;
signal dly_ack      : cfgbus_ack;
signal int_cmd      : cfgbus_cmd;
signal int_ack      : cfgbus_ack;

-- Command state machine.
signal cmd_start    : std_logic;
signal wr_start     : std_logic;
signal wr_pending   : std_logic := '0';
signal wr_done      : std_logic;
signal rd_start     : std_logic;
signal rd_pending   : std_logic := '0';
signal rd_done      : std_logic;

begin

-- Address conversion.
addr_trim <= convert_address(apb_paddr, BASE_ADDR, 30);

-- Drive top-level APB slave outputs:
apb_pready  <= wr_done or rd_done;
apb_prdata  <= int_ack.rdata;
apb_pslverr <= addr_error or int_ack.rderr;
interrupt   <= int_ack.irq;

-- Drive internal ConfigBus signals:
int_cmd.clk     <= apb_pclk;
int_cmd.sysaddr <= to_integer(addr_trim(29 downto 18));
int_cmd.devaddr <= to_integer(addr_trim(17 downto 10));
int_cmd.regaddr <= to_integer(addr_trim(9 downto 0));
int_cmd.wdata   <= apb_pwdata;
int_cmd.wstrb   <= apb_pstrb;
int_cmd.wrcmd   <= wr_start;
int_cmd.rdcmd   <= rd_start;
int_cmd.reset_p <= not apb_presetn;

-- Single-cycle delay ensures minimum read turnaround time.
-- (APB minimum reply time is one cycle after start of request,
--  but ConfigBus allows same-cycle responses.)
u_buffer : cfgbus_buffer
    generic map(
    DLY_CMD     => false,
    DLY_ACK     => true)
    port map(
    host_cmd    => int_cmd,
    host_ack    => int_ack,
    buff_cmd    => dly_cmd,
    buff_ack    => dly_ack);

-- Timeouts and error detection.
u_timeout : cfgbus_timeout
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    host_cmd    => dly_cmd,
    host_ack    => dly_ack,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Command state machine.
cmd_start   <= apb_psel and not apb_penable;
wr_start    <= cmd_start and apb_pwrite;
wr_done     <= wr_pending;
rd_start    <= cmd_start and not apb_pwrite;
rd_done     <= int_ack.rdack or int_ack.rderr;

p_write : process(apb_pclk)
begin
    if rising_edge(apb_pclk) then
        -- Sanity-check PENABLE against our pending flags.
        if (apb_psel = '1' and apb_penable = '1') then
            assert (wr_pending = '1' and rd_pending = '0')
                or (wr_pending = '0' and rd_pending = '1')
                report "Unexpected PENABLE flag.";
        else
            assert (wr_pending = '0' and rd_pending = '0')
                report "Incomplete read/write command.";
        end if;

        -- Detect address-decode errors.
        -- (Delay is OK here due to the APB two-cycle minimum.)
        addr_error <= cmd_start and (apb_paddr(1) or apb_paddr(0));

        -- Update the write and read pending flags.
        if (apb_presetn = '0') then
            wr_pending <= '0';
        elsif (wr_start = '1') then
            wr_pending <= '1';
        elsif (wr_done = '1') then
            wr_pending <= '0';
        end if;

        if (apb_presetn = '0') then
            rd_pending <= '0';
        elsif (rd_start = '1') then
            rd_pending <= '1';
        elsif (rd_done = '1') then
            rd_pending <= '0';
        end if;
    end if;
end process;

end cfgbus_host_apb;
