--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Ethernet preamble insertion and removal
--
-- The Ethernet standard requires that each packet be preceded by
-- an eight-byte preamble (0x55, 0x55, ..., 0xD5) and followed by
-- at least twelve bytes of idle time.  This file defines a block
-- that inserts these fields into the output stream, and a separate
-- block that removes the preamble from the input stream.
--
-- For more information, refer to:
-- https://en.wikipedia.org/wiki/Ethernet_frame
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity eth_preamble_rx is
    generic (
    RATE_MBPS   : positive;             -- Line rate, in Mbps
    DV_XOR_ERR  : boolean := false);    -- RGMII mode (DV xor ERR)
    port (
    -- Received data stream
    raw_clk     : in  std_logic;        -- Received clock
    raw_lock    : in  std_logic;        -- Clock detect OK
    raw_cken    : in  std_logic := '1'; -- Clock-enable
    raw_data    : in  std_logic_vector(7 downto 0);
    raw_dv      : in  std_logic;        -- Data valid
    raw_err     : in  std_logic;        -- Error flag

    -- Additional error strobe
    aux_err     : in  std_logic := '0';

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s);
end eth_preamble_rx;

architecture rtl of eth_preamble_rx is

signal out_en       : std_logic := '0';
signal reg_data     : std_logic_vector(7 downto 0) := (others => '0');
signal reg_dv       : std_logic := '0';
signal reg_err      : std_logic := '0';

begin

rx_data.clk     <= raw_clk;
rx_data.reset_p <= not raw_lock;
rx_data.data    <= reg_data;
rx_data.write   <= raw_cken and reg_dv and out_en;
rx_data.last    <= raw_cken and reg_dv and not raw_dv;
rx_data.rxerr   <= (raw_cken and reg_err) or aux_err;
rx_data.rate    <= get_rate_word(RATE_MBPS);

p_rx : process(raw_clk)
begin
    if rising_edge(raw_clk) then
        -- Watch for the start-of-frame delimiter (needs reset).
        if (raw_lock = '0') then
            out_en <= '0';
        elsif (raw_cken = '1' and reg_dv = '0') then
            out_en <= '0';
        elsif (raw_cken = '1' and reg_dv = '1' and reg_data = x"D5") then
            out_en <= '1';
        end if;

        -- Delay buffer for raw signals (no reset needed).
        if (raw_cken = '1') then
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
    end if;
end process;

end rtl;



library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity eth_preamble_tx is
    generic (
    DV_XOR_ERR  : boolean := false);    -- RGMII mode (DV xor ERR)
    port (
    -- Output data stream
    out_data    : out std_logic_vector(7 downto 0);
    out_dv      : out std_logic;
    out_err     : out std_logic;

    -- Auxiliary inputs
    tx_clk      : in  std_logic;        -- Stream clock
    tx_pwren    : in  std_logic;        -- Enable / shutdown-bar
    tx_pkten    : in  std_logic := '1'; -- Allow data packets
    tx_frmst    : in  std_logic := '1'; -- Start-of-frame accepted?
    tx_cken     : in  std_logic := '1'; -- Clock-enable strobe
    tx_idle     : in  std_logic_vector(3 downto 0) := (others => '0');

    -- Generic internal port interface.
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : out port_tx_s2m);
end eth_preamble_tx;

architecture rtl of eth_preamble_tx is

signal fifo_data    : std_logic_vector(7 downto 0);
signal fifo_last    : std_logic;
signal fifo_write   : std_logic;
signal fifo_valid   : std_logic;
signal fifo_read    : std_logic;
signal fifo_full    : std_logic;
signal fifo_reset   : std_logic;

signal reg_data     : std_logic_vector(7 downto 0) := (others => '0');
signal reg_dv       : std_logic := '0';
signal reg_ready    : std_logic := '0';

begin

-- Note: This design never asserts error strobe.

-- Drive top-level outputs.
out_data        <= reg_data;
out_dv          <= reg_dv;
out_err         <= reg_dv when DV_XOR_ERR else '0';

tx_ctrl.clk     <= tx_clk;
tx_ctrl.ready   <= not fifo_full;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= not tx_pwren;

-- Small FIFO ensures strict AMBA-stream compatibility.
-- (To avoid deadlocks, must not withhold READY until VALID, but
--  we can't start the preamble until we have data available...)
fifo_write      <= tx_data.valid and not fifo_full;
fifo_read       <= tx_cken and reg_ready;
fifo_reset      <= not tx_pwren;

u_fifo : entity work.fifo_smol
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

-- Preamble-insertion state machine.
p_tx : process(tx_clk)
    constant COUNT_MAX : integer := 20;
    variable count : integer range 0 to COUNT_MAX := 0;
begin
    if rising_edge(tx_clk) then
        if (tx_pwren = '0') then
            -- Reset / shutdown
            reg_ready   <= '0';
            reg_data    <= (others => '0');
            reg_dv      <= '0';
            count       := 0;
        elsif (tx_cken = '1') then
            -- Upstream flow control.
            if (count >= COUNT_MAX-1) then
                reg_ready <= tx_pkten and not fifo_last;
            else
                reg_ready <= '0';
            end if;

            -- Insertion state machine.
            if (count < 12) then
                -- Pre-frame idle of at least 12 bytes.
                -- (During any idle time, send inter-frame metadata.)
                reg_data <= tx_idle & tx_idle;
                reg_dv   <= '0';
                count    := count + 1;
            elsif (count = 12) then
                -- Are we able to start a new frame?
                if (tx_pkten = '1' and fifo_valid = '1') then
                    -- Start of new frame preamble.
                    reg_data <= x"55";
                    reg_dv   <= '1';
                    count    := count + 1;
                else
                    -- Keep sending idle tokens for now.
                    reg_data <= tx_idle & tx_idle;
                    reg_dv   <= '0';
                end if;
            elsif (count = 13) then
                -- Hold frame preamble until accepted.
                reg_data <= x"55";
                reg_dv   <= '1';
                if (tx_frmst = '1') then
                    count := count + 1;
                end if;
            elsif (count < COUNT_MAX-1) then
                -- Continue frame preamble (7 bytes total).
                reg_data <= x"55";
                reg_dv   <= '1';
                count    := count + 1;
            elsif (count = COUNT_MAX-1) then
                -- Start of frame delimiter (1 byte)
                reg_data <= x"D5";
                reg_dv   <= '1';
                count    := count + 1;
            elsif (count = COUNT_MAX) then
                -- Normal data transmission.
                reg_data <= fifo_data;
                reg_dv   <= '1';
                if (fifo_last = '1') then
                    count := 0;
                end if;
            end if;
        end if;
    end if;
end process;

end rtl;
