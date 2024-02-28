--------------------------------------------------------------------------
-- Copyright 2019-2020 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Wrapper for Xilinx Soft Error Management (SEM) core
--
-- This file defines a thin-wrapper for the Xilinx SEM core, which provides
-- automatic scrubbing of FPGA configuration memory.  The core corrects errors
-- up to two bits per frame, and detects almost all other errors.  The wrapper
-- monitors the core's status pins, providing a simple strobe every time an
-- error is detected.  The interface is simplified for commonality with similar
-- functions on other FPGA platforms.
--
-- The most important caveat is the clock.  Because the SEM core has no
-- external reset signal, it is imperative that the clock be stable BEFORE
-- the FPGA releases its global configuration reset.  Raw external clocks
-- meet this constraint.  Synthesized clocks from a DCM or PLL are not
-- sufficient unless buffered through a BUFGCE.  The clock frequency should
-- be as close as possible to the maximum maximum ICAP frequency, which
-- is 100 MHz for Kintex-7 devices.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;

entity scrub_generic is
    port (
    clk_raw : in  std_logic;        -- SEM/ICAP clock (See notes above)
    err_out : out std_logic);       -- Strobe on scrub error
end scrub_generic;

architecture xilinx of scrub_generic is

-- Interface to Xilinx SEM core:
component sem_0 is
    port (
    status_heartbeat : out std_logic;
    status_initialization : out std_logic;
    status_observation : out std_logic;
    status_correction : out std_logic;
    status_classification : out std_logic;
    status_injection : out std_logic;
    status_essential : out std_logic;
    status_uncorrectable : out std_logic;
    monitor_txdata : out std_logic_vector ( 7 downto 0 );
    monitor_txwrite : out std_logic;
    monitor_txfull : in std_logic;
    monitor_rxdata : in std_logic_vector ( 7 downto 0 );
    monitor_rxread : out std_logic;
    monitor_rxempty : in std_logic;
    icap_o : in std_logic_vector ( 31 downto 0 );
    icap_csib : out std_logic;
    icap_rdwrb : out std_logic;
    icap_i : out std_logic_vector ( 31 downto 0 );
    icap_clk : in std_logic;
    icap_request : out std_logic;
    icap_grant : in std_logic;
    fecc_crcerr : in std_logic;
    fecc_eccerr : in std_logic;
    fecc_eccerrsingle : in std_logic;
    fecc_syndromevalid : in std_logic;
    fecc_syndrome : in std_logic_vector ( 12 downto 0 );
    fecc_far : in std_logic_vector ( 25 downto 0 );
    fecc_synbit : in std_logic_vector ( 4 downto 0 );
    fecc_synword : in std_logic_vector ( 6 downto 0 ));
end component;

-- Core status
signal stat_correction      : std_logic;
signal stat_uncorrectable   : std_logic;

-- ICAP control port
signal icap_o               : std_logic_vector(31 downto 0);
signal icap_csib            : std_logic;
signal icap_rdwrb           : std_logic;
signal icap_i               : std_logic_vector(31 downto 0);

-- FECC control port
signal fecc_crcerr          : std_logic;
signal fecc_eccerr          : std_logic;
signal fecc_eccerrsingle    : std_logic;
signal fecc_syndromevalid   : std_logic;
signal fecc_syndrome        : std_logic_vector(12 downto 0);
signal fecc_far             : std_logic_vector(25 downto 0);
signal fecc_synbit          : std_logic_vector(4 downto 0);
signal fecc_synword         : std_logic_vector(6 downto 0);

-- Error detection logic for main output.
signal err_out_i            : std_logic := '0';

begin

-- Instantiate the SEM core.
u_sem : sem_0
    port map (
    status_heartbeat        => open,
    status_initialization   => open,
    status_observation      => open,
    status_correction       => stat_correction,
    status_classification   => open,
    status_injection        => open,    -- Not used
    status_essential        => open,    -- Feature not supported
    status_uncorrectable    => stat_uncorrectable,
    monitor_txdata          => open,
    monitor_txwrite         => open,
    monitor_txfull          => '0',   -- Don't wait if full
    monitor_rxdata          => (others => '0'),
    monitor_rxread          => open,
    monitor_rxempty         => '1',
    icap_o                  => icap_o,
    icap_csib               => icap_csib,
    icap_rdwrb              => icap_rdwrb,
    icap_i                  => icap_i,
    icap_clk                => clk_raw,
    icap_request            => open,  -- Reserved (see PG036)
    icap_grant              => '1',
    fecc_crcerr             => fecc_crcerr,
    fecc_eccerr             => fecc_eccerr,
    fecc_eccerrsingle       => fecc_eccerrsingle,
    fecc_syndromevalid      => fecc_syndromevalid,
    fecc_syndrome           => fecc_syndrome,
    fecc_far                => fecc_far,
    fecc_synbit             => fecc_synbit,
    fecc_synword            => fecc_synword);

-- Instantiate the FECC and ICAP hardware primitives.
u_fecc : FRAME_ECCE2
    generic map (
    FARSRC          => "EFAR",          -- "FAR" or "EFAR" mode
    FRAME_RBT_IN_FILENAME => "None")    -- Raw bitstream for simulation
    port map (
    crcerror        => fecc_crcerr,
    eccerror        => fecc_eccerr,
    eccerrorsingle  => fecc_eccerrsingle,
    far             => fecc_far,
    synbit          => fecc_synbit,
    syndrome        => fecc_syndrome,
    syndromevalid   => fecc_syndromevalid,
    synword         => fecc_synword);

u_icap : ICAPE2
    generic map (
    ICAP_WIDTH => "X32",            -- Bus I/O width
    SIM_CFG_FILE_NAME => "None")    -- Raw bitstream for simulation
    port map (
    o       => icap_o,
    csib    => icap_csib,
    rdwrb   => icap_rdwrb,
    i       => icap_i,
    clk     => clk_raw);

-- Error detection strobe.
err_out <= err_out_i;

p_error : process(clk_raw)
    variable prev_correction : std_logic := '0';
begin
    if rising_edge(clk_raw) then
        -- Classify errors by looking at the "status_uncorrectable" flag
        -- as the SEM controller exits the "status_correction" state.
        if (prev_correction = '1' and stat_correction = '0') then
            err_out_i <= '1';
            if (stat_uncorrectable = '1') then
                report "SEM: Uncorrectable error." severity warning;
            else
                report "SEM: Correctable error." severity warning;
            end if;
        else
            err_out_i <= '0';
        end if;
        prev_correction := stat_correction;
    end if;
end process;

end;
