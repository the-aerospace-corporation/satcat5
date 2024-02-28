--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SGMII Receiver using OSERDESE2
--
-- This block accepts a 1250 Mbps input and samples it at 5 GSPS using
-- the Xilinx 7-Series ISERDESE2 primitive.  This high effective rate is
-- achieved using the I/O structure in OVERSAMPLE mode and delaying one
-- half of the differential pair by ~200 ps.  An input FIFO is then
-- used to slow parallel data for further processing.
--
-- The input FIFO can be implemented using IN_FIFO (specify IN_FIFO_LOC)
-- or using SelectRAM (leave IN_FIFO_LOC empty).  See also: sgmii_input_fifo.
--
-- Note: Parts of the raw input structure are inspired by XAPP523, though
-- this design draws substantially less power and is more jitter tolerant.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;

entity sgmii_serdes_rx is
    generic (
    IN_FIFO_LOC : string := "";         -- Location of IN_FIFO (or use RAMB32X1D)
    IOSTANDARD  : string := "LVDS_25";  -- IOSTANDARD for RxD_*
    POL_INVERT  : boolean := false;     -- Invert input polarity
    BIAS_ENABLE : boolean := false;     -- Enable split-termination biasing.
    DIFF_TERM   : boolean := true;      -- Enable internal termination?
    REFCLK_MHZ  : integer := 200);      -- IDELAYCTRL reference freq. (MHz)
    port (
    -- Top-level LVDS input pair.
    RxD_p_pin   : in  std_logic;
    RxD_n_pin   : in  std_logic;

    -- Timestamp metadata in the "clk_125" domain.
    rx_tstamp   : in  unsigned(47 downto 0) := (others => '0');

    -- Parallel output data (MSB first, AXI flow control).
    out_clk     : in  std_logic;        -- 130 MHz or higher
    out_data    : out std_logic_vector(39 downto 0);
    out_tstamp  : out unsigned(47 downto 0);
    out_next    : out std_logic;

    -- Rx clock and reset/shutdown
    clk_125     : in  std_logic;
    clk_625_00  : in  std_logic;
    clk_625_90  : in  std_logic;
    reset_p     : in  std_logic);
end sgmii_serdes_rx;

architecture rtl of sgmii_serdes_rx is

-- Enable split termination?
-- (Note this method is incompatible with LVDS_25; try DIFF_SSTL18_II etc.)
function get_term return string is
begin
    if BIAS_ENABLE then
        return "UNTUNED_SPLIT_50";  -- 100 Ohm pullup + 100 ohm pulldown
    else
        return "NONE";              -- 100 Ohm differential (DIFF_TERM)
    end if;
end function;

attribute IN_TERM : string;
attribute IN_TERM of RxD_p_pin, RxD_n_pin : signal is get_term;

-- Calculate delay parameters given IDELAYCTRL reference frequency.
constant TARGET_PS      : real := 200.0;
constant STEP_PS        : real := 15625.0 / real(REFCLK_MHZ);
constant STEP_DELTA_R   : real := TARGET_PS / STEP_PS;
constant STEP_DELTA_I   : integer := integer(floor(STEP_DELTA_R + 0.5));

constant IDELAY_COUNT_P : integer := 0;
constant IDELAY_COUNT_N : integer := IDELAY_COUNT_P + STEP_DELTA_I;

-- Negated copies of each input clock.
signal clk_625_180      : std_logic;
signal clk_625_270      : std_logic;

-- Received signal pipeline.
signal RxD_p_buf        : std_logic;
signal RxD_n_buf        : std_logic;
signal RxD_p_dly        : std_logic;
signal RxD_n_dly        : std_logic;

-- Word-size conversion and clock domain transition.
subtype slv8 is std_logic_vector(7 downto 0);
subtype slv40 is std_logic_vector(39 downto 0);
signal rx_par8          : slv8;
signal rx_par40         : slv40 := (others => '0');
signal out_meta         : std_logic_vector(47 downto 0);
signal reset_125        : std_logic := '1';

begin

-- Instantiate LVDS-compatible receive buffer.
u_rxbuf : IBUFDS_DIFF_OUT
    generic map (
    IBUF_LOW_PWR => FALSE,
    DIFF_TERM    => DIFF_TERM,
    IOSTANDARD   => IOSTANDARD)
    port map (
    I => RxD_p_pin, IB => RxD_n_pin,
    O => RxD_p_buf, OB => RxD_n_buf);

