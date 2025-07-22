--------------------------------------------------------------------------
-- Copyright 2019-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Fixed-delay buffer for use with packet FIFO
--
-- This block implements a fixed-delay buffer for data and byte-count
-- fields, suitable for use at the input to the packet FIFO.  Shifting
-- the data in this fashion allows maximum utilization of the MAC-lookup
-- pipeline, while still ensuring that port-routing information is ready
-- prior to the end of the packet.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity packet_delay is
    generic (
    IO_BYTES    : positive;         -- Width of input port
    DELAY_COUNT : natural;          -- Fixed delay, in clocks
    PORT_COUNT  : positive := 1);   -- Number of ports (for psrc)
    port (
    -- Input port (no flow control).
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_mask     : in  std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
    in_meta     : in  switch_meta_t := SWITCH_META_NULL;
    in_psrc     : in  integer range 0 to PORT_COUNT-1 := 0;
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic := '0';
    in_result   : in  frm_result_t := FRM_RESULT_NULL;

    -- Output port (no flow control).
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_mask    : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_meta    : out switch_meta_t;
    out_psrc    : out integer range 0 to PORT_COUNT-1;
    out_nlast   : out integer range 0 to IO_BYTES;
    out_write   : out std_logic;
    out_result  : out frm_result_t;

    -- System clock and optional reset.
    io_clk      : in  std_logic;
    reset_p     : in  std_logic := '0');
end packet_delay;

architecture packet_delay of packet_delay is

constant ADDR_MAX : integer := int_max(0, DELAY_COUNT-2);
subtype addr_t is integer range 0 to ADDR_MAX;
subtype flag_t is std_logic_vector(FRM_RESULT_WIDTH downto 0);
subtype mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype nlast_t is integer range 0 to IO_BYTES;
subtype psrc_t is integer range 0 to PORT_COUNT-1;
subtype word_t is std_logic_vector(8*IO_BYTES-1 downto 0);
type flag_array is array(natural range <>) of flag_t;
type mask_array is array(natural range <>) of mask_t;
type meta_array is array(natural range <>) of switch_meta_t;
type nlast_array is array(natural range <>) of nlast_t;
type psrc_array is array(natural range <>) of psrc_t;
type word_array is array(natural range <>) of word_t;

signal in_flags     : flag_t;
signal rw_addr      : addr_t := 0;
signal out_en       : flag_t := (others => '0');
signal tmp_data     : word_t := (others => '0');
signal tmp_flags    : flag_t := (others => '0');
signal tmp_mask     : mask_t := (others => '0');
signal tmp_meta     : switch_meta_t := SWITCH_META_NULL;
signal tmp_nlast    : nlast_t := IO_BYTES;
signal tmp_psrc     : psrc_t := 0;

begin

-- Drive the final output signals.
out_data    <= tmp_data;
out_mask    <= tmp_mask;
out_meta    <= tmp_meta;
out_nlast   <= tmp_nlast;
out_psrc    <= tmp_psrc;
out_write   <= tmp_flags(FRM_RESULT_WIDTH);
out_result  <= frm_result_v2m(tmp_flags(FRM_RESULT_WIDTH-1 downto 0));

-- Concatenate named input strobes.
in_flags <= in_write & frm_result_m2v(in_result);

-- Special case if delay is zero:
gen_null : if (DELAY_COUNT = 0) generate
    tmp_data    <= in_data;
    tmp_flags   <= in_flags;
    tmp_mask    <= in_mask;
    tmp_meta    <= in_meta;
    tmp_nlast   <= in_nlast;
    tmp_psrc    <= in_psrc;
end generate;

