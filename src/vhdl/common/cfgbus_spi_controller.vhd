--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled SPI controller.
--
-- This block implements a flexible, software-controlled SPI bus controller.
-- Each bus operation (chip-select, write, read+write) is directly commanded
-- by the host, one byte at a time, with a small FIFO for queueing commands.
--
-- This block raises a ConfigBus interrupt after each end-of-frame event.
--
-- Control is handled through four ConfigBus registers:
-- (All bits not explicitly mentioned are reserved; write zeros.)
--  * REGADDR = 0: Interrupt control
--      Refer to cfgbus_common::cfgbus_interrupt
--  * REGADDR = 1: Configuration
--      Any write to this register resets the bus and clears all FIFOs.
--      Bit 09-08: SPI mode (0-3)
--      Bit 07-00: Clock divider ratio (SPI_SCK = REF_CLK / 2N)
--  * REGADDR = 2: Status (Read only)
--      Bit 02-02: Running / busy
--      Bit 01-01: Command FIFO full
--      Bit 00-00: Read FIFO has data
--  * REGADDR = 3: Data
--      Write: Queue a single command
--          Bit 11-08: Command opcode
--              0x0 Start-of-transaction / Select device (data = index)
--              0x1 Send byte (Tx-only)
--              0x2 Send and receive byte (Tx+Rx)
--              0x3 Receive byte (Rx-only, sets tristate pin)
--              0x4 End-of-transaction
--              (All other codes reserved)
--          Bit 07-00: Transmit byte or device index
--      Read: Read next data byte from receive FIFO
--          Bit 08-08: Received byte valid
--          Bit 07-00: Received byte, if applicable
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

-- Define a package with useful constants.
package cfgbus_spi_constants is
    -- Define command codes
    subtype spi_cmd_t is std_logic_vector(3 downto 0);
    constant CMD_SEL    : spi_cmd_t := x"0";
    constant CMD_WR     : spi_cmd_t := x"1";
    constant CMD_RW     : spi_cmd_t := x"2";
    constant CMD_RD     : spi_cmd_t := x"3";
    constant CMD_EOF    : spi_cmd_t := x"4";
end package;