-- Instantiate IDELAY unit for each pin.
u_dly_p : IDELAYE2
    generic map (
    IDELAY_TYPE             => "FIXED",
    IDELAY_VALUE            => IDELAY_COUNT_P,
    HIGH_PERFORMANCE_MODE   => "TRUE",
    REFCLK_FREQUENCY        => real(REFCLK_MHZ))
    port map (
    C           => '0',
    LD          => '0',
    LDPIPEEN    => '0',
    REGRST      => '0',
    CE          => '0',
    INC         => '0',
    CINVCTRL    => '0',
    CNTVALUEIN  => I2S(IDELAY_COUNT_P, 5),
    IDATAIN     => RxD_p_buf,
    DATAIN      => '0',
    DATAOUT     => RxD_p_dly,
    CNTVALUEOUT => open);

u_dly_n : IDELAYE2
    generic map (
    IDELAY_TYPE             => "FIXED",
    IDELAY_VALUE            => IDELAY_COUNT_N,
    HIGH_PERFORMANCE_MODE   => "TRUE",
    REFCLK_FREQUENCY        => real(REFCLK_MHZ))
    port map (
    C           => '0',
    LD          => '0',
    LDPIPEEN    => '0',
    REGRST      => '0',
    CE          => '0',
    INC         => '0',
    CINVCTRL    => '0',
    CNTVALUEIN  => I2S(IDELAY_COUNT_N, 5),
    IDATAIN     => RxD_n_buf,
    DATAIN      => '0',
    DATAOUT     => RxD_n_dly,
    CNTVALUEOUT => open);

-- Clock negation is absorbed inside ISERDESE2 (see below).
clk_625_180 <= not clk_625_00;
clk_625_270 <= not clk_625_90;

-- Instantiate each ISERDESE2 unit in OVERSAMPLE mode.
-- Sequential input ABCD results in Q1=A, Q3=B, Q2=C, Q4=D.
-- See UG471 Figure 3-7 for details.
u_iser_p : ISERDESE2
    generic map (
    INTERFACE_TYPE      => "OVERSAMPLE",
    DATA_RATE           => "DDR",
    DATA_WIDTH          => 4,
    OFB_USED            => "FALSE",
    NUM_CE              => 1,
    SERDES_MODE         => "MASTER",
    IOBDELAY            => "IFD",
    DYN_CLKDIV_INV_EN   => "FALSE",
    DYN_CLK_INV_EN      => "FALSE",
    INIT_Q1             => '0',
    INIT_Q2             => '0',
    INIT_Q3             => '0',
    INIT_Q4             => '0',
    SRVAL_Q1            => '0',
    SRVAL_Q2            => '0',
    SRVAL_Q3            => '0',
    SRVAL_Q4            => '0')
    port map (
    CLK                 => clk_625_00,
    CLKB                => clk_625_180,
    OCLK                => clk_625_90,
    OCLKB               => clk_625_270,
    DDLY                => RxD_p_dly,
    D                   => '0',
    BITSLIP             => '0',
    CE1                 => '1',
    CE2                 => '1',
    CLKDIV              => '0',
    CLKDIVP             => '0',
    DYNCLKDIVSEL        => '0',
    DYNCLKSEL           => '0',
    OFB                 => '0',
    RST                 => reset_p,
    SHIFTIN1            => '0',
    SHIFTIN2            => '0',
    SHIFTOUT1           => open,
    SHIFTOUT2           => open,
    O                   => open,
    Q1                  => rx_par8(6),
    Q2                  => rx_par8(2),
    Q3                  => rx_par8(4),
    Q4                  => rx_par8(0),  -- Last in (newest)
    Q5                  => open,
    Q6                  => open,
    Q7                  => open,
    Q8                  => open);

