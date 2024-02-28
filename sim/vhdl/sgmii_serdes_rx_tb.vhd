--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Xilinx SGMII SERDES block.
--
-- This block is a self-contained unit test for the Xilinx SGMII SERDES.
-- It generates an LFSR sequence at 5 Gbps, and confirms that the output
-- is sampled correctly.  The sequence is unrealistically fast, but it
-- should work just fine in simulation.
--
-- The complete test takes ??? milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.lfsr_sim_types.all;

entity sgmii_serdes_rx_tb is
    -- Unit testbench, no I/O
end sgmii_serdes_rx_tb;

architecture tb of sgmii_serdes_rx_tb is

-- Clock and reset.
signal clk_125      : std_logic := '0';
signal clk_200      : std_logic := '0';
signal clk_625_00   : std_logic := '0';
signal clk_625_90   : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Source and reference LFSR.
signal src_data     : std_logic := '0';
signal ref_data     : std_logic_vector(39 downto 0) := (others => '0');
signal ref_locked   : std_logic := '0';

-- Unit under test
signal RxD_p_pin    : std_logic;
signal RxD_n_pin    : std_logic;
signal out_data     : std_logic_vector(39 downto 0);
signal out_next     : std_logic;

-- Overall test status
signal count_words  : integer := 0;
signal count_errs   : integer := 0;

begin

-- Clock and reset
clk_125     <= not clk_125 after 4.0 ns;    -- 1/(2*4.0ns) = 125 MHz
clk_200     <= not clk_200 after 2.5 ns;    -- 1/(2*2.5ns) = 200 MHz
clk_625_00  <= not clk_625_00 after 0.8 ns; -- 1/(2*0.8ns) = 625 MHz
clk_625_90  <= clk_625_00 after 0.4 ns;     -- Quarter-cycle delay
reset_p     <= '0' after 100 ns;            -- Briefly hold reset

-- Input stream generation at 5 Gbps
p_input : process
    variable lfsr : lfsr_state := LFSR_RESET;
begin
    src_data <= lfsr_out_next(lfsr);
    lfsr_incr(lfsr);
    wait for 0.2 ns;
end process;

RxD_p_pin <= src_data;
RxD_n_pin <= not src_data;

-- Unit under test
uut : entity work.sgmii_serdes_rx
    port map(
    RxD_p_pin   => RxD_p_pin,
    RxD_n_pin   => RxD_n_pin,
    out_clk     => clk_200,
    out_data    => out_data,
    out_next    => out_next,
    clk_125     => clk_125,
    clk_625_00  => clk_625_00,
    clk_625_90  => clk_625_90,
    reset_p     => reset_p);

-- Synchronize with output stream
p_check : process(clk_200)
    variable lfsr : lfsr_state := LFSR_RESET;
begin
    if rising_edge(clk_200) then
        -- Once synchronized, check output against reference.
        if (ref_locked = '1' and out_next = '1') then
            if (ref_data /= out_data) then
                report "Output mismatch" severity error;
                count_errs <= count_errs + 1;
            end if;
            count_words <= count_words + 1;
        end if;

        -- Reference LFSR synchronization.
        if (reset_p = '1') then
            -- Reset LFSR state.
            lfsr := LFSR_RESET;
        elsif (out_next = '1' and not lfsr_sync_done(lfsr)) then
            -- Push received data into shift register.
            for n in 39 downto 0 loop   -- MSB first
                lfsr_sync_next(lfsr, out_data(n));
            end loop;
        end if;

        -- Once we have enough data, run LFSR for the next word.
        if (not lfsr_sync_done(lfsr)) then
            ref_locked <= '0';
            ref_data   <= (others => '0');
        elsif (out_next = '1') then
            ref_locked <= '1';
            for n in 39 downto 0 loop    -- MSB-first
                lfsr_incr(lfsr);
                ref_data(n) <= lfsr_out_next(lfsr);
            end loop;
        end if;
    end if;
end process;

end tb;
