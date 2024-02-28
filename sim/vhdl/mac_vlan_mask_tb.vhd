--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Virtual-LAN port mask lookup block
--
-- This testbench configures a variety of VLAN port-masks, and confirms
-- that the unit under test produces the expected metadata.
--
-- The complete test takes less than 1.3 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity mac_vlan_mask_tb is
    generic (PORT_COUNT : positive := 8);
    -- Testbench has no top-level I/O.
end mac_vlan_mask_tb;

architecture tb of mac_vlan_mask_tb is

constant REGADDR_V  : integer := 42;
constant REGADDR_M  : integer := 43;
subtype port_idx_t is integer range 0 to PORT_COUNT-1;
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- Load a fixed configuration into the VID lookup table.
function get_pmask(vid : integer) return port_mask_t is
    variable tmp : std_logic_vector(31 downto 0) := i2s(17*vid + 1234, 32);
begin
    return tmp(PORT_COUNT-1 downto 0);
end function;

-- Is the current port a legal member of the current VLAN?
function is_member(psrc : port_idx_t; vid : vlan_vid_t) return std_logic is
    variable tmp : port_mask_t := get_pmask(to_integer(vid));
begin
    if (psrc < PORT_COUNT) then
        return tmp(psrc);
    else
        return '0';
    end if;
end function;

-- Clock and reset generation
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input, reference, and output streams.
signal in_psrc      : port_idx_t := 0;
signal in_vtag      : vlan_hdr_t := (others => '0');
signal in_error     : std_logic := '0';
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';

signal ref_psrc     : port_idx_t := 0;
signal ref_vtag     : vlan_hdr_t := (others => '0');
signal ref_vid      : vlan_vid_t := (others => '0');
signal ref_error    : std_logic := '0';
signal ref_pmask    : port_mask_t;
signal ref_hipri    : std_logic;

signal out_vtag     : vlan_hdr_t;
signal out_pmask    : std_logic_vector(PORT_COUNT-1 downto 0);
signal out_hipri    : std_logic;
signal out_next     : std_logic;

-- Configuration interface (write-only)
signal cfg_cmd      : cfgbus_cmd;
signal cfg_done     : std_logic := '0';
signal rate_in      : real := 0.0;

begin

-- Clock and reset generation
clk100 <= not clk100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
cfg_cmd.clk <= clk100;

-- Input and reference stream generation.
p_input : process(clk100)
    -- Two synchronized PRNGs.
    constant SEED1  : positive := 123456;
    constant SEED2  : positive := 987654;
    variable iseed1 : positive := SEED1;    -- Input data
    variable iseed2 : positive := SEED2;
    variable rseed1 : positive := SEED1;    -- Reference data
    variable rseed2 : positive := SEED2;

    -- Get a random VLAN tag or error flag.
    variable tmp_src : port_idx_t;
    variable tmp_tag : vlan_hdr_t;
    variable tmp_err : std_logic;

    procedure syncrand_port(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        uniform(s1, s2, rand);
        tmp_src := integer(floor(rand * real(PORT_COUNT)));
    end procedure;

    procedure syncrand_vtag(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        for n in tmp_tag'range loop
            uniform(s1, s2, rand);
            tmp_tag(n) := bool2bit(rand < 0.5);
        end loop;
    end procedure;

    procedure syncrand_error(variable s1,s2: inout positive) is
        variable rand : real := 0.0;
    begin
        uniform(s1, s2, rand);
        tmp_err := bool2bit(rand < 0.02);
    end procedure;
begin
    if rising_edge(clk100) then
        -- Reset synchronized PRNG state.
        if (reset_p = '1') then
            iseed1  := SEED1;
            iseed2  := SEED2;
            rseed1  := SEED1;
            rseed2  := SEED2;
        end if;

        -- Generate the next input word?
        if (reset_p = '1' or (in_write = '1' and in_last = '1')) then
            syncrand_port (iseed1, iseed2); in_psrc <= tmp_src;
            syncrand_vtag (iseed1, iseed2); in_vtag <= tmp_tag;
            syncrand_error(iseed1, iseed2); in_error <= tmp_err;
        end if;

        -- Generate the next reference word?
        if (reset_p = '1' or out_next = '1') then
            syncrand_port (rseed1, rseed2); ref_psrc <= tmp_src;
            syncrand_vtag (rseed1, rseed2); ref_vtag <= tmp_tag;
            syncrand_error(rseed1, rseed2); ref_error <= tmp_err;
        end if;

        -- Flow-control randomization.
        in_last  <= rand_bit(rate_in);
        in_write <= rand_bit(rate_in);
    end if;
end process;

-- Other reference signals are derived with combinational logic:
ref_vid   <= vlan_get_vid(ref_vtag);
ref_hipri <= bool2bit(vlan_get_pcp(ref_vtag) >= 4);
ref_pmask <= (others => '0') when (ref_error = '1')
        else (others => '0') when (ref_vid = VID_NONE)
        else (others => '0') when (ref_vid = VID_RSVD)
        else (others => '1') when (cfg_done = '0')
        else (others => '0') when (is_member(ref_psrc, ref_vid) = '0')
        else get_pmask(to_integer(ref_vid));

-- Unit under test
uut : entity work.mac_vlan_mask
    generic map(
    DEV_ADDR    => CFGBUS_ADDR_ANY,
    REG_ADDR_V  => REGADDR_V,
    REG_ADDR_M  => REGADDR_M,
    PORT_COUNT  => PORT_COUNT)
    port map(
    in_psrc     => in_psrc,
    in_vtag     => in_vtag,
    in_error    => in_error,
    in_last     => in_last,
    in_write    => in_write,
    out_vtag    => out_vtag,
    out_pmask   => out_pmask,
    out_hipri   => out_hipri,
    out_valid   => out_next,
    out_ready   => '1',     -- Not tested
    cfg_cmd     => cfg_cmd,
    clk         => clk100,
    reset_p     => reset_p);

-- Check output against reference.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (out_next = '1') then
            assert (out_vtag = ref_vtag)
                report "VTAG mismatch" severity error;
            assert (out_pmask = ref_pmask)
                report "PMASK mismatch" severity error;
            assert (out_hipri = ref_hipri)
                report "HIPRI mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure load_table is
        variable cfg : cfgbus_word := (others => '0');
    begin
        -- Shut down input and allow pipeline to flush.
        rate_in <= 0.0;
        wait for 1 us;

        -- Load the new table contents.
        cfgbus_write(cfg_cmd, 0, REGADDR_V, x"00000000");
        for n in 0 to 4095 loop
            cfg := resize(get_pmask(n), CFGBUS_WORD_SIZE);
            cfgbus_write(cfg_cmd, 0, REGADDR_M, cfg);
        end loop;

        -- Short wait to be sure table contents are settled.
        cfg_done <= '1';
        wait for 1 us;
    end procedure;

    procedure run(rate : real) is
    begin
        rate_in <= rate;
        wait for 200 us;
    end procedure;
begin
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Check the default config.
    run(1.0);
    run(0.9);
    run(0.5);

    -- Load configuration table.
    load_table;

    -- Check the custom config.
    run(1.0);
    run(0.9);
    run(0.5);
    report "All tests completed!";
end process;

end tb;
