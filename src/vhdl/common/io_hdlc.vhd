--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic HDLC interfaces
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.ddr_input;
use     work.eth_frame_common.byte_t;

entity io_hdlc_rx is
    generic(
    USE_ADDRESS : boolean); -- Expect address field in data?
    port(
    -- External HDLC interface.
    hdlc_rxd    : in  std_logic; -- Input signal
    hdlc_clk    : in  std_logic; -- Input clock

    -- Generic internal byte interface.
    rx_data     : out byte_t;
    rx_write    : out std_logic;
    rx_last     : out std_logic;
    rx_error    : out std_logic;
    rx_addr     : out byte_t;

    -- Clock and reset
    refclk      : in  std_logic;  -- Reference clock
    reset_p     : in  std_logic); -- Reset / shutdown
end io_hdlc_rx;

architecture io_hdlc_rx of io_hdlc_rx is

-- Buffered inputs
signal clk0, clk1, clk2         : std_logic;
signal rxd1, rxd2               : std_logic;
signal ptr_sample1, ptr_sample2 : std_logic := '0';

-- Decoder inputs
signal in_data  : std_logic;
signal in_write : std_logic;

-- Optional address
signal s_rx_addr : byte_t := (others => '0');

begin

u_buf1: ddr_input
    port map(d_pin => hdlc_clk, clk => refclk, q_re => clk1, q_fe => clk2);
u_buf2: ddr_input
    port map(d_pin => hdlc_rxd, clk => refclk, q_re => rxd1, q_fe => rxd2);

ptr_sample1 <= bool2bit(clk0 = '0' and clk1 = '1');
ptr_sample2 <= bool2bit(clk1 = '0' and clk2 = '1');

p_dat_sel : process(refclk)
begin
    if rising_edge(refclk) then
        -- Delayed HDLC clock
        clk0 <= clk2;
        in_write  <= '1';

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
    USE_ADDRESS => USE_ADDRESS)
    port map(
    in_data     => in_data,
    in_write    => in_write,
    out_data    => rx_data,
    out_write   => rx_write,
    out_last    => rx_last,
    out_error   => rx_error,
    out_addr    => s_rx_addr,
    clk         => refclk,
    reset_p     => reset_p);

gen_addr : if USE_ADDRESS generate
    rx_addr <= s_rx_addr;
end generate;

no_gen_addr : if not USE_ADDRESS generate
    rx_addr <= (others => '0');
end generate;

end io_hdlc_rx;

---------------------------------------------------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;
use     work.eth_frame_common.HDLC_DELIM;

entity io_hdlc_tx is
    generic(
    USE_ADDRESS : boolean;         -- Use address field?
    BLOCK_BYTES : integer;         -- Frame size (< 0 for variable)
    RATE_WIDTH  : positive := 16); -- Width of clock divider
    port(
    -- External HDLC interface.
    hdlc_txd    : out  std_logic; -- Output signal
    hdlc_clk    : out  std_logic; -- Output clock

    -- Generic internal byte interface.
    tx_data     : in byte_t;
    tx_last     : in std_logic;
    tx_valid    : in std_logic;
    tx_addr     : in byte_t := x"03"; -- Optional address
    tx_ready    : out std_logic;

    -- Rate control (clocks per bit, from 1 to 2**RATE_WIDTH-1)
    rate_div    : in  unsigned(RATE_WIDTH-1 downto 0);

    -- Clock and reset
    refclk      : in  std_logic;  -- Reference clock
    reset_p     : in  std_logic); -- Reset / shutdown
end io_hdlc_tx;

architecture io_hdlc_tx of io_hdlc_tx is

-- Encoder output
signal enc_data  : std_logic := '0';
signal enc_valid : std_logic := '0';
signal enc_ready : std_logic := '0';

-- Transmitter state machine
signal t_clk_count : unsigned(RATE_WIDTH-1 downto 0) := (others => '0');
signal t_bit_count : integer range 0 to 7 := 0; -- Only for delimiter
signal t_sreg      : byte_t := HDLC_DELIM;      -- Only for delimiter

-- Internal output signals
signal hdlc_txd_i : std_logic := '0';
signal hdlc_clk_i : std_logic := '0';

begin

-- Outputs
hdlc_txd <= hdlc_txd_i;
hdlc_clk <= hdlc_clk_i;

encoder : entity work.hdlc_encoder
    generic map(
    USE_ADDRESS => USE_ADDRESS,
    BLOCK_BYTES => BLOCK_BYTES)
    port map(
    in_data     => tx_data,
    in_last     => tx_last,
    in_valid    => tx_valid,
    in_addr     => tx_addr,
    in_ready    => tx_ready,
    out_data    => enc_data,
    out_valid   => enc_valid,
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

        -- Reset output clock
        hdlc_clk_i <= '1';

        -- Upstream flow control
        enc_ready <= bool2bit(t_bit_count = 0) and bool2bit(t_clk_count = 1);

        -- Counter and shift-register updates
        if (reset_p = '1') then
            t_clk_count <= (others => '0');
            t_bit_count <= 0;
            hdlc_txd_i  <= '0';
            hdlc_clk_i  <= '1';
        elsif (t_clk_count > 0) then
            -- Countdown to next bit
            t_clk_count <= t_clk_count - 1;
        elsif (t_bit_count > 0) then
            -- Delimiter Tx in progress, emit next delimiter bit
            t_clk_count <= rate_div - 1;
            t_bit_count <= t_bit_count - 1;
            hdlc_txd_i  <= t_sreg(7);
            hdlc_clk_i  <= '0';
            t_sreg       <= t_sreg(6 downto 0) & t_sreg(7);
        elsif (enc_valid = '1') then
            -- Emit next data bit
            t_clk_count <= rate_div - 1;
            hdlc_txd_i  <= enc_data;
            hdlc_clk_i  <= '0';
        else
            -- Idle (emit delimiter bit)
            t_clk_count <= rate_div - 1;
            t_bit_count <= 7;
            hdlc_txd_i  <= t_sreg(7);
            hdlc_clk_i  <= '0';
            t_sreg      <= t_sreg(6 downto 0) & t_sreg(7);
        end if;
    end if;
end process;

end io_hdlc_tx;
