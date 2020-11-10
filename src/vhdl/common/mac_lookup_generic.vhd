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
-- MAC-address lookup, generic wrapper
--
-- This simple wrapper instantiates the selected implementation of the
-- MAC lookup table.  The possible options are:
--  * BINARY    - Binary search through BRAM, slow but scales well
--  * BRUTE     - Brute-force matching, resource hog but very fast
--  * LUTRAM    - Two-stage CAM using LUTRAM, fast with moderate size
--  * PARSHIFT  - Partially parallelized search, balanced size/speed
--  * SIMPLE    - Naive search, lightweight but very slow
--  * STREAM    - Fast and lightweight, but only one address per port
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_generic is
    generic (
    IMPL_TYPE       : string;       -- Type: BINARY, STREAM, etc.
    INPUT_WIDTH     : integer;      -- Width of main data port
    PORT_COUNT      : integer;      -- Number of Ethernet ports
    TABLE_SIZE      : integer;      -- Max stored MAC addresses
    SCRUB_TIMEOUT   : integer);     -- Timeout for stale entries
    port (
    -- Main input (Ethernet frame) uses AXI-stream flow control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_data         : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Search result is the port mask for the destination port(s).
    out_pdst        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- Promiscuous-port flag.
    cfg_prmask      : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- Scrub interface
    scrub_req       : in  std_logic;
    scrub_busy      : out std_logic;
    scrub_remove    : out std_logic;

    -- Error strobes
    error_full      : out std_logic;    -- No room for new address
    error_table     : out std_logic;    -- Table integrity check failed

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_generic;

architecture mac_lookup_generic of mac_lookup_generic is

signal in_pmask : std_logic_vector(PORT_COUNT-1 downto 0);

begin

-- Convert source port-index to a port-mask.
p_mask_convert : process(in_psrc)
begin
    for n in in_pmask'range loop
        in_pmask(n) <= bool2bit(n = in_psrc);
    end loop;
end process;

-- Instantiate the selected option.
gen_binary : if (IMPL_TYPE = "BINARY") generate
    u_mac : entity work.mac_lookup_binary
        generic map(
        INPUT_WIDTH     => INPUT_WIDTH,
        PORT_COUNT      => PORT_COUNT,
        TABLE_SIZE      => TABLE_SIZE,
        SCRUB_TIMEOUT   => SCRUB_TIMEOUT)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        scrub_req       => scrub_req,
        scrub_busy      => scrub_busy,
        scrub_remove    => scrub_remove,
        cfg_prmask      => cfg_prmask,
        error_full      => error_full,
        error_table     => error_table,
        clk             => clk,
        reset_p         => reset_p);
end generate;

gen_brute : if (IMPL_TYPE = "BRUTE") generate
    u_mac : entity work.mac_lookup_brute
        generic map(
        INPUT_WIDTH     => INPUT_WIDTH,
        PORT_COUNT      => PORT_COUNT,
        TABLE_SIZE      => TABLE_SIZE)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        cfg_prmask      => cfg_prmask,
        error_full      => error_full,
        error_table     => error_table,
        clk             => clk,
        reset_p         => reset_p);

    scrub_busy   <= '0'; -- Unused
    scrub_remove <= '0'; -- Unused
end generate;

gen_lutram : if (IMPL_TYPE = "LUTRAM") generate
    u_mac : entity work.mac_lookup_lutram
        generic map(
        INPUT_WIDTH     => INPUT_WIDTH,
        PORT_COUNT      => PORT_COUNT,
        TABLE_SIZE      => TABLE_SIZE)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        cfg_prmask      => cfg_prmask,
        error_full      => error_full,
        error_table     => error_table,
        clk             => clk,
        reset_p         => reset_p);

    scrub_busy   <= '0'; -- Unused
    scrub_remove <= '0'; -- Unused
end generate;

gen_parshift : if (IMPL_TYPE = "PARSHIFT") generate
    u_mac : entity work.mac_lookup_parshift
        generic map(
        INPUT_WIDTH     => INPUT_WIDTH,
        PORT_COUNT      => PORT_COUNT,
        TABLE_SIZE      => TABLE_SIZE)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        cfg_prmask      => cfg_prmask,
        error_full      => error_full,
        error_table     => error_table,
        clk             => clk,
        reset_p         => reset_p);

    scrub_busy   <= '0'; -- Unused
    scrub_remove <= '0'; -- Unused
end generate;

gen_simple : if (IMPL_TYPE = "SIMPLE") generate
    u_mac : entity work.mac_lookup_simple
        generic map(
        INPUT_WIDTH     => INPUT_WIDTH,
        PORT_COUNT      => PORT_COUNT,
        TABLE_SIZE      => TABLE_SIZE,
        SCRUB_TIMEOUT   => SCRUB_TIMEOUT)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        scrub_req       => scrub_req,
        scrub_busy      => scrub_busy,
        scrub_remove    => scrub_remove,
        cfg_prmask      => cfg_prmask,
        error_full      => error_full,
        clk             => clk,
        reset_p         => reset_p);

    error_table <= '0'; -- Unused
end generate;

gen_stream : if (IMPL_TYPE = "STREAM") generate
    u_mac : entity work.mac_lookup_stream
        generic map(
        PORT_COUNT      => PORT_COUNT)
        port map(
        in_psrc         => in_pmask,
        in_data         => in_data,
        in_last         => in_last,
        in_valid        => in_valid,
        in_ready        => in_ready,
        out_pdst        => out_pdst,
        out_valid       => out_valid,
        out_ready       => out_ready,
        cfg_prmask      => cfg_prmask,
        clk             => clk,
        reset_p         => reset_p);

    error_full   <= '0'; -- Unused
    error_table  <= '0'; -- Unused
    scrub_busy   <= '0'; -- Unused
    scrub_remove <= '0'; -- Unused
end generate;

end mac_lookup_generic;