-- Small delays use a shift-register interface:
gen_sreg : if (1 <= DELAY_COUNT and DELAY_COUNT < 16) generate
    -- To save resources, only the "out_flags" buffer is resettable.
    p_flags : process(io_clk)
        variable sreg : flag_array(DELAY_COUNT downto 1) := (others => (others => '0'));
    begin
        if rising_edge(io_clk) then
            if (reset_p = '1') then
                sreg := (others => (others => '0'));
            else
                sreg := sreg(DELAY_COUNT-1 downto 1) & in_flags;
            end if;
            tmp_flags <= sreg(DELAY_COUNT);
        end if;
    end process;

    p_other : process(io_clk)
        variable sreg_data  : word_array(DELAY_COUNT downto 1) := (others => (others => '0'));
        variable sreg_mask  : mask_array(DELAY_COUNT downto 1) := (others => (others => '0'));
        variable sreg_meta  : meta_array(DELAY_COUNT downto 1) := (others => SWITCH_META_NULL);
        variable sreg_nlast : nlast_array(DELAY_COUNT downto 1) := (others => IO_BYTES);
        variable sreg_psrc  : psrc_array(DELAY_COUNT downto 1) := (others => 0);
    begin
        if rising_edge(io_clk) then
            sreg_data  := sreg_data (DELAY_COUNT-1 downto 1) & in_data;
            sreg_mask  := sreg_mask (DELAY_COUNT-1 downto 1) & in_mask;
            sreg_meta  := sreg_meta (DELAY_COUNT-1 downto 1) & in_meta;
            sreg_nlast := sreg_nlast(DELAY_COUNT-1 downto 1) & in_nlast;
            sreg_psrc  := sreg_psrc (DELAY_COUNT-1 downto 1) & in_psrc;

            tmp_data   <= sreg_data (DELAY_COUNT);
            tmp_mask   <= sreg_mask (DELAY_COUNT);
            tmp_meta   <= sreg_meta (DELAY_COUNT);
            tmp_nlast  <= sreg_nlast(DELAY_COUNT);
            tmp_psrc   <= sreg_psrc (DELAY_COUNT);
        end if;
    end process;
end generate;

-- Larger delays use inferred block-RAM.
gen_bram : if (DELAY_COUNT >= 16) generate
    -- Counter state machine:
    p_addr : process(io_clk)
    begin
        if rising_edge(io_clk) then
            -- Permanently set "out_en" N cycles after reset.
            if (reset_p = '1') then
                out_en <= (others => '0');
            elsif (rw_addr = ADDR_MAX) then
                out_en <= (others => '1');
            end if;

            -- Combined read/write address increments every clock cycle.
            if (reset_p = '1' or rw_addr = ADDR_MAX) then
                rw_addr <= 0;
            else
                rw_addr <= rw_addr + 1;
            end if;
        end if;
    end process;

    -- Inferred block-RAM or distributed RAM:
    p_bram : process(io_clk)
        variable ram_data   : word_array(0 to ADDR_MAX) := (others => (others => '0'));
        variable ram_flags  : flag_array(0 to ADDR_MAX) := (others => (others => '0'));
        variable ram_mask   : mask_array(0 to ADDR_MAX) := (others => (others => '0'));
        variable ram_meta   : meta_array(0 to ADDR_MAX) := (others => SWITCH_META_NULL);
        variable ram_nlast  : nlast_array(0 to ADDR_MAX) := (others => IO_BYTES);
        variable ram_psrc   : psrc_array(0 to ADDR_MAX) := (others => 0);
    begin
        if rising_edge(io_clk) then
            -- Read before write.
            tmp_data    <= ram_data (rw_addr);
            tmp_flags   <= ram_flags(rw_addr) and out_en;
            tmp_mask    <= ram_mask (rw_addr);
            tmp_meta    <= ram_meta (rw_addr);
            tmp_psrc    <= ram_psrc (rw_addr);
            tmp_nlast   <= ram_nlast(rw_addr);

            ram_data (rw_addr)  := in_data;
            ram_flags(rw_addr)  := in_flags;
            ram_mask (rw_addr)  := in_mask;
            ram_meta (rw_addr)  := in_meta;
            ram_psrc (rw_addr)  := in_psrc;
            ram_nlast(rw_addr)  := in_nlast;
        end if;
    end process;
end generate;

end packet_delay;
