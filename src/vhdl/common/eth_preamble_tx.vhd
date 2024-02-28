--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet preamble insertion
--
-- The Ethernet standard requires that each packet be preceded by
-- an eight-byte preamble (0x55, 0x55, ..., 0xD5) and followed by
-- at least twelve bytes of idle time.  This file defines the block
-- "eth_preamble_tx", which inserts these fields into the output stream.
--
-- Optionally, the block can also be configured to repeat each data byte
-- (including the amble bytes) by a designated factor.  This is used for
-- SGMII rate-adaptation as described in Cisco ENG-46158.
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

entity eth_preamble_tx is
    generic (
    DV_XOR_ERR  : boolean := false);    -- RGMII mode (DV xor ERR)
    port (
    -- Output data stream
    out_data    : out byte_t;
    out_dv      : out std_logic;
    out_err     : out std_logic;

    -- Auxiliary inputs
    tx_clk      : in  std_logic;        -- Stream clock
    tx_pwren    : in  std_logic;        -- Enable / shutdown-bar
    tx_pkten    : in  std_logic := '1'; -- Allow data packets
    tx_frmst    : in  std_logic := '1'; -- Start-of-frame accepted?
    tx_cken     : in  std_logic := '1'; -- Clock-enable strobe
    tx_idle     : in  std_logic_vector(3 downto 0) := (others => '0');
    tx_tstamp   : in  tstamp_t := TSTAMP_DISABLED;

    -- Byte-repetition: Each input byte is repeated N+1 times.
    -- (Optional. If unused, leave this port disconnected or tied to zero.)
    rep_rate    : in  byte_u := (others => '0');
    rep_read    : out std_logic;        -- For testing only

    -- Generic internal port interface.
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s);
end eth_preamble_tx;

architecture rtl of eth_preamble_tx is

-- Define events at specific byte-counts:
constant COUNT_AMBLE    : integer := 12;    -- Start of preamble
constant COUNT_HOLD     : integer := 13;    -- Preamble hold (tx_frmst flag)
constant COUNT_START    : integer := 19;    -- Start-of-frame token
constant COUNT_FRAME    : integer := 20;    -- Hold until end-of-frame
constant COUNT_MAX      : integer := COUNT_FRAME;

signal fifo_data    : byte_t;
signal fifo_last    : std_logic;
signal fifo_write   : std_logic;
signal fifo_valid   : std_logic;
signal fifo_read    : std_logic;
signal fifo_full    : std_logic;
signal fifo_reset   : std_logic;

signal rep_cken     : std_logic;
signal rep_read_i   : std_logic;
signal rep_ctr      : byte_u := (others => '0');
signal rep_max      : byte_u := (others => '0');

signal reg_ctr      : integer range 0 to COUNT_MAX := 0;
signal reg_data     : byte_t := (others => '0');
signal reg_dv       : std_logic := '0';
signal reg_ready    : std_logic := '0';
signal reg_pstart   : std_logic := '0';

begin

-- Drive top-level outputs.
-- Note: PHY errors should not usually trigger the "txerr" strobe.
out_data        <= reg_data;
out_dv          <= reg_dv;
out_err         <= reg_dv when DV_XOR_ERR else '0';
rep_read        <= rep_read_i;

tx_ctrl.clk     <= tx_clk;
tx_ctrl.ready   <= not fifo_full;
tx_ctrl.pstart  <= reg_pstart;
tx_ctrl.tnow    <= tx_tstamp;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= not tx_pwren;

-- Small FIFO ensures strict AMBA-stream compatibility.
-- (To avoid deadlocks, must not withhold READY until VALID, but
--  we can't start the preamble until we have data available...)
fifo_write      <= tx_data.valid and not fifo_full;
fifo_read       <= rep_cken and reg_ready;
fifo_reset      <= not tx_pwren;

u_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 8)
    port map(
    in_data     => tx_data.data,
    in_last     => tx_data.last,
    in_write    => fifo_write,
    out_data    => fifo_data,
    out_last    => fifo_last,
    out_valid   => fifo_valid,
    out_read    => fifo_read,
    fifo_full   => fifo_full,
    clk         => tx_clk,
    reset_p     => fifo_reset);

