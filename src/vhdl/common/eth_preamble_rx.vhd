--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet preamble removal
--
-- This block is the counterpart to "eth_preamble_tx".  It removes the
-- standard Ethernet preamble and start-of-frame token, leaving only the
-- header, payload data and frame-check sequence.
--
-- Optionally, the block can be used to count repeated start-of-frame
-- tokens to auto-detect the rate-adaptation used by certain xMII
-- protocols.  (e.g., SGMII, refer to Cisco ENG-46158.)  The repetition
-- rate is refreshed at the start of each incoming frame, and is made
-- available for configuration of the matching preamble-insertion block.
--
-- For more information, refer to:
-- https://en.wikipedia.org/wiki/Ethernet_frame
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity eth_preamble_rx is
    generic (
    DV_XOR_ERR  : boolean := false;     -- RGMII mode (DV xor ERR)
    REP_ENABLE  : boolean := false);    -- Enable repeat-detect?
    port (
    -- Received data stream
    raw_clk     : in  std_logic;        -- Received clock
    raw_lock    : in  std_logic;        -- Clock detect OK
    raw_cken    : in  std_logic := '1'; -- Clock-enable
    raw_data    : in  byte_t;
    raw_dv      : in  std_logic;        -- Data valid
    raw_err     : in  std_logic;        -- Error flag

    -- Line-rate reporting (see switch_types::get_rate_word)
    rate_word   : in  port_rate_t;

    -- Received message timestamps, if enabled.
    rx_tstamp   : in  tstamp_t := TSTAMP_DISABLED;

    -- Repeat detection (each input byte repeated N+1 times)
    rep_rate    : out byte_u;
    rep_valid   : out std_logic;

    -- Additional error strobe (optional)
    aux_err     : in  std_logic := '0';

    -- Diagnostic status signals
    status      : in  port_status_t;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s);
end eth_preamble_rx;

architecture rtl of eth_preamble_rx is

type state_t is (
    STATE_IDLE,     -- Waiting for start of frame (SOF)
    STATE_SOF,      -- Received SOF, counting repeats
    STATE_DATA);    -- Received first data byte

signal out_data     : byte_t := (others => '0');
signal out_write    : std_logic := '0';
signal out_last     : std_logic := '0';

signal reg_st       : state_t := STATE_IDLE;
signal reg_data     : byte_t := (others => '0');
signal reg_dv       : std_logic := '0';
signal reg_err      : std_logic := '0';
signal reg_ctr      : byte_u := (others => '0');    -- Working counter
signal reg_rpt      : byte_u := (others => '0');    -- Reference repeat rate
signal got_rpt      : std_logic := '0';

signal err_dlyct    : unsigned(2 downto 0) := (others => '0');

begin

-- Drive top-level outputs.
rx_data.clk     <= raw_clk;
rx_data.reset_p <= not raw_lock;
rx_data.data    <= out_data;
rx_data.write   <= out_write;
rx_data.last    <= out_last;
rx_data.rxerr   <= bool2bit(err_dlyct > 0);
rx_data.rate    <= rate_word;
rx_data.status  <= status;
rx_data.tsof    <= rx_tstamp;
rep_rate        <= reg_rpt;
rep_valid       <= got_rpt;

-- Internal state machine.
p_rx : process(raw_clk)
begin
    if rising_edge(raw_clk) then
        -- Drive the next-word and EOF strobes, including decimation.
        if (raw_lock = '0' or raw_cken = '0' or reg_st /= STATE_DATA) then
            out_write <= '0';   -- No new data this cycle
            out_last  <= '0';
        elsif (reg_dv = '1' and raw_dv = '0') then
            out_write <= '1';   -- End of frame
            out_last  <= '1';   -- (Even if final repeat is truncated)
        else
            out_write <= reg_dv and bool2bit(reg_ctr = 0);
            out_last  <= '0';   -- Keep the last byte in each window
        end if;

        -- Watch for start-of-frame delimiter and optionally count repeats.
        -- Note: Repeat-counter will fail if first byte of frame constains
        --       0xD5, but I believe that would be an illegal MAC address.
        if (raw_lock = '0') then
            reg_st  <= STATE_IDLE;          -- Port reset
            reg_ctr <= (others => '0');
            reg_rpt <= (others => '0');
            got_rpt <= '0';
        elsif (raw_cken = '0') then
            null;                           -- No change
        elsif (raw_dv = '0') then
            reg_st  <= STATE_IDLE;          -- End of frame
            reg_ctr <= (others => '0');
        elsif (reg_st = STATE_IDLE and raw_data = ETH_AMBLE_SOF) then
            reg_st  <= STATE_SOF;           -- SOF received (0xD5)
        elsif (reg_st = STATE_SOF) then
            -- If repeat-detect is enabled, count SOF tokens to determine
            -- the underlying repetition rate. (Allowed rates depend on
            -- standard; parent should check for unexpected values.)
            if (REP_ENABLE and raw_data = ETH_AMBLE_SOF) then
                reg_ctr <= reg_ctr + 1;     -- Count repeated SOF
            else
                reg_st  <= STATE_DATA;      -- First data byte
                reg_rpt <= reg_ctr;         -- Latch repeat count
                got_rpt <= '1';
            end if;
        elsif (reg_st = STATE_DATA and REP_ENABLE) then
            -- If repeat-detect is enabled, run a cyclic countdown during
            -- data portion so we can keep exactly one of each repeated byte.
            if (reg_ctr > 0) then
                reg_ctr <= reg_ctr - 1;     -- Countdown to zero
            else
                reg_ctr <= reg_rpt;         -- Counter wraparound
            end if;
        end if;

        -- Falling edge of data-valid (DV) marks end of input.
        -- Delay buffer lets us assert "last" strobe at the appropriate time.
        if (raw_cken = '1') then
            out_data <= reg_data;
            reg_data <= raw_data;
            reg_dv   <= raw_dv;
            if (DV_XOR_ERR) then
                -- RGMII mode: Only flag data-reception errors.
                reg_err <= raw_dv and not raw_err;
            else
                -- All others: Forward the error flag verbatim.
                reg_err <= raw_err;
            end if;
        end if;

        -- Sustain async error strobe for a few clock-cycles.
        if (aux_err = '1' or reg_err = '1') then
            err_dlyct <= (others => '1');
        elsif (err_dlyct > 0) then
            err_dlyct <= err_dlyct - 1;
        end if;
    end if;
end process;

end rtl;
