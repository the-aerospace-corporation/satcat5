--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Pulse-per-second (PPS) input comparison to a PTP clock
--
-- This block accepts two inputs: a pulse-per-second (PPS) signal from
-- outside the FPGA, and a PTP timestamp (e.g., the "rtc_time" signal
-- from port_mailmap).  On detecting the selected edge of the PPS signal
-- (i.e., rising or falling), it notes the PTP timestamp and makes this
-- information available to the ConfigBus host.
--
-- The PPS signal can be an ordinary single-bit input, or it can be a
-- parallel word with PAR_COUNT samples per parallel clock.  The user
-- must separately provide any required SERDES logic.
--
-- The ConfigBus interface uses a single register:
--  * Write: Set the PPS polarity
--      * Bit 31-02: Reserved (write zeros)
--      * Bit 01-00: Select active edge(s):
--          00 = Falling
--          01 = Rising
--          1x = Both
--      * Writing to this register clears the FIFO.
--  * Read: Read timestamp information, 24 bits at a time.
--      * Bit 31: Last word flag (each timestamp contains four words)
--      * Bit 30: Data valid flag (0 = ignore this read)
--      * Bit 29-25: Reserved
--      * Bit 24: Polarity flag (1 = rising edge, 0 = falling edge)
--      * Bit 23-00: Concatenated PTP timestamp:
--          1st word = Seconds (47 downto 24)
--          2nd word = Seconds (23 downto 00)
--          3rd word = Subnanoseconds (47 downto 24)
--          4th word = Subnanoseconds (23 downto 00)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_pps_in is
    generic (
    DEV_ADDR    : integer;              -- ConfigBus device address
    REG_ADDR    : integer;              -- ConfigBus register address
    PAR_CLK_HZ  : positive;             -- Rate of the parallel clock
    PAR_COUNT   : positive := 1;        -- Number of samples per clock
    EDGE_RISING : boolean := true;      -- Default polarity?
    MSB_FIRST   : boolean := true);     -- Parallel bit order
    port (
    -- Parallel PPS input, with PTP timestamp in the same clock domain.
    par_clk     : in  std_logic;        -- Parallel clock
    par_rtc     : in  ptp_time_t;       -- PTP/RTC timestamp
    par_rtc_ok  : in  std_logic := '1'; -- PTP/RTC locked?
    par_pps_in  : in  std_logic_vector(PAR_COUNT-1 downto 0);

    -- ConfigBus interface (required)
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end ptp_pps_in;

architecture ptp_pps_in of ptp_pps_in is

-- Precalculate the effective offset for each input bit.
-- (Including compensation for edge-detection pipeline delay.)
type tstamp_array is array(0 to PAR_COUNT-1) of tstamp_t;

function get_offsets return tstamp_array is
    constant TPAR  : real := 1.0 / real(PAR_CLK_HZ);
    constant TSAMP : real := TPAR / real(PAR_COUNT);
    variable result : tstamp_array;
begin
    for n in result'range loop
        result(n) := get_tstamp_sec(real(n)*TSAMP - 2.0*TPAR);
    end loop;
    return result;
end function;

constant IDX2OFFSET : tstamp_array := get_offsets;

-- Edge detection.
subtype par_t is std_logic_vector(PAR_COUNT-1 downto 0);
signal par_early    : par_t;
signal par_late     : par_t;
signal par_prev     : std_logic := '0';
signal par_edge     : par_t;
signal diff_pol     : std_logic := '0';
signal diff_vec     : par_t := (others => '0');
signal edge_det     : std_logic := '0';
signal edge_idx     : integer range 0 to PAR_COUNT-1 := 0;
signal edge_pol     : std_logic := '0';

-- Timestamp calculation.
signal adj_sec      : tstamp_t := (others => '0');
signal adj_subns    : tstamp_t := (others => '0');
signal adj_pol      : std_logic := '0';
signal adj_write    : std_logic := '0';

-- FIFO state machine.
signal fifo_count   : integer range 0 to 4 := 0;
signal fifo_sreg    : std_logic_vector(95 downto 0) := (others => '0');
signal fifo_meta    : std_logic_vector(4 downto 0) := (others => '0');
signal fifo_last    : std_logic;
signal fifo_valid   : std_logic;
signal fifo_ready   : std_logic;

-- ConfigBus interface.
constant CPU_RSTVAL : cfgbus_word := (0 => bool2bit(EDGE_RISING), others => '0');
signal cpu_clear    : std_logic;
signal cpu_config   : cfgbus_word;
signal cpu_rising   : par_t;
signal cpu_both     : par_t;

begin

-- Convert input to LSB-first and compare adjacent bits.
par_late  <= flip_vector(par_pps_in) when MSB_FIRST else par_pps_in;
par_early <= par_late(PAR_COUNT-2 downto 0) & par_prev;
par_edge  <= (cpu_both) or (cpu_rising xnor par_late);

-- Edge detection state machine:
p_edge : process(par_clk)
begin
    if rising_edge(par_clk) then
        -- Pipeline stage 2: Priority encoder
        -- If there's a conflict, take the earliest match.
        edge_det <= or_reduce(diff_vec) and not cpu_clear;
        edge_idx <= priority_encoder(diff_vec);
        edge_pol <= diff_pol;

        -- Pipeline stage 1: Edge detection
        -- Compare adjacent bits to find rising or falling edges, then
        -- mask for requested edge type(s), i.e., rising/falling/both.
        diff_vec <= (par_late xor par_early) and par_edge;
        -- Note previous state to distinguish rising vs. falling edge.
        diff_pol <= not par_prev;   -- '1' for rising, '0' for falling

        -- Buffer the last bit of each input word.
        par_prev <= par_late(PAR_COUNT-1);
    end if;
end process;

-- Timestamp & FIFO state machine:
--  * For each detected edge, note the effective timestamp.
--  * Write timestamp to FIFO (i.e., four consecutive words).
p_time : process(par_clk)
begin
    if rising_edge(par_clk) then
        -- Pipeline stage 2: Write timestamp to FIFO.
        -- (Ignore new writes while transfer is already in progress.)
        if (cpu_clear = '1') then
            -- Clear FIFO -> Revert to idle.
            fifo_count <= 0;
        elsif (fifo_count = 0 and adj_write = '1') then
            -- Start new timestamp (four words).
            fifo_count <= 4;
        elsif (fifo_count > 0 and fifo_ready = '1') then
            -- Countdown until transfer is completed.
            fifo_count <= fifo_count - 1;
        end if;

        if (fifo_count = 0 and adj_write = '1') then
            -- Latch the new timestamp, renormalizing as needed.
            if (signed(adj_subns) < 0) then
                fifo_sreg <= std_logic_vector(adj_sec - 1)
                           & std_logic_vector(adj_subns + TSTAMP_ONE_SEC);
            else
                fifo_sreg <= std_logic_vector(adj_sec)
                           & std_logic_vector(adj_subns);
            end if;
            -- Other metadata, such as rising/falling polarity.
            fifo_meta <= (0 => adj_pol, others => '0');
        elsif (fifo_count > 0 and fifo_ready = '1') then
            -- Update shift-register until transfer is completed.
            fifo_sreg <= fifo_sreg(71 downto 0) & x"000000";
        end if;

        -- Pipeline stage 1: Latch effective timestamp.
        -- Note: IDX2OFFSET is always negative, to compensate for pipeline delay.
        if (edge_det = '1' and par_rtc_ok = '1') then
            adj_sec     <= unsigned(par_rtc.sec);
            adj_subns   <= (par_rtc.nsec & par_rtc.subns) + IDX2OFFSET(edge_idx);
            adj_pol     <= edge_pol;
            adj_write   <= not cpu_clear;
        else
            adj_write   <= '0';
        end if;
    end if;
end process;

fifo_valid  <= bool2bit(fifo_count > 0);
fifo_last   <= bool2bit(fifo_count = 1);

-- ConfigBus interface.
cpu_rising <= (others => cpu_config(0));
cpu_both   <= (others => cpu_config(1));

u_cfg_rd : entity work.cfgbus_fifo
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_ADDR,
    RD_DEPTH    => 4,   -- 2^4 = 16 words = 4 timestamps
    RD_DWIDTH   => 24,
    RD_MWIDTH   => 5,
    RD_FLAGS    => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    cfg_clear   => cpu_clear,
    rd_clk      => par_clk,
    rd_data     => fifo_sreg(95 downto 72),
    rd_meta     => fifo_meta,
    rd_last     => fifo_last,
    rd_valid    => fifo_valid,
    rd_ready    => fifo_ready);

u_cfg_wr : cfgbus_register_sync
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_ADDR,
    WR_ATOMIC   => true,
    WR_MASK     => x"00000003",
    RSTVAL      => CPU_RSTVAL)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,
    sync_clk    => par_clk,
    sync_val    => cpu_config,
    sync_wr     => cpu_clear);

end ptp_pps_in;
