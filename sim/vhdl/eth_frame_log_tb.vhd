--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for generation of loggable Ethernet packet descriptors
--
-- This testbench streams traffic with a mixture of valid and invalid
-- frames, then conbriems that each one is tagged correctly.
--
-- The complete test takes 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity eth_frame_log_tb_single is
    generic (
    INPUT_BYTES : positive;
    FILTER_MODE : boolean;
    OUT_BUFFER  : boolean;
    PORT_COUNT  : positive);
end eth_frame_log_tb_single;

architecture single of eth_frame_log_tb_single is

subtype mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype meta_t is std_logic_vector(PORT_COUNT+7 downto 0);
subtype psrc_t is integer range 0 to PORT_COUNT-1;

-- Clock and reset generation
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test
signal in_data      : std_logic_vector(8*INPUT_BYTES-1 downto 0) := (others => '0');
signal in_mask      : mask_t := (others => '0');
signal in_psrc      : psrc_t := 0;
signal in_meta      : switch_meta_t := SWITCH_META_NULL;
signal in_nlast     : integer range 0 to INPUT_BYTES := 0;
signal in_result    : frm_result_t := FRM_RESULT_NULL;
signal in_write     : std_logic := '0';
signal ovr_strobe   : std_logic := '0';
signal out_data     : log_meta_t;
signal out_mask     : mask_t;
signal out_psrc     : psrc_t;
signal out_strobe   : std_logic;

-- Reference stream
signal fifo_data    : log_meta_v := (others => '0');
signal fifo_meta    : meta_t := (others => '0');
signal fifo_mask    : mask_t := (others => '0');
signal fifo_psrc    : psrc_t := 0;
signal fifo_write   : std_logic := '0';
signal raw_data     : log_meta_v;
signal raw_meta     : meta_t;
signal ref_data     : log_meta_t;
signal ref_mask     : mask_t;
signal ref_psrc     : psrc_t;
signal ref_valid    : std_logic;

-- High-level test control.
signal test_rate    : real := 0.0;

begin

-- Clock and reset generation
clk100  <= not clk100 after 5 ns;
reset_p <= '0' after 1 us;

-- Generate the input and reference streams.
p_input : process(clk100)
    variable tmp_data   : log_meta_t := LOG_META_NULL;
    variable tmp_mask   : mask_t := (others => '0');
    variable tmp_psrc   : psrc_t := 0;
    variable bidx, blen : natural := 0;
    variable btmp       : byte_t := (others => '0');
begin
    if rising_edge(clk100) then
        -- Default values, may override later.
        in_write    <= '0';
        fifo_write  <= '0';

        -- If requested, assert overflow one cycle after EOF.
        ovr_strobe <= in_write and bool2bit(in_nlast > 0 and tmp_data.reason = DROP_OVERFLOW);

        -- Generate input data for the unit under test...
        if (reset_p = '0' and rand_float < test_rate) then
            -- Start of new packet?
            if (bidx >= blen) then
                -- Randomize packet parameters.
                tmp_data.dst_mac    := rand_vec(MAC_ADDR_WIDTH);
                tmp_data.src_mac    := rand_vec(MAC_ADDR_WIDTH);
                tmp_data.etype      := rand_vec(MAC_TYPE_WIDTH);
                tmp_data.vtag       := rand_vec(VLAN_HDR_WIDTH);
                tmp_data.reason     := "000000" & rand_vec(2);
                tmp_mask            := rand_vec(PORT_COUNT);
                tmp_psrc            := rand_int(PORT_COUNT);
                bidx                := 0;
                blen                := 14 + rand_int(64);
                -- Load packet descriptor into the FIFO?
                fifo_data       <= log_m2v(tmp_data);
                fifo_meta       <= i2s(tmp_psrc, 8) & tmp_mask;
                if FILTER_MODE then
                    fifo_write <= bool2bit(tmp_data.reason /= REASON_KEEP);
                else
                    fifo_write <= '1';
                end if;
                -- Fixed packet metadata.
                in_mask         <= tmp_mask;
                in_psrc         <= tmp_psrc;
                in_meta.vtag    <= tmp_data.vtag;
            end if;
            -- End-of-frame for the input stream?
            if (bidx + INPUT_BYTES < blen) then
                -- Keep emitting data until EOF.
                in_nlast    <= 0;
                in_result   <= FRM_RESULT_NULL;
            elsif (tmp_data.reason = REASON_KEEP
                or tmp_data.reason = DROP_OVERFLOW) then
                -- Ostensibly valid, may drop later using "ovr_strobe".
                in_nlast    <= blen - bidx;
                in_result   <= frm_result_ok;
            else
                -- Specify a reason why this packet is invalid.
                in_nlast    <= blen - bidx;
                in_result   <= frm_result_error(tmp_data.reason);
            end if;
            -- Generate Ethernet frame headers for the unit under test.
            for b in INPUT_BYTES-1 downto 0 loop
                if (bidx < 6) then
                    btmp := strm_byte_value(bidx,    tmp_data.dst_mac);
                elsif (bidx < 12) then
                    btmp := strm_byte_value(bidx-6,  tmp_data.src_mac);
                elsif (bidx < 14) then
                    btmp := strm_byte_value(bidx-12, tmp_data.etype);
                else
                    btmp := rand_vec(8);
                end if;
                in_data(8*b+7 downto 8*b) <= btmp;
                in_write <= '1';
                bidx := bidx + 1;
            end loop;
        end if;
    end if;
