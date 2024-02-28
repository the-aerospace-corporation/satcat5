--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Special-purpose clock crossing FIFO for SGMII
--
-- This block accepts a 40-bit wide input, running at 125 MHz with
-- 100% duty cycle.  It generates a 40-bit wide output, running at
-- a higher rate, with less than 100% duty cycle.
--
-- The first implementation option uses the IN_FIFO primitive, which
-- is specifically designed for this purpose but requires manual
-- placement and may consume more power.
--
-- The second implementation option uses the RAM32X1D primitive, which
-- implements a small dual-port RAM using generic fabric resources.
--
-- Each implementation is provided as a separate "architecture" block
-- and can be selected using configuration constraints, etc.
--
-- NOTE: THIS FILE CONTAINS TWO IMPLEMENTATIONS OF THE SAME ENTITY!
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.common_primitives.sync_toggle2pulse;

entity sgmii_input_fifo is
    generic (
    IN_FIFO_LOC : string := "");    -- Default = RAM32X1D
    port (
    -- Input port:
    in_clk      : in  std_logic;
    in_data     : in  std_logic_vector(39 downto 0);
    in_meta     : in  std_logic_vector(47 downto 0);
    in_reset_p  : in  std_logic;

    -- Output port:
    out_clk     : in  std_logic;
    out_data    : out std_logic_vector(39 downto 0);
    out_meta    : out std_logic_vector(47 downto 0);
    out_next    : out std_logic);
end sgmii_input_fifo;

---------------------------------------------------------------------

architecture prim_in_fifo of sgmii_input_fifo is

-- IN_FIFO port conversion
signal fifo_in_d5   : std_logic_vector(7 downto 0);
signal fifo_in_d6   : std_logic_vector(7 downto 0);
signal fifo_out     : std_logic_vector(79 downto 0);
signal meta_out     : std_logic_vector(79 downto 0);
signal fifo_rd      : std_logic;
signal fifo_empty   : std_logic;

-- Lock location of the IN_FIFO unit.
attribute LOC : string;
attribute LOC of u_fifo : label is IN_FIFO_LOC;

begin

-- Instantiate the clock-crossing FIFO.  See UG471 pp. 171-173.
fifo_in_d5 <= "0000" & in_data(23 downto 20);
fifo_in_d6 <= "0000" & in_data(27 downto 24);

u_fifo : IN_FIFO
    generic map (
    ARRAY_MODE          => "ARRAY_MODE_4_X_4",  -- ARRAY_MODE_4_X_8, ARRAY_MODE_4_X_4
    SYNCHRONOUS_MODE    => "FALSE")             -- I/O clocks are async
    port map (
    -- FIFO status
    ALMOSTEMPTY => open,
    ALMOSTFULL  => open,
    EMPTY       => fifo_empty,
    FULL        => open,
    RESET       => in_reset_p,
    -- FIFO input ports (10+2 lanes x 4 bits each)
    WRCLK       => in_clk,
    WREN        => '1',
    D0          => in_data(3 downto 0),
    D1          => in_data(7 downto 4),
    D2          => in_data(11 downto 8),
    D3          => in_data(15 downto 12),
    D4          => in_data(19 downto 16),
    D5          => fifo_in_d5,  -- Zero-padded, see above
    D6          => fifo_in_d6,
    D7          => in_data(31 downto 28),
    D8          => in_data(35 downto 32),
    D9          => in_data(39 downto 36),
    -- FIFO output ports (10 lanes x 8 bits each)
    RDCLK       => out_clk,
    RDEN        => fifo_rd,
    Q0          => fifo_out(7 downto 0),
    Q1          => fifo_out(15 downto 8),
    Q2          => fifo_out(23 downto 16),
    Q3          => fifo_out(31 downto 24),
    Q4          => fifo_out(39 downto 32),
    Q5          => fifo_out(47 downto 40),
    Q6          => fifo_out(55 downto 48),
    Q7          => fifo_out(63 downto 56),
    Q8          => fifo_out(71 downto 64),
    Q9          => fifo_out(79 downto 72));

-- A second instance for metadata.
u_meta : IN_FIFO
    generic map (
    ARRAY_MODE          => "ARRAY_MODE_4_X_4",  -- ARRAY_MODE_4_X_8, ARRAY_MODE_4_X_4
    SYNCHRONOUS_MODE    => "FALSE")             -- I/O clocks are async
    port map (
    -- FIFO status
    ALMOSTEMPTY => open,
    ALMOSTFULL  => open,
    EMPTY       => fifo_empty,
    FULL        => open,
    RESET       => in_reset_p,
    -- FIFO input ports (10x4 + 2x8 lanes)
    WRCLK       => in_clk,
    WREN        => '1',
    D0          => in_meta(3 downto 0),
    D1          => in_meta(7 downto 4),
    D2          => in_meta(11 downto 8),
    D3          => in_meta(15 downto 12),
    D4          => in_meta(19 downto 16),
    D5          => in_meta(27 downto 20),
    D6          => in_meta(35 downto 28),
    D7          => in_meta(39 downto 36),
    D8          => in_meta(43 downto 40),
    D9          => in_meta(47 downto 44),
    -- FIFO output ports (10 lanes x 8 bits each)
    RDCLK       => out_clk,
    RDEN        => fifo_rd,
    Q0          => meta_out(7 downto 0),
    Q1          => meta_out(15 downto 8),
    Q2          => meta_out(23 downto 16),
    Q3          => meta_out(31 downto 24),
    Q4          => meta_out(39 downto 32),
    Q5          => meta_out(47 downto 40),
    Q6          => meta_out(55 downto 48),
    Q7          => meta_out(63 downto 56),
    Q8          => meta_out(71 downto 64),
    Q9          => meta_out(79 downto 72));

