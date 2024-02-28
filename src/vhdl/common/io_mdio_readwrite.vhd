--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- A more complex MDIO interface with read/write capability
--
-- The "Management Data Input/Output" (MDIO) is an interface defined in
-- IEEE 802.3, Part 3.  It is commonly used to configure Ethernet PHY
-- transceivers.  This block implements a bus controller can read or write
-- commands using a word-at-a-time interface.  It is more complex than
-- io_mdio_writer, but also more capable.
--
-- All commands use a 12-bit control word.  From the MSB:
--  * 2-bits operator ("01" = write, "10" = read)
--  * 5-bits PHY address
--  * 5-bits REG address
-- Write commands have a separate 16-bit data argument; read commands
-- ignore this argument but present a 16-bit data word at the output.
-- Preambles and start tokens are generated automatically.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity io_mdio_readwrite is
    generic (
    CLKREF_HZ   : positive;         -- Main clock rate (Hz)
    MDIO_BAUD   : positive);        -- MDIO baud rate (bps)
    port (
    -- Command stream
    cmd_ctrl    : in    std_logic_vector(11 downto 0);
    cmd_data    : in    std_logic_vector(15 downto 0);
    cmd_valid   : in    std_logic;
    cmd_ready   :   out std_logic;

    -- Read data interface
    rd_data     :   out std_logic_vector(15 downto 0);
    rd_rdy      :   out std_logic;  -- Write-enable strobe

    -- MDIO interface
    mdio_clk    :   out std_logic;
    mdio_data   : inout std_logic;

    -- System interface
    ref_clk     : in    std_logic;  -- Reference clock
    reset_p     : in    std_logic);
end io_mdio_readwrite;

architecture io_mdio_readwrite of io_mdio_readwrite is

-- PHY signals
signal phy_clk_o    : std_logic := '0';
signal phy_data_o   : std_logic := '1';
signal phy_data_t   : std_logic := '1';
signal phy_data_i   : std_logic;
signal phy_data_s   : std_logic;

-- MDIO state machine
signal cmd_write    : std_logic := '0';
signal cmd_idle     : std_logic := '1';
signal rd_enable    : std_logic := '0';
signal rd_final     : std_logic := '0';
signal rd_sreg      : std_logic_vector(15 downto 0) := (others => '0');
signal wr_sreg      : std_logic_vector(31 downto 0) := (others => '0');

begin

-- Drive top-level I/O signals.
cmd_write   <= cmd_valid and cmd_idle;
cmd_ready   <= cmd_idle;
rd_data     <= rd_sreg;
rd_rdy      <= rd_final;
mdio_clk    <= phy_clk_o;

u_iobuf : bidir_io
    generic map(EN_PULLUP => true)
    port map(
    io_pin  => mdio_data,
    d_in    => phy_data_i,
    d_out   => phy_data_o,
    t_en    => phy_data_t);

-- Synchronize the MDIO input signal.
u_sync : sync_buffer
    port map(
    in_flag  => phy_data_i,
    out_flag => phy_data_s,
    out_clk  => ref_clk);

-- MDIO state machine.
p_mdio : process(ref_clk)
    -- Calculate delay per quarter-bit.
    -- (Specified rate is maximum, so round up.)
    constant DELAY_QTR  : natural := clocks_per_baud(CLKREF_HZ, 4*MDIO_BAUD);
    -- Local state.
    variable bit_count  : integer range 0 to 63 := 0;
    variable qtr_count  : integer range 0 to 3 := 0;
    variable clk_count  : natural range 0 to DELAY_QTR-1 := 0;
begin
    if rising_edge(ref_clk) then
        -- Clock signal
        if (reset_p = '1') then
            phy_clk_o <= '0';
        elsif (cmd_write = '1') then
            phy_clk_o <= '0';
        elsif (clk_count = 0) then
            phy_clk_o <= bool2bit(qtr_count = 3 or qtr_count = 2);
        end if;

        -- Data signal.
        if (reset_p = '1') then
            -- Global reset
            cmd_idle    <= '1';
            phy_data_o  <= '1';
            phy_data_t  <= '1';
            rd_enable   <= '0';
        elsif (cmd_write = '1') then
            -- Start of preamble
            cmd_idle    <= '0';
            phy_data_o  <= '1';
            phy_data_t  <= '0';
            rd_enable   <= cmd_ctrl(11);
            assert ((cmd_ctrl(11) xor cmd_ctrl(10)) = '1')
                report "Invalid command" severity error;
        elsif (qtr_count > 0 or clk_count > 0) then
            -- Wait until next bit transition...
            null;
        elsif (bit_count > 0) then
            -- Shift to next bit (amble or data)
            cmd_idle    <= '0';
            phy_data_o  <= bool2bit(bit_count > 32) or wr_sreg(31);
            phy_data_t  <= bool2bit(rd_enable = '1' and bit_count < 19);
        else
            -- End of command
            cmd_idle    <= '1';
            phy_data_o  <= '1';
            phy_data_t  <= '1';
        end if;

        -- Shift-register for reads samples just before rising-edge.
        if (qtr_count = 3 and clk_count = 0) then
            rd_sreg  <= rd_sreg(14 downto 0) & phy_data_s;  -- MSB-first
            rd_final <= rd_enable and bool2bit(bit_count = 0);
        else
            rd_final <= '0';
        end if;

        -- Shift-register for writes.
        if (cmd_write = '1') then
            wr_sreg <= "01" & cmd_ctrl & "10" & cmd_data;
        elsif (qtr_count = 0 and clk_count = 0 and bit_count <= 32) then
            wr_sreg <= wr_sreg(30 downto 0) & '0';
        end if;

        -- Update counters.
        if (reset_p = '1') then
            -- Reset.
            bit_count := 0;
            qtr_count := 0;
            clk_count := 0;
        elsif (cmd_write = '1') then
            -- Start of new byte.
            bit_count := 63;
            qtr_count := 3;
            clk_count := DELAY_QTR - 1;
        elsif (clk_count > 0) then
            -- Countdown to next quarter-bit.
            clk_count := clk_count - 1;
        elsif (qtr_count > 0) then
            -- Countdown to next full-bit.
            qtr_count := qtr_count - 1;
            clk_count := DELAY_QTR - 1;
        elsif (bit_count > 0) then
            -- Start of next bit.
            bit_count := bit_count - 1;
            qtr_count := 3;
            clk_count := DELAY_QTR - 1;
        end if;
    end if;
end process;

end io_mdio_readwrite;
