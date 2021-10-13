--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- "Switch" for 2 ports. All traffic from one port is forwarded directly
-- to the other port with no MAC filter
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity switch_dual is
    generic (
    ALLOW_JUMBO     : boolean := false; -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;          -- Allow runt frames? (Size < 64 bytes)
    OBUF_KBYTES     : positive);        -- Output buffer size (kilobytes)
    port (
    -- Input from each port.
    ports_rx_data   : in  array_rx_m2s(1 downto 0);

    -- Output to each port.
    ports_tx_data   : out array_tx_s2m(1 downto 0);
    ports_tx_ctrl   : in  array_tx_m2s(1 downto 0);

    -- Error events are marked by toggling these bits.
    errvec_t        : out std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0));
end switch_dual;

architecture switch_dual of switch_dual is

signal errvec_0 : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal errvec_1 : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

begin

-- Compute combined errvec as XOR to preserve all toggles.
-- (May miss both in extremely rare case of simultaneous errors.)
errvec_t <= errvec_0 xor errvec_1;

----------------------------- PORT LOGIC ---------------------------
u_passthrough_0 : entity work.port_passthrough
    generic map(
    ALLOW_JUMBO     => ALLOW_JUMBO,
    ALLOW_RUNT      => ALLOW_RUNT,
    OBUF_KBYTES     => OBUF_KBYTES)
    port map(
    port_rx_data    => ports_rx_data(0),
    port_tx_data    => ports_tx_data(1),
    port_tx_ctrl    => ports_tx_ctrl(1),
    errvec_t        => errvec_0);

u_passthrough_1 : entity work.port_passthrough
    generic map(
    ALLOW_JUMBO     => ALLOW_JUMBO,
    ALLOW_RUNT      => ALLOW_RUNT,
    OBUF_KBYTES     => OBUF_KBYTES)
    port map(
    port_rx_data    => ports_rx_data(1),
    port_tx_data    => ports_tx_data(0),
    port_tx_ctrl    => ports_tx_ctrl(0),
    errvec_t        => errvec_1);

end switch_dual;
