--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Auxiliary functions supporting multiple switch cores
--
-- This module handles configuration scrubbing, error-reporting, status
-- LEDs, and other functions to support one or more switch_core units.
--
-- If enabled, this block can instantiate an FPGA-wide "scrubber" block
-- to detect SEU. Using this feature allows such events to be logged by
-- the error-reporting UART.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.scrub_generic;
use     work.common_primitives.sync_toggle2pulse_slv;
use     work.io_leds.all;
use     work.switch_types.all;

entity switch_aux is
    generic (
    SCRUB_CLK_HZ    : positive;             -- Scrubbing clock frequency (Hz)
    STARTUP_MSG     : string;               -- On-boot message (e.g., build date)
    STATUS_LED_LIT  : std_logic;            -- Polarity for status LEDs
    UART_BAUD       : positive := 921_600;  -- Baud rate for status UART
    CORE_COUNT      : positive := 1 ;       -- Number of switch_core units
    SCRUB_ENABLE    : boolean := false);    -- Enable FPGA-wide scrubbing?
    port (
    -- Concatenated error vector from each switch_core.
    -- (Each is a "toggle" indicator in any clock domain.)
    swerr_vec_t     : in  std_logic_vector(SWITCH_ERR_WIDTH*CORE_COUNT-1 downto 0);

    -- Ignore specific error types (optional).
    swerr_ignore    : in  std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0) := (others => '0');

    -- Optional error strobe for the clock.
    clock_stopped   : in  std_logic := '0';

    -- Status indicators.
    status_led_grn  : out std_logic;    -- Green LED (breathing pattern)
    status_led_ylw  : out std_logic;    -- Yellow LED (clock error strobe)
    status_led_red  : out std_logic;    -- Red LED (switch error strobe)
    status_uart     : out std_logic;    -- Plaintext error messages
    status_aux_dat  : out std_logic_vector(7 downto 0);
    status_aux_wr   : out std_logic;    -- Auxiliary error interface

    -- System interface.
    scrub_clk       : in  std_logic;    -- Scrubbing clock (always-on!)
    scrub_req_t     : out std_logic;    -- MAC-table scrub request (toggle)
    reset_p         : in  std_logic);   -- Global system reset
end switch_aux;

architecture switch_aux of switch_aux is

-- Configuration scrubbing error strobe.
signal scrub_err    : std_logic := '0';

-- MAC-table scrub request toggle (internal)
signal scrub_req_ti : std_logic := '0';

-- Clock-crossing for error signals.
signal swerr_sync   : std_logic_vector(SWITCH_ERR_WIDTH*CORE_COUNT-1 downto 0);
signal error_vec    : std_logic_vector(SWITCH_ERR_WIDTH downto 0);
signal error_any    : std_logic := '0';

begin

-- Optional FPGA configuration scrubbing for SEU mitigation.
gen_scrub : if SCRUB_ENABLE generate
    u_cfg_scrub : scrub_generic
        port map(
        clk_raw => scrub_clk,
        err_out => scrub_err);
end generate;

-- Toggle the MAC-scrub request signal every N clocks.
scrub_req_t <= scrub_req_ti;
p_mac_scrub : process(scrub_clk)
    variable count : integer range 0 to SCRUB_CLK_HZ := SCRUB_CLK_HZ;
begin
    if rising_edge(scrub_clk) then
        if (count = 0) then
            scrub_req_ti <= not scrub_req_ti;
        end if;

        if (reset_p = '1' or count = 0) then
            count := SCRUB_CLK_HZ;
        else
            count := count - 1;
        end if;
    end if;
end process;

-- Synchronize error signals from each switch core:
u_sync : sync_toggle2pulse_slv
    generic map(IO_WIDTH => swerr_sync'length)
    port map(
    in_toggle   => swerr_vec_t,
    out_strobe  => swerr_sync,
    out_clk     => scrub_clk);

-- Aggregate error-strobes from multiple sources.
p_errors : process(scrub_clk)
    variable err_temp : std_logic_vector(CORE_COUNT-1 downto 0) := (others => '0');
begin
    if rising_edge(scrub_clk) then
        -- Overall error strobe.
        error_any <= or_reduce(error_vec);

        -- Error index 0 is the scrubber.
        error_vec(0) <= scrub_err;

        -- Bitwise-OR switch error strobes from each core.
        for n in 0 to SWITCH_ERR_WIDTH-1 loop
            for c in err_temp'range loop
                err_temp(c) := swerr_sync(SWITCH_ERR_WIDTH*c + n);
            end loop;
            error_vec(n+1) <= or_reduce(err_temp) and not swerr_ignore(n);
        end loop;
    end if;
end process;

-- Error reporting UART.
u_uart : entity work.io_error_reporting
    generic map(
    CLK_HZ          => SCRUB_CLK_HZ,
    OUT_BAUD        => UART_BAUD,
    OK_CLOCKS       => SCRUB_CLK_HZ,
    START_MSG       => STARTUP_MSG,
    ERR_COUNT       => SWITCH_ERR_WIDTH+1,
    ERR_MSG00       => "SCRUB_SEU",
    ERR_MSG01       => "OVR_RX",
    ERR_MSG02       => "OVR_TX",
    ERR_MSG03       => "MAC_INT",
    ERR_MSG04       => "MAC_DUP",
    ERR_MSG05       => "MAC_TBL",
    ERR_MSG06       => "MII_RX",
    ERR_MSG07       => "MII_TX",
    ERR_MSG08       => "PKT_CRC")
    port map(
    err_uart        => status_uart,
    aux_data        => status_aux_dat,
    aux_wren        => status_aux_wr,
    err_strobe      => error_vec,
    err_clk         => scrub_clk,
    reset_p         => reset_p);

-- Steady breathing LED pattern repeating every 3.0 seconds.
-- Aesthetic goal: 64 * DIV * PREDIV = 3 * SCRUB_CLK_HZ
u_grn : breathe_led
    generic map(
    RATE    => (3 * SCRUB_CLK_HZ) / 65536,
    PREDIV  => 1024,
    LED_LIT => STATUS_LED_LIT)
    port map(
    LED     => status_led_grn,
    Clk     => scrub_clk);

-- Clock-stopped strobe: Exponential decay with time-constant ~1/16 second.
-- Aesthetic goal: 16 * DIV * PREDIV = SCRUB_CLK_HZ / 16
u_ylw : sustain_exp_led
    generic map(
    DIV      => SCRUB_CLK_HZ / 262144,
    PREDIV   => 1024,
    LED_LIT  => '1')
    port map(
    LED     => status_led_ylw,
    Clk     => scrub_clk,
    pulse   => clock_stopped);

-- Switch error strobe: Exponential decay with time-constant ~1/16 second.
-- Aesthetic goal: 16 * DIV * PREDIV = SCRUB_CLK_HZ / 16
u_red : sustain_exp_led
    generic map(
    DIV      => SCRUB_CLK_HZ / 262144,
    PREDIV   => 1024,
    LED_LIT  => STATUS_LED_LIT)
    port map(
    LED     => status_led_red,
    Clk     => scrub_clk,
    pulse   => error_any);

end switch_aux;
