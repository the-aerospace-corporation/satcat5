--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic HDLC interfaces. See hdlc_encoder.vhd for more information.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.ddr_input;
use     work.eth_frame_common.byte_t;

entity io_hdlc_rx is
    generic(
    BUFFER_KBYTES : positive;          -- Packet FIFO size (kilobytes)
    MSB_FIRST     : boolean := false); -- false for LSb first
    port(
    -- External HDLC interface.
    hdlc_clk  : in  std_logic; -- Input clock
    hdlc_data : in  std_logic; -- Input signal

    -- Generic internal byte interface.
    rx_data   : out byte_t;
    rx_write  : out std_logic;
    rx_last   : out std_logic;

    -- Clock and reset
    refclk    : in  std_logic;  -- Reference clock
    reset_p   : in  std_logic); -- Reset / shutdown
end io_hdlc_rx;

architecture io_hdlc_rx of io_hdlc_rx is

-- Buffered inputs
signal clk0, clk1, clk2         : std_logic;
signal rxd1, rxd2               : std_logic;
signal ptr_sample1, ptr_sample2 : std_logic := '0';

-- Decoder inputs
signal in_data  : std_logic;
signal in_write : std_logic;

begin

u_buf1: ddr_input
    port map(d_pin => hdlc_clk, clk => refclk, q_re => clk1, q_fe => clk2);
u_buf2: ddr_input
    port map(d_pin => hdlc_data, clk => refclk, q_re => rxd1, q_fe => rxd2);

ptr_sample1 <= bool2bit(clk0 = '0' and clk1 = '1');
ptr_sample2 <= bool2bit(clk1 = '0' and clk2 = '1');

p_dat_sel : process(refclk)
begin
    if rising_edge(refclk) then
        -- Delayed HDLC clock
        clk0     <= clk2;
        in_write <= '1';

        if (ptr_sample1 = '1') then
            in_data  <= rxd1;
        elsif (ptr_sample2 = '1') then
            in_data  <= rxd2;
        else
            in_write <= '0';
        end if;
    end if;
end process;

decoder : entity work.hdlc_decoder
    generic map(
    BUFFER_KBYTES => BUFFER_KBYTES,
    MSB_FIRST     => MSB_FIRST)
    port map(
    in_data   => in_data,
    in_write  => in_write,
    out_data  => rx_data,
    out_write => rx_write,
    out_last  => rx_last,
    clk       => refclk,
    reset_p   => reset_p);

end io_hdlc_rx;

---------------------------------------------------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.eth_frame_common.byte_t;
use     work.eth_frame_common.HDLC_FLAG;

entity io_hdlc_tx is
    generic(
    FRAME_BYTES : natural;           -- Bytes per frame excluding flags/FCS
    MSB_FIRST   : boolean  := false; -- false for LSb first
    RATE_WIDTH  : positive := 16);   -- Width of clock divider
    port(
    -- External HDLC interface.
    hdlc_clk   : out std_logic; -- Output clock
    hdlc_data  : out std_logic; -- Output signal
    hdlc_ready : in  std_logic; -- Downstream flow control

    -- Generic internal byte interface.
    tx_data    : in  byte_t;
    tx_valid   : in  std_logic;
    tx_last    : in  std_logic;
    tx_ready   : out std_logic;

    -- Rate control (clocks per bit, from 1 to 2**RATE_WIDTH-1)
    -- LIMITATION: a rate_div of 1 will not work. No clock will be generated.
    rate_div   : in  unsigned(RATE_WIDTH-1 downto 0);

    -- Clock and reset
    refclk     : in  std_logic;  -- Reference clock
    reset_p    : in  std_logic); -- Reset / shutdown
end io_hdlc_tx;

architecture io_hdlc_tx of io_hdlc_tx is

-- Encoder output
signal enc_data  : std_logic;
signal enc_valid : std_logic;
signal enc_last  : std_logic;
signal enc_ready : std_logic := '0';