u_iser_n : ISERDESE2
    generic map (
    INTERFACE_TYPE      => "OVERSAMPLE",
    DATA_RATE           => "DDR",
    DATA_WIDTH          => 4,
    OFB_USED            => "FALSE",
    NUM_CE              => 1,
    SERDES_MODE         => "MASTER",
    IOBDELAY            => "IFD",
    DYN_CLKDIV_INV_EN   => "FALSE",
    DYN_CLK_INV_EN      => "FALSE",
    INIT_Q1             => '0',
    INIT_Q2             => '0',
    INIT_Q3             => '0',
    INIT_Q4             => '0',
    SRVAL_Q1            => '0',
    SRVAL_Q2            => '0',
    SRVAL_Q3            => '0',
    SRVAL_Q4            => '0')
    port map (
    CLK                 => clk_625_00,
    CLKB                => clk_625_180,
    OCLK                => clk_625_90,
    OCLKB               => clk_625_270,
    DDLY                => RxD_n_dly,
    D                   => '0',
    BITSLIP             => '0',
    CE1                 => '1',
    CE2                 => '1',
    CLKDIV              => '0',
    CLKDIVP             => '0',
    DYNCLKDIVSEL        => '0',
    DYNCLKSEL           => '0',
    OFB                 => '0',
    RST                 => reset_p,
    SHIFTIN1            => '0',
    SHIFTIN2            => '0',
    SHIFTOUT1           => open,
    SHIFTOUT2           => open,
    O                   => open,
    Q1                  => rx_par8(7),  -- First in (oldest)
    Q2                  => rx_par8(3),
    Q3                  => rx_par8(5),
    Q4                  => rx_par8(1),
    Q5                  => open,
    Q6                  => open,
    Q7                  => open,
    Q8                  => open);

-- Clock-domain transition from 625 to 125 MHz.
-- Most internal logic (including IN_FIFO) cannot run at 625 MHz.
-- A 5:1 fixed-rate is simple and doesn't require new clock buffers.
p_sreg : process(clk_625_00)
    -- In normal inputs, the ISERDES for RxD_N is negated.
    -- For inverted inputs (P/N switched), then negate RxD_P instead.
    -- (Sometimes need to swap pins for PCB layout optimization.)
    function make_mask return slv8 is
        -- Temporary variable forces "7 downto 0" vs. "0 to 7".
        -- (Workaround because "01010101" is ambiguous.)
        variable tmp : slv8;
    begin
        if (POL_INVERT) then
            tmp := "01010101";  -- Inverted input
        else
            tmp := "10101010";  -- Normal input
        end if;
        return tmp;
    end function;

    constant NEG_MASK   : slv8 := make_mask;
    -- Adjust latch phase:
    --  * Zero is precisely aligned with clk_125.
    --  * Positive values increase hold time.
    constant SAMP_PHASE : integer := 1;
    constant INIT_COUNT : integer := (SAMP_PHASE+3) mod 5;
    -- 5:1 shift register is latched at the designated clock phase.
    variable latch_ct   : integer range 0 to 4 := INIT_COUNT;
    variable latch_ce   : std_logic := '0';
    variable rx_sreg    : slv40 := (others => '0');
begin
    if rising_edge(clk_625_00) then
        -- Latch the shift-register contents every N clocks.
        if (latch_ce = '1') then
            rx_par40 <= rx_sreg;
        end if;
        latch_ce := bool2bit(latch_ct = 0);

        -- N-byte shift register, MSW first.
        -- (Also negate bits coming from the RxD_N pin.)
        rx_sreg := rx_sreg(31 downto 0) & (rx_par8 xor NEG_MASK);

        -- Countdown loop for choosing clock phase.
        if (reset_125 = '1') then
            latch_ct := INIT_COUNT;
        elsif (latch_ct = 0) then
            latch_ct := 4;
        else
            latch_ct := latch_ct - 1;
        end if;
    end if;
end process;

-- Simple sync marker aids the 625 MHz to 125 MHz transition.
p_mark : process(clk_125)
    variable reset_d : std_logic := '1';
begin
    if rising_edge(clk_125) then
        reset_125 <= reset_p or reset_d;
        reset_d   := reset_p;
    end if;
end process;

-- Instantiate either implementation of the sgmii_input_fifo:
gen_impl_a : if (IN_FIFO_LOC'length >= 1) generate
    u_fifo : entity work.sgmii_input_fifo(prim_in_fifo)
        generic map(IN_FIFO_LOC => IN_FIFO_LOC)
        port map(
        in_clk      => clk_125,
        in_data     => rx_par40,
        in_meta     => std_logic_vector(rx_tstamp),
        in_reset_p  => reset_125,
        out_clk     => out_clk,
        out_data    => out_data,
        out_meta    => out_meta,
        out_next    => out_next);
end generate;

gen_impl_b : if (IN_FIFO_LOC'length <= 0) generate
    u_fifo : entity work.sgmii_input_fifo(prim_ram32)
        port map(
        in_clk      => clk_125,
        in_data     => rx_par40,
        in_meta     => std_logic_vector(rx_tstamp),
        in_reset_p  => reset_125,
        out_clk     => out_clk,
        out_data    => out_data,
        out_meta    => out_meta,
        out_next    => out_next);
end generate;

-- Convert timestamp back to unsigned.
out_tstamp <= unsigned(out_meta);

end rtl;
