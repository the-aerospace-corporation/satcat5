--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Drop-in replacement for the Xilinx "Processing System Reset Module"
--
-- The Xilinx Processing System Reset Module v5.0 has a bug where it
-- can become stuck in the reset state.  This replacement omits some
-- features but operates correctly. Signal names mimic the original.
--
-- For more information, refer to Xilinx PG164, Figure 2-3.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;

entity ublaze_reset is
    generic (
    EXT_RESET_POL           : std_logic := '0';     -- Reset if ext_reset_in = EXT_RESET_POL
    SEQUENCE_DELAY          : positive := 16);      -- Hold each stage for N clocks
    port (
    slowest_sync_clk        : in  std_logic;
    ext_reset_in            : in  std_logic;        -- Reset if ext_reset_in = EXT_RESET_POL
    aux_reset_in            : in  std_logic := '0'; -- Active high async reset
    mb_debug_sys_rst        : in  std_logic := '0'; -- Active high async reset
    dcm_locked              : in  std_logic := '1'; -- Active low async reset
    bus_struct_reset        : out std_logic;        -- Active high, released 1st
    peripheral_reset        : out std_logic;        -- Active high, released 2nd
    mb_reset                : out std_logic;        -- Active high, released 3rd
    interconnect_aresetn    : out std_logic;        -- Inverse of bus_struct_reset
    peripheral_aresetn      : out std_logic);       -- Inverse of peripheral_reset
end ublaze_reset;

architecture ublaze_reset of ublaze_reset is

-- Input buffering.
signal buf_aux : std_logic;
signal buf_dbg : std_logic;
signal buf_dcm : std_logic;
signal buf_ext : std_logic;

-- Polarity conversion.
signal req_vec : std_logic_vector(3 downto 0);

-- Output sequencing.
constant CTR_MAX : integer := 3 * SEQUENCE_DELAY;
signal counter  : integer range 0 to CTR_MAX := 0;
signal rst_seq  : std_logic_vector(2 downto 0) := (others => '1');

begin

-- Synchronize each of the input signals.
u_sync_aux : sync_buffer
    port map(
    in_flag     => aux_reset_in,
    out_flag    => buf_aux,
    out_clk     => slowest_sync_clk);
u_sync_dbg : sync_buffer
    port map(
    in_flag     => mb_debug_sys_rst,
    out_flag    => buf_dbg,
    out_clk     => slowest_sync_clk);
u_sync_dcm : sync_buffer
    port map(
    in_flag     => dcm_locked,
    out_flag    => buf_dcm,
    out_clk     => slowest_sync_clk);
u_sync_ext : sync_buffer
    port map(
    in_flag     => ext_reset_in,
    out_flag    => buf_ext,
    out_clk     => slowest_sync_clk);

-- Convert buffered requests to active-high.
req_vec(0) <= bool2bit(buf_aux = '1');
req_vec(1) <= bool2bit(buf_dbg = '1');
req_vec(2) <= bool2bit(buf_dcm = '0');
req_vec(3) <= bool2bit(buf_ext = EXT_RESET_POL);

-- Output sequencing state machine.
p_seq : process(slowest_sync_clk)
begin
    if rising_edge(slowest_sync_clk) then
        -- Sequenced synchronous resets, starting with index zero.
        for n in rst_seq'range loop
            rst_seq(n) <= bool2bit(counter < (n+1) * SEQUENCE_DELAY);
        end loop;
        -- Count cycles since release of all reset requests.
        if (or_reduce(req_vec) = '1') then
            counter <= 0;
        elsif (counter < CTR_MAX) then
            counter <= counter + 1;
        end if;
    end if;
end process;

-- Drive named outputs.
bus_struct_reset        <=     rst_seq(0);
interconnect_aresetn    <= not rst_seq(0);
peripheral_reset        <=     rst_seq(1);
peripheral_aresetn      <= not rst_seq(1);
mb_reset                <=     rst_seq(2);

end ublaze_reset;