-- Reconstruct the final output word.
-- (Use LSBs and ignore MSBs from each sub-word.)
out_data <= fifo_out(75 downto 72)      -- LSBs Q9
          & fifo_out(67 downto 64)      -- LSBs Q8
          & fifo_out(59 downto 56)      -- LSBs Q7
          & fifo_out(51 downto 48)      -- LSBs Q6
          & fifo_out(43 downto 40)      -- LSBs Q5
          & fifo_out(35 downto 32)      -- LSBs Q4
          & fifo_out(27 downto 24)      -- LSBs Q3
          & fifo_out(19 downto 16)      -- LSBs Q2
          & fifo_out(11 downto 8)       -- LSBs Q1
          & fifo_out(3 downto 0);       -- LSBs Q0

out_meta <= meta_out(75 downto 72)      -- LSBs Q9
          & meta_out(67 downto 64)      -- LSBs Q8
          & meta_out(59 downto 56)      -- LSBs Q7
          & meta_out(55 downto 48)      -- Full Q6
          & meta_out(47 downto 40)      -- Full Q5
          & meta_out(35 downto 32)      -- LSBs Q4
          & meta_out(27 downto 24)      -- LSBs Q3
          & meta_out(19 downto 16)      -- LSBs Q2
          & meta_out(11 downto 8)       -- LSBs Q1
          & meta_out(3 downto 0);       -- LSBs Q0

out_next <= not fifo_empty;
fifo_rd  <= not fifo_empty;

end prim_in_fifo;

---------------------------------------------------------------------

architecture prim_ram32 of sgmii_input_fifo is

-- Each clock-crossing strobe represents N data words. (4/8/16)
constant BLK_SIZE : integer := 4;

signal wr_addr      : unsigned(4 downto 0) := (others => '0');
signal rd_addr      : unsigned(4 downto 0) := (others => '0');
signal rd_en        : std_logic := '0';
signal blk_tog      : std_logic := '0';     -- Toggle in in_clk
signal blk_out      : std_logic;            -- Strobe in out_clk
signal out_reset_p  : std_logic;

begin

-- Each primitive is 1-bit, so instantiate 40 for data and 48 for metadata.
gen_data : for n in in_data'range generate
    u_ram32x1d : RAM32X1D
        port map (
        -- Write port
        WCLK    => in_clk,      -- Write clock
        WE      => '1',         -- Write enable
        D       => in_data(n),  -- Write data
        SPO     => open,        -- Data passthrough (unused)
        A0      => wr_addr(0),  -- Write address
        A1      => wr_addr(1),
        A2      => wr_addr(2),
        A3      => wr_addr(3),
        A4      => wr_addr(4),
        -- Read port
        DPO     => out_data(n), -- Read data
        DPRA0   => rd_addr(0),  -- Read address
        DPRA1   => rd_addr(1),
        DPRA2   => rd_addr(2),
        DPRA3   => rd_addr(3),
        DPRA4   => rd_addr(4));
end generate;

gen_meta : for n in in_meta'range generate
    u_ram32x1d : RAM32X1D
        port map (
        -- Write port
        WCLK    => in_clk,      -- Write clock
        WE      => '1',         -- Write enable
        D       => in_meta(n),  -- Write data
        SPO     => open,        -- Data passthrough (unused)
        A0      => wr_addr(0),  -- Write address
        A1      => wr_addr(1),
        A2      => wr_addr(2),
        A3      => wr_addr(3),
        A4      => wr_addr(4),
        -- Read port
        DPO     => out_meta(n), -- Read data
        DPRA0   => rd_addr(0),  -- Read address
        DPRA1   => rd_addr(1),
        DPRA2   => rd_addr(2),
        DPRA3   => rd_addr(3),
        DPRA4   => rd_addr(4));
end generate;

-- Write address state machine:
p_write : process(in_clk)
    variable reset_d : std_logic := '1';
begin
    if rising_edge(in_clk) then
        -- Toggle every N clocks, unless we're in reset.
        if (in_reset_p = '0' and (wr_addr mod BLK_SIZE) = BLK_SIZE-1) then
            blk_tog <= not blk_tog;
        end if;

        -- Increment write address each clock.
        if (in_reset_p = '1' or reset_d = '1') then
            wr_addr <= (others => '0');
        else
            wr_addr <= wr_addr + 1;
        end if;
        reset_d := in_reset_p;
    end if;
end process;

-- Clock-crossing for the synchronous reset signal.
u_rst : sync_reset
    generic map(
    HOLD_MIN    => 3)
    port map(
    in_reset_p  => in_reset_p,
    out_reset_p => out_reset_p,
    out_clk     => out_clk);

-- Clock-domain crossing: One strobe every N clocks.
-- When we get a strobe, read up to the next block boundary.
u_blk : sync_toggle2pulse
    port map(
    in_toggle   => blk_tog,
    out_strobe  => blk_out,
    out_clk     => out_clk);

rd_en <= blk_out or bool2bit((rd_addr mod BLK_SIZE) /= 0);

-- Read address and flow-control state machine:
p_read : process(out_clk)
begin
    if rising_edge(out_clk) then
        if (out_reset_p = '1') then
            rd_addr <= (others => '0');
        elsif (rd_en = '1') then
            rd_addr <= rd_addr + 1;
        end if;
    end if;
end process;

out_next <= rd_en;

end prim_ram32;
