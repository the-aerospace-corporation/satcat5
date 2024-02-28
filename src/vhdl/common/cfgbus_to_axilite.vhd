--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled AXI-Lite bus:
--
-- This block allows control of an AXI-Lite peripheral over ConfigBus.
-- It is not suitable for high-speed interfaces, but is good enough for
-- configuration registers and other low-throughput tasks.  The ConfigBus
-- and AXI clock domains may be separated if desired.
--
-- For the opposite conversion, see "cfgbus_host_axi.vhd".
--
-- Executing a single AXI write requires two ConfigBus commands (write
-- address, write data).  Executing a single AXI read requires three
-- ConfigBus operations (write address, initiate read, read result).
--
-- The interface contains four registers:
--  Reg0 = ADDRESS register (read-write)
--      Writes sets the AXI address for subsequent commands.
--      Reads echo the current AXI address.
--  Reg1 = WRITE register (write-only)
--      Writing to this register executes an AXI write with the provided
--      data word.  (And per-byte write strobes, if provided.)
--      Reads as '1' if the most recent write succeeded, '0' otherwise.
--  Reg2 = READ register (read-write)
--      Writing to this register executes an AXI read; data is ignored.
--      Reads yield the next response value if one is available, otherwise
--      they will return a ConfigBus error.
--  Reg3 = INTERRUPT register (optional)
--      See cfgbus_common.vhd / cfgbus_interrupt.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity cfgbus_to_axilite is
    generic (
    DEVADDR     : integer;          -- ConfigBus address
    ADDR_WIDTH  : positive;         -- AXI address width (max 32)
    IRQ_ENABLE  : boolean := true); -- Enable interrupts?
    port (
    -- ConfigBus peripheral interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- Optional level-sensitive interrupt.
    interrupt   : in  std_logic := '0';

    -- AXI-Lite master interface.
    axi_aclk    : in  std_logic;    -- AXI bus clock
    axi_aresetn : in  std_logic;    -- AXI bus reset
    axi_awaddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_awvalid : out std_logic;
    axi_awready : in  std_logic;
    axi_wdata   : out std_logic_vector(31 downto 0);
    axi_wstrb   : out std_logic_vector(3 downto 0);
    axi_wvalid  : out std_logic;
    axi_wready  : in  std_logic;
    axi_bresp   : in  std_logic_vector(1 downto 0);
    axi_bvalid  : in  std_logic;
    axi_bready  : out std_logic;
    axi_araddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_arvalid : out std_logic;
    axi_arready : in  std_logic;
    axi_rdata   : in  std_logic_vector(31 downto 0);
    axi_rresp   : in  std_logic_vector(1 downto 0);
    axi_rvalid  : in  std_logic;
    axi_rready  : out std_logic);
end cfgbus_to_axilite;

architecture cfgbus_to_axilite of cfgbus_to_axilite is

constant REGADDR_ADDR   : integer := 0;
constant REGADDR_WRITE  : integer := 1;
constant REGADDR_READ   : integer := 2;
constant REGADDR_IRQ    : integer := 3;

signal axi_reset_p  : std_logic;
signal axi_bokay    : std_logic;
signal axi_rokay    : std_logic;
signal cfg_acks     : cfgbus_ack_array(0 to 2) := (others => cfgbus_idle);
signal cfg_addr     : cfgbus_word;
signal wr_start     : std_logic;
signal wr_read      : std_logic;
signal wr_okay_axi  : std_logic := '0';
signal wr_status    : cfgbus_word := (others => '0');
signal rd_start     : std_logic;
signal rd_data      : cfgbus_word;
signal rd_okay      : std_logic;
signal rd_valid     : std_logic;
signal rd_ready     : std_logic;

begin