---------------------------- Main block ----------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.cfgbus_spi_constants.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity cfgbus_spi_controller is
    generic(
    DEVADDR     : integer;          -- Control register address
    CSB_WIDTH   : positive := 1;    -- Number of chip-select outputs
    FIFO_LOG2   : integer := 6);    -- Tx/Rx FIFO depth = 2^N
    port(
    -- External SPI signals (4-wire)
    -- Tristate signal can be used to enable 3-wire mode.
    spi_csb     : out std_logic_vector(CSB_WIDTH-1 downto 0);
    spi_sck     : out std_logic;        -- Serial clock out (SCK)
    spi_sdo     : out std_logic;        -- Serial data out (COPI)
    spi_sdi     : in  std_logic := '0'; -- Serial data in (CIPO, if present)
    spi_sdt     : out std_logic;        -- Tristate for three-wire mode

    -- Command interface, including reference clock.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_spi_controller;

architecture cfgbus_spi_controller of cfgbus_spi_controller is

-- Chip-select controller
signal sel_idx      : byte_u := (others => '0');
signal sel_csb      : std_logic;

-- Command state
signal tx_data      : byte_t := (others => '0');
signal tx_last      : std_logic;
signal tx_wren      : std_logic := '0';
signal tx_rden      : std_logic := '0';
signal tx_tris      : std_logic := '0';
signal tx_valid     : std_logic;
signal tx_ready     : std_logic;
signal cmd_opcode   : spi_cmd_t;
signal cmd_data     : byte_t;
signal cmd_valid    : std_logic;
signal cmd_ready    : std_logic;
signal cmd_busy     : std_logic;

-- Received data
signal rx_data      : byte_t;
signal rx_rcvd      : std_logic;
signal rx_write     : std_logic;
signal rx_busy      : std_logic := '0';
signal rx_last      : std_logic := '0';
signal rx_rden      : std_logic := '0';
signal rx_tris      : std_logic := '0';

-- ConfigBus interface
signal cfg_word     : cfgbus_word;
signal cfg_mode     : integer range 0 to 3; -- Selected SPI mode (0/1/2/3)
signal cfg_rate     : byte_u;               -- Clock divider setting
signal cfg_reset    : std_logic;            -- Reset FIFOs and SPI state
signal cfg_irq_t    : std_logic := '0';     -- Toggle on EOF

begin

-- Combinational logic for the tristate and chip-select lines.
spi_sdt <= sel_csb or rx_tris;

gen_csb : for n in spi_csb'range generate
    spi_csb(n) <= sel_csb when (CSB_WIDTH = 1 or sel_idx = n) else '1';
end generate;

-- SPI bus controller
u_spi : entity work.io_spi_controller
    port map(
    cmd_data    => tx_data,
    cmd_last    => tx_last,
    cmd_valid   => tx_valid,
    cmd_ready   => tx_ready,
    rcvd_data   => rx_data,
    rcvd_write  => rx_rcvd,
    spi_csb     => sel_csb,
    spi_sck     => spi_sck,
    spi_sdo     => spi_sdo,
    spi_sdi     => spi_sdi,
    cfg_mode    => cfg_mode,
    cfg_rate    => cfg_rate,
    ref_clk     => cfg_cmd.clk,
    reset_p     => cfg_reset);

-- Command state machine.
p_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- One-word delay for Tx-data (see forwarding logic below)
        if (cmd_valid = '1' and cmd_ready = '1') then
            tx_data <= cmd_data;
        end if;

        -- Update flags for each upcoming command.
        if (cfg_reset = '1') then
            tx_wren <= '0';
            tx_rden <= '0';
            tx_tris <= '0';
            sel_idx <= (others => '0');
        elsif (cmd_valid = '1' and cmd_ready = '1') then
            -- Update various flags based on opcode.
            tx_wren <= bool2bit(cmd_opcode = CMD_WR)
                    or bool2bit(cmd_opcode = CMD_RW)
                    or bool2bit(cmd_opcode = CMD_RD);
            tx_rden <= bool2bit(cmd_opcode = CMD_RD)
                    or bool2bit(cmd_opcode = CMD_RW);
            tx_tris <= bool2bit(cmd_opcode = CMD_RD);
            -- Update selected index when commanded.
            if (cmd_opcode = CMD_SEL) then
                sel_idx <= unsigned(cmd_data);
            end if;
        end if;

        -- Update flags for the command currently being executed.
        if (cfg_reset = '1') then
            rx_busy <= '0';     -- Global reset
            rx_last <= '0';
            rx_rden <= '0';
            rx_tris <= '0';
        elsif (tx_valid = '1' and tx_ready = '1') then
            rx_busy <= tx_wren; -- Starting new command
            rx_last <= tx_last;
            rx_rden <= tx_rden;
            rx_tris <= tx_tris;
        elsif (rx_rcvd = '1') then
            rx_busy <= '0';     -- End of current command
        end if;

        -- Trigger an interrupt at the end of each frame.
        if (rx_rcvd = '1' and rx_last = '1') then
            cfg_irq_t <= not cfg_irq_t;
        end if;
    end if;
end process;

-- Modify command stream for the SPI controller:
--  * Only forward read, write, and read-write opcodes.
--  * Delay all commands by one, so we can set the LAST strobe.
tx_last     <= tx_wren and bool2bit(cmd_opcode = CMD_SEL or cmd_opcode = CMD_EOF);
tx_valid    <= tx_wren and cmd_valid;
cmd_ready   <= tx_ready or not tx_wren;
cmd_busy    <= rx_busy or tx_valid or not tx_ready;

-- Bus controller strobes at the end of each Tx/Rx byte.
-- Filter FIFO writes based on the relevant opcode.
rx_write    <= rx_rcvd and rx_rden;

-- Extract configuration parameters:
cfg_mode    <= u2i(cfg_word(9 downto 8));
cfg_rate    <= unsigned(cfg_word(7 downto 0));

-- ConfigBus interface
u_cfg : entity work.cfgbus_multiserial
    generic map(
    DEVADDR     => DEVADDR,
    CFG_MASK    => x"000003FF",
    CFG_RSTVAL  => x"000003FF",
    FIFO_LOG2   => FIFO_LOG2)
    port map(
    cmd_opcode  => cmd_opcode,
    cmd_data    => cmd_data,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    rx_data     => rx_data,
    rx_write    => rx_write,
    cfg_reset   => cfg_reset,
    cfg_word    => cfg_word,
    status_busy => cmd_busy,
    event_tog   => cfg_irq_t,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end cfgbus_spi_controller;