-- Transmitter state machine
signal t_clk_count : unsigned(RATE_WIDTH-1 downto 0) := (others => '0');
signal t_bit_count : integer range 0 to 7 := 0; -- Only for delimiter
signal t_sreg      : byte_t := HDLC_FLAG;       -- Only for delimiter
signal t_enable    : boolean := false; -- Only for data bits

-- Rate div right shifted by one
signal hrate_div : unsigned(RATE_WIDTH-1 downto 0);

-- Synchronous ready
signal hdlc_ready_i : std_logic;

-- Internal output signals
signal hdlc_data_i : std_logic := '0';
signal hdlc_clk_i : std_logic := '0';

begin

hrate_div <= shift_right(rate_div, 1);

-- Outputs
hdlc_data <= hdlc_data_i;
hdlc_clk  <= hdlc_clk_i;

encoder : entity work.hdlc_encoder
    generic map(
    FRAME_BYTES => FRAME_BYTES,
    MSB_FIRST   => MSB_FIRST)
    port map(
    in_data     => tx_data,
    in_valid    => tx_valid,
    in_last     => tx_last,
    in_ready    => tx_ready,
    out_data    => enc_data,
    out_valid   => enc_valid,
    out_last    => enc_last,
    out_ready   => enc_ready,
    clk         => refclk,
    reset_p     => reset_p);

-- Transmitter state machine
p_tx : process(refclk)
begin
    if rising_edge(refclk) then
        -- Sanity check on rate-divider setting.
        assert (reset_p = '1' or rate_div > 0)
            report "Invalid rate-divider setting." severity error;

        -- Upstream flow control
        enc_ready <= '0';

        -- Counter and shift-register updates
        if (reset_p = '1') then
            t_clk_count <= (others => '0');
            t_bit_count <= 0;
            t_sreg      <= HDLC_FLAG;
            hdlc_data_i <= '0';
            hdlc_clk_i  <= '0';
        elsif (t_clk_count = "0") then
            -- Clock rising edge; reset counter
            hdlc_clk_i <= '1';
            t_clk_count <= rate_div - 1;
        elsif (t_clk_count = hrate_div) then
            -- Clock falling edge; decrement counter, and emit next bit
            hdlc_clk_i  <= '0';
            t_clk_count <= t_clk_count - 1;

            -- Bit tx logic
            if (t_bit_count > 0) then
                -- Delimiter Tx in progress, emit next delimiter bit
                t_bit_count <= t_bit_count - 1;
                hdlc_data_i <= t_sreg(7);
                t_sreg      <= t_sreg(6 downto 0) & t_sreg(7);
            elsif (enc_valid = '1') and t_enable then
                -- Emit next data bit
                enc_ready <= '1';
                hdlc_data_i <= enc_data;
            else
                -- Idle (emit first delimiter bit)
                t_bit_count <= 7;
                hdlc_data_i <= t_sreg(7);
                t_sreg      <= t_sreg(6 downto 0) & t_sreg(7);
            end if;
        elsif(t_clk_count <= rate_div-1) then
            -- Normal operation; counting down to next bit
            t_clk_count <= t_clk_count - 1;
        else
            -- Case where clock_div is set <= current clk_count
            -- Avoid having to count down to new clock_div first
            t_clk_count <= rate_div - 1;
        end if;
    end if;
end process;

u_sync : sync_buffer
    port map(
    in_flag  => hdlc_ready,
    out_flag => hdlc_ready_i,
    out_clk  => refclk,
    reset_p  => reset_p);

-- Disable data bit transmission at end of frame if downstream isn't ready
p_en : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            t_enable <= false;
        elsif t_enable and (hdlc_ready_i = '0') and (enc_last = '1') then
            t_enable <= false;
        elsif hdlc_ready_i = '1' then
            t_enable <= true;
        end if;
    end if;
end process;

end io_hdlc_tx;