-- Miscellaneous glue logic.
axi_reset_p <= not axi_aresetn;
axi_bready  <= '1';     -- Always accept write-response
axi_bokay   <= bool2bit(axi_bresp = "00" or axi_bresp = "01");
axi_rokay   <= bool2bit(axi_rresp = "00" or axi_rresp = "01");
cfg_ack     <= cfgbus_merge(cfg_acks);

-- Shared logic for address register.
u_addr : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR_ADDR)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    reg_val     => cfg_addr);

-- Write controller.
wr_start    <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR_WRITE));
wr_read     <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_WRITE));

u_wr_addr : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => ADDR_WIDTH)
    port map(
    in_clk      => cfg_cmd.clk,
    in_data     => cfg_addr(ADDR_WIDTH-1 downto 0),
    in_valid    => wr_start,
    in_ready    => open,
    out_clk     => axi_aclk,
    out_data    => axi_awaddr,
    out_valid   => axi_awvalid,
    out_ready   => axi_awready,
    reset_p     => axi_reset_p);

u_wr_data : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => CFGBUS_WORD_SIZE,
    META_WIDTH  => CFGBUS_WORD_SIZE/8)
    port map(
    in_clk      => cfg_cmd.clk,
    in_data     => cfg_cmd.wdata,
    in_meta     => cfg_cmd.wstrb,
    in_valid    => wr_start,
    in_ready    => open,
    out_clk     => axi_aclk,
    out_data    => axi_wdata,
    out_meta    => axi_wstrb,
    out_valid   => axi_wvalid,
    out_ready   => axi_wready,
    reset_p     => axi_reset_p);

-- Clock-crossing logic for the write-response flag.
-- (Sticky flag in AXI domain, then simple sync buffer.)
p_wr_okay : process(axi_aclk)
begin
    if rising_edge(axi_aclk) then
        if (axi_reset_p = '1') then
            wr_okay_axi <= '0';
        elsif (axi_bvalid = '1') then
            wr_okay_axi <= axi_bokay;
        end if;
    end if;
end process;

u_wr_okay : sync_buffer
    port map(
    in_flag     => wr_okay_axi,
    out_flag    => wr_status(0),
    out_clk     => cfg_cmd.clk);

-- Read controller.
rd_start    <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR_READ));
rd_ready    <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_READ));

u_rd_addr : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => ADDR_WIDTH)
    port map(
    in_clk      => cfg_cmd.clk,
    in_data     => cfg_addr(ADDR_WIDTH-1 downto 0),
    in_valid    => rd_start,
    in_ready    => open,
    out_clk     => axi_aclk,
    out_data    => axi_araddr,
    out_valid   => axi_arvalid,
    out_ready   => axi_arready,
    reset_p     => axi_reset_p);

u_rd_data : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => CFGBUS_WORD_SIZE)
    port map(
    in_clk      => axi_aclk,
    in_data     => axi_rdata,
    in_last     => axi_rokay,
    in_valid    => axi_rvalid,
    in_ready    => axi_rready,
    out_clk     => cfg_cmd.clk,
    out_data    => rd_data,
    out_last    => rd_okay,
    out_valid   => rd_valid,
    out_ready   => rd_ready,
    reset_p     => axi_reset_p);

p_read : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (rd_valid = '1' and rd_ready = '1' and rd_okay = '1') then
            -- Successful read!
            cfg_acks(1) <= cfgbus_reply(rd_data);
        elsif (rd_ready = '1') then
            -- Failed read due to AXI error or empty queue.
            cfg_acks(1) <= cfgbus_error;
        elsif (wr_read = '1') then
            -- Report status for the WRITE register.
            cfg_acks(1) <= cfgbus_reply(wr_status);
        else
            -- Idle.
            cfg_acks(1) <= cfgbus_idle;
        end if;
    end if;
end process;

-- Optional interrupt controller.
gen_irq : if IRQ_ENABLE generate
    u_irq : cfgbus_interrupt
        generic map(
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR_IRQ)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(2),
        ext_flag    => interrupt);
end generate;

end cfgbus_to_axilite;