-- Byte-repetition counters.
rep_cken   <= tx_pwren and tx_cken and bool2bit(rep_ctr = 0);
rep_read_i <= rep_cken and bool2bit(reg_ctr = COUNT_AMBLE);

p_rep : process(tx_clk)
begin
    if rising_edge(tx_clk) then
        -- Repetition countdown for each byte.
        if (tx_pwren = '0') then
            rep_ctr <= (others => '0');
        elsif (tx_cken = '0') then
            null;   -- No change
        elsif (rep_ctr > 0) then
            rep_ctr <= rep_ctr - 1;
        else
            rep_ctr <= rep_max;
        end if;

        -- Update the setting as we start each packet.
        if (tx_pwren = '0') then
            rep_max <= (others => '0');
        elsif (rep_read_i = '1') then
            rep_max <= rep_rate;
        end if;

        -- Frame-start strobe with deterministic delay (see "ptp_egress.vhd").
        reg_pstart <= tx_frmst and rep_read_i and not fifo_valid;
    end if;
end process;

-- Preamble-insertion state machine.
p_tx : process(tx_clk)
begin
    if rising_edge(tx_clk) then
        if (tx_pwren = '0') then
            -- Reset / shutdown
            reg_ready   <= '0';
            reg_data    <= (others => '0');
            reg_dv      <= '0';
            reg_ctr     <= 0;
        elsif (rep_cken = '1') then
            -- Once we start transmission, FIFO should never run dry.
            assert (reg_ctr <= COUNT_AMBLE or fifo_valid = '1')
                report "Preamble-Tx underflow." severity error;

            -- Upstream flow control helper.
            -- (Assert flag if byte should be read on NEXT iteration.)
            if (reg_ctr = COUNT_FRAME) then
                reg_ready <= not fifo_last; -- Read data up to EOF
            elsif (reg_ctr = COUNT_START) then
                reg_ready <= '1';           -- Always read first byte
            else
                reg_ready <= '0';           -- Idle or preamble
            end if;

            -- Insertion state machine.
            if (reg_ctr < COUNT_AMBLE) then
                -- Pre-frame idle of at least 12 bytes.
                -- (During any idle time, send inter-frame metadata.)
                reg_data <= tx_idle & tx_idle;
                reg_dv   <= '0';
                reg_ctr  <= reg_ctr + 1;
            elsif (reg_ctr = COUNT_AMBLE) then
                -- Are we able to start a new frame?
                if (tx_pkten = '1' and fifo_valid = '1') then
                    -- Start of new frame preamble.
                    reg_data <= ETH_AMBLE_PRE;
                    reg_dv   <= '1';
                    reg_ctr  <= reg_ctr + 1;
                else
                    -- Keep sending idle tokens for now.
                    reg_data <= tx_idle & tx_idle;
                    reg_dv   <= '0';
                end if;
            elsif (reg_ctr = COUNT_HOLD) then
                -- Hold frame preamble until accepted.
                reg_data <= ETH_AMBLE_PRE;
                reg_dv   <= '1';
                if (tx_frmst = '1') then
                    reg_ctr <= reg_ctr + 1;
                end if;
            elsif (reg_ctr < COUNT_START) then
                -- Continue frame preamble (7 bytes total).
                reg_data <= ETH_AMBLE_PRE;
                reg_dv   <= '1';
                reg_ctr  <= reg_ctr + 1;
            elsif (reg_ctr = COUNT_START) then
                -- Start of frame delimiter (1 byte)
                reg_data <= ETH_AMBLE_SOF;
                reg_dv   <= '1';
                reg_ctr  <= reg_ctr + 1;
            elsif (reg_ctr = COUNT_FRAME) then
                -- Normal data transmission.
                reg_data <= fifo_data;
                reg_dv   <= '1';
                if (fifo_valid = '0' or fifo_last = '1') then
                    reg_ctr <= 0;
                end if;
            end if;
        end if;
    end if;
end process;

end rtl;