end process;

-- FIFO for reference data.
ref_data <= log_v2m(raw_data);
ref_mask <= raw_meta(PORT_COUNT-1 downto 0);
ref_psrc <= u2i(raw_meta(PORT_COUNT+7 downto PORT_COUNT));

u_ref : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => LOG_META_WIDTH,
    META_WIDTH  => 8 + PORT_COUNT)
    port map(
    in_data     => fifo_data,
    in_meta     => fifo_meta,
    in_write    => fifo_write,
    out_data    => raw_data,
    out_meta    => raw_meta,
    out_valid   => ref_valid,
    out_read    => out_strobe,
    clk         => clk100,
    reset_p     => reset_p);

-- Unit under test
uut : entity work.eth_frame_log
    generic map(
    INPUT_BYTES => INPUT_BYTES,
    FILTER_MODE => FILTER_MODE,
    OUT_BUFFER  => OUT_BUFFER,
    PORT_COUNT  => PORT_COUNT)
    port map(
    in_data     => in_data,
    in_dmask    => in_mask,
    in_psrc     => in_psrc,
    in_meta     => in_meta,
    in_nlast    => in_nlast,
    in_result   => in_result,
    in_write    => in_write,
    ovr_strobe  => ovr_strobe,
    out_data    => out_data,
    out_dmask   => out_mask,
    out_psrc    => out_psrc,
    out_strobe  => out_strobe,
    clk         => clk100,
    reset_p     => reset_p);

-- Check outputs against reference.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (ref_valid = '0') then
            assert (out_strobe = '0') report "Unexpected output." severity error;
        elsif (out_strobe = '1') then
            assert (out_data = ref_data) report "DATA mismatch" severity error;
            assert (out_mask = ref_mask) report "MASK mismatch" severity error;
            assert (out_psrc = ref_psrc) report "PSRC mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_ctrl : process
begin
    wait until (reset_p = '0');
    test_rate <= 0.1 + rand_float(0.9);
    wait for 50 us;
end process;

end single;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity eth_frame_log_tb is
    -- Testbench has no top-level I/O.
end eth_frame_log_tb;

architecture tb of eth_frame_log_tb is

begin

uut1 : entity work.eth_frame_log_tb_single
    generic map(
    INPUT_BYTES => 1,
    FILTER_MODE => false,
    OUT_BUFFER  => false,
    PORT_COUNT  => 3);
uut2 : entity work.eth_frame_log_tb_single
    generic map(
    INPUT_BYTES => 2,
    FILTER_MODE => false,
    OUT_BUFFER  => true,
    PORT_COUNT  => 4);
uut3 : entity work.eth_frame_log_tb_single
    generic map(
    INPUT_BYTES => 3,
    FILTER_MODE => true,
    OUT_BUFFER  => false,
    PORT_COUNT  => 3);
uut4 : entity work.eth_frame_log_tb_single
    generic map(
    INPUT_BYTES => 4,
    FILTER_MODE => true,
    OUT_BUFFER  => true,
    PORT_COUNT  => 4);

p_done : process
begin
    wait for 999 us;
    report "All tests completed!";
    wait;
end process;

end tb;
