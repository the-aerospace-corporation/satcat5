--------------------------------------------------------------------------
-- Copyright 2019-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Internal crosslink port, for multi-tiered switch topologies
--
-- To optimize power and resource constraints, some switch designs
-- instantiate multiple switch_core units.  This block allows such
-- designs to easily interconnect, including designs in which one
-- segment allows runt packets and the other does not.
--
-- To prevent unnecessary buffer overflows, the crosslink can be
-- limited to a fixed 1/N fraction of the maximum transfer rate.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_crosslink is
    generic (
    RUNT_PORTA  : boolean;          -- Allow runt packets on Port A?
    RUNT_PORTB  : boolean;          -- Allow runt packets on Port B?
    RATE_DIV    : positive := 2;    -- Rate limit of 1/N
    REF_CLK_HZ  : natural := 0;     -- Transfer clock rate (for PTP)
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- Internal interface for Port A.
    rxa_data    : out port_rx_m2s;
    txa_data    : in  port_tx_s2m;
    txa_ctrl    : out port_tx_m2s;

    -- Internal interface for Port B.
    rxb_data    : out port_rx_m2s;
    txb_data    : in  port_tx_s2m;
    txb_ctrl    : out port_tx_m2s;

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Other control
    ref_clk     : in  std_logic;    -- Transfer clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_crosslink;

architecture port_crosslink of port_crosslink is

-- Do we need to pad packets coming from each segment?
constant PAD_REQ_A2B : boolean := RUNT_PORTA and not RUNT_PORTB;
constant PAD_REQ_B2A : boolean := RUNT_PORTB and not RUNT_PORTA;

-- Synchronized reset signal.
signal reset_sync       : std_logic;

-- Precision timestamps, if enabled.
signal lcl_tstamp       : tstamp_t := TSTAMP_DISABLED;
signal lcl_tvalid       : std_logic := '0';

-- Rate limiter state machine.
signal rxa_data_valid   : std_logic := '0';
signal rxb_data_valid   : std_logic := '0';
signal xfer_ready       : std_logic := '0';

begin

-- Drive clocks and control signals for each port.
rxa_data.clk        <= ref_clk;
rxa_data.rxerr      <= '0';
rxa_data.rate       <= get_rate_word(1000 / RATE_DIV);
rxa_data.status     <= (0 => reset_sync, others => '0');
rxa_data.tsof       <= lcl_tstamp;
rxa_data.reset_p    <= reset_sync;
rxa_data.write      <= rxa_data_valid and xfer_ready;

txa_ctrl.clk        <= ref_clk;
txa_ctrl.tnow       <= lcl_tstamp;
txa_ctrl.pstart     <= xfer_ready;
txa_ctrl.txerr      <= '0';
txa_ctrl.reset_p    <= reset_sync;

rxb_data.clk        <= ref_clk;
rxb_data.rxerr      <= '0';
rxb_data.rate       <= get_rate_word(1000 / RATE_DIV);
rxb_data.status     <= (others => '0');
rxb_data.tsof       <= lcl_tstamp;
rxb_data.reset_p    <= reset_sync;
rxb_data.write      <= rxb_data_valid and xfer_ready;

txb_ctrl.clk        <= ref_clk;
txb_ctrl.pstart     <= xfer_ready;
txb_ctrl.tnow       <= lcl_tstamp;
txb_ctrl.txerr      <= '0';
txb_ctrl.reset_p    <= reset_sync;

-- Re-synchronize the reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => ref_clk);

-- If enabled, generate timestamps with a Vernier synchronizer.
gen_ptp : if VCONFIG.input_hz > 0 generate
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => REF_CLK_HZ)
        port map(
        ref_time    => ref_time,
        user_clk    => ref_clk,
        user_ctr    => lcl_tstamp,
        user_lock   => lcl_tvalid,
        user_rst_p  => reset_sync);
end generate;

-- Rate limiter state machine.
p_rate : process(ref_clk)
    constant RATE_MAX : integer := int_max(0, RATE_DIV-1);
    variable count : integer range 0 to RATE_MAX := RATE_MAX;
begin
    if rising_edge(ref_clk) then
        xfer_ready <= bool2bit(count = 0);
        if (reset_sync = '1' or count = 0) then
            count := RATE_MAX;
        else
            count := count - 1;
        end if;
    end if;
end process;

-- Do we need to modify packets from Port A?
gen_a_mod : if PAD_REQ_A2B generate
    -- Pad runt packets up to full size as needed.
    u_adj : entity work.eth_frame_adjust
        port map(
        in_data     => txa_data.data,
        in_last     => txa_data.last,
        in_valid    => txa_data.valid,
        in_ready    => txa_ctrl.ready,
        out_data    => rxb_data.data,
        out_last    => rxb_data.last,
        out_valid   => rxb_data_valid,
        out_ready   => xfer_ready,
        clk         => ref_clk,
        reset_p     => reset_sync);
end generate;

gen_a_pass : if not PAD_REQ_A2B generate
    -- Simple pass-through.
    txa_ctrl.ready <= xfer_ready;
    rxb_data.data  <= txa_data.data;
    rxb_data.last  <= txa_data.last;
    rxb_data_valid <= txa_data.valid;
end generate;

-- Do we need to modify packets from Port B?
gen_b_mod : if PAD_REQ_B2A generate
    -- Pad runt packets up to full size as needed.
    u_adj : entity work.eth_frame_adjust
        port map(
        in_data     => txb_data.data,
        in_last     => txb_data.last,
        in_valid    => txb_data.valid,
        in_ready    => txb_ctrl.ready,
        out_data    => rxa_data.data,
        out_last    => rxa_data.last,
        out_valid   => rxa_data_valid,
        out_ready   => xfer_ready,
        clk         => ref_clk,
        reset_p     => reset_sync);
end generate;

gen_b_pass : if not PAD_REQ_B2A generate
    -- Simple pass-through.
    txb_ctrl.ready <= xfer_ready;
    rxa_data.data  <= txb_data.data;
    rxa_data.last  <= txb_data.last;
    rxa_data_valid <= txb_data.valid;
end generate;

end port_crosslink;
