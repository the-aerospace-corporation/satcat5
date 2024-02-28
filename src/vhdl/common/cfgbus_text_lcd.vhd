--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled LCD interface
--
-- This block connects the "io_text_lcd" controller to a simple ConfigBus
-- interface.  Since the LCD controller doesn't support back-pressure,
-- the ConfigBus interface is also feedforward.  Write a burst of text,
-- one character at a time up to 32 characters, then wait.
--
-- Control uses a single write-only ConfigBus register:
--  Bit 31:    Reset strobe (clears LCD)
--  Bit 30-08: Reserved (write zeros)
--  Bit 07-00: Next byte to be displayed (see "io_text_lcd")
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_text_lcd is
    generic(
    DEVADDR     : integer;          -- Control register address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    CFG_CLK_HZ  : integer;          -- ConfigBus clock rate (Hz)
    MSG_WAIT    : integer := 255);  -- Minimum time before refresh (msec)
    port(
    -- External LCD interface (see "io_text_lcd")
    lcd_db      : out std_logic_vector(3 downto 0);
    lcd_e       : out std_logic;
    lcd_rw      : out std_logic;
    lcd_rs      : out std_logic;

    -- Command interface, including reference clock.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_text_lcd;

architecture cfgbus_text_lcd of cfgbus_text_lcd is

signal strm_data    : std_logic_vector(7 downto 0) := (others => '0');
signal strm_write   : std_logic := '0';
signal lcd_reset_p  : std_logic := '1';

begin

-- LCD interface
u_lcd : entity work.io_text_lcd
    generic map(
    REFCLK_HZ   => CFG_CLK_HZ,
    MSG_WAIT    => MSG_WAIT)
    port map(
    lcd_db      => lcd_db,
    lcd_e       => lcd_e,
    lcd_rw      => lcd_rw,
    lcd_rs      => lcd_rs,
    strm_clk    => cfg_cmd.clk,
    strm_data   => strm_data,
    strm_wr     => strm_write,
    reset_p     => lcd_reset_p);

-- ConfigBus interface
u_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Reset and new-data strobes.
        if (cfg_cmd.reset_p = '1') then
            lcd_reset_p <= '1';
            strm_write  <= '0';
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
            lcd_reset_p <= cfg_cmd.wdata(31);
            strm_write  <= not cfg_cmd.wdata(31);
        else
            lcd_reset_p <= '0';
            strm_write  <= '0';
        end if;

        -- Streaming data.
        if (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
            strm_data   <= cfg_cmd.wdata(7 downto 0);
        end if;
    end if;
end process;

-- Read-replies currently disabled; reserved for future expansion.
cfg_ack <= cfgbus_idle;

end cfgbus_text_lcd;
