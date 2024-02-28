--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet 8b/10b decoder
--
-- This block implements an 8b/10b decoder that is compatible with Ethernet
-- Physical Coding Sublayer (IEEE 802.3 Section 3.36). This includes:
--   * Token boundary alignment (by detecting the K28.5 "comma" token)
--   * Receiving configuration metadata (the C1 and C2 ordered sets)
--   * Frame decapsulation (by detecting start and end tokens)
--
-- For simplicity, most other tokens and metadata are ignored.
--
-- Input is an unaligned data stream, 10 bits per clock with a clock-enable
-- strobe and bit "a" in the MSB.  Output is the recovered byte stream, with
-- write/final strobes and bit "H" in the MSB.  The output is intended for
-- direct connection to the eth_preamble_rx block.
--
-- For a high-level overview of the 8b/10b code:
--   https://en.wikipedia.org/wiki/8b/10b_encoding
-- The full 802.3 standard can be downloaded here:
--   http://standards.ieee.org/getieee802/802.3.html
--   https://ieeexplore.ieee.org/xpl/mostRecentIssue.jsp?punumber=7428774
--
-- Error reporting can be operated in strict mode, in which every decode
-- error fires the error strobe; or in filtered mode, in which the error
-- strobe is reserved for loss-of-lock or repeated decode errors.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity eth_dec8b10b is
    generic (
    IN_RATE_HZ  : natural := 0;         -- Baud rate in Hz (for timestamps)
    ERR_STRICT  : boolean := false);    -- Report every decode error
    port (
    -- Input stream
    io_clk      : in  std_logic;        -- Data clock
    in_lock     : in  std_logic;        -- Clock detect OK
    in_cken     : in  std_logic;        -- Clock-enable
    in_data     : in  std_logic_vector(9 downto 0);
    in_tsof     : in  tstamp_t := (others => '0');

    -- Output stream (to eth_preamble_rx)
    out_lock    : out std_logic;        -- Token align OK
    out_cken    : out std_logic;        -- Clock-enable
    out_dv      : out std_logic;        -- Data valid
    out_err     : out std_logic;        -- Error flag
    out_data    : out std_logic_vector(7 downto 0);
    out_tsof    : out tstamp_t;

    -- Link configuration state machine.
    cfg_rcvd    : out std_logic;
    cfg_word    : out std_logic_vector(15 downto 0));
end eth_dec8b10b;

architecture rtl of eth_dec8b10b is

-- Token alignment
signal align_sreg_d : std_logic_vector(18 downto 0) := (others => '0');
signal align_sreg_q : std_logic_vector(8 downto 0) := (others => '0');
signal align_data   : std_logic_vector(9 downto 0) := (others => '0');
signal align_tsof   : tstamp_t := (others => '0');
signal align_cken   : std_logic := '0';
signal align_error  : std_logic := '0';
signal align_lock   : std_logic := '0';
signal align_bit    : integer range 0 to 9 := 0;

-- Multi-part lookup table.
signal align_6b     : std_logic_vector(5 downto 0) := (others => '0');
signal align_4b     : std_logic_vector(3 downto 0) := (others => '0');
signal lookup_cken  : std_logic := '0';
signal lookup_ctrl  : std_logic := '0';
signal lookup_tsof  : tstamp_t := (others => '0');
signal lookup_5b    : std_logic_vector(4 downto 0) := (others => '0');
signal lookup_3b    : std_logic_vector(2 downto 0) := (others => '0');
signal lookup_err   : std_logic := '0';
signal lookup_sof   : std_logic := '0';

-- Error reporting
signal err_strobe   : std_logic := '0';

-- Packet encapsulation and configuration metadata.
signal pkt_active   : std_logic := '0';
signal pkt_tsof     : tstamp_t := (others => '0');
signal cfg_rcvd_i   : std_logic := '0';
signal cfg_word_i   : std_logic_vector(15 downto 0) := (others => '0');

-- For debugging, apply KEEP constraint to certain signals.
attribute KEEP : string;
attribute KEEP of align_data, align_cken, align_lock : signal is "true";

begin

-- Token alignment.
align_sreg_d <= align_sreg_q & in_data; -- MSB first

p_align : process(io_clk)
    -- Note: Increasing time-to-lock can result in autonegotiation failure of
    --       some MAC-to-PHY SGMII links.  Selected threshold is compatible
    --       with all tested PHYs but still tolerates transient glitches.
    constant WINDOW_THRESH  : positive := 31;   -- Minimum matches to lock
    constant WINDOW_PENALTY : positive := 2;    -- Weight for misaligned commas
    constant SLIP_DELAY     : tstamp_t := get_tstamp_incr(IN_RATE_HZ);
    variable comma_temp     : std_logic_vector(6 downto 0) := (others => '0');
    variable comma_detect   : std_logic_vector(9 downto 0) := (others => '0');
    variable comma_error    : std_logic_vector(9 downto 0) := (others => '0');
    variable align_count    : integer range 0 to WINDOW_THRESH := 0;
    variable align_incr     : tstamp_t := (others => '0');
begin
    if rising_edge(io_clk) then
        -- Update shift register and drive output (MSB-first)
        if (in_cken = '1') then
            align_sreg_q <= align_sreg_d(8 downto 0);
            align_data   <= align_sreg_d(align_bit+9 downto align_bit);
            align_tsof   <= in_tsof + align_incr;
        end if;
        align_cken <= in_cken;

        -- Update alignment-check state machine.
        align_error <= '0';
        if (in_lock = '0') then
            -- Reset due to upstream errors or major downstream errors.
            align_error <= align_lock;
            align_lock  <= '0';
            align_bit   <= 0;
            align_count := 0;
            align_incr  := (others => '0');
        elsif (or_reduce(comma_error) = '1') then
            -- Misaligned comma, unlock if score reaches zero.
            if (align_count > WINDOW_PENALTY) then
                -- Decrement score but stay locked.
                align_count := align_count - WINDOW_PENALTY;
            else
                -- Unlock, then move to next phase hypothesis.
                -- (Error strobe if we were already locked.)
                align_error <= align_lock;
                align_lock  <= '0';
                align_count := 0;
                if (align_bit = 9) then
                    align_bit   <= 0;
                    align_incr  := (others => '0');
                else
                    align_bit   <= align_bit + 1;
                    align_incr  := align_incr + SLIP_DELAY;
                end if;
            end if;
        elsif (or_reduce(comma_detect) = '1') then
            -- Lock on N consecutive aligned commas.
            if (align_count < WINDOW_THRESH) then
                align_count := align_count + 1;
            else
                align_lock  <= '1';
            end if;
        end if;

        -- Check if any input alignment contains the special "comma"
        -- sequence as defined in Sections 36.2.4.8 and 36.2.4.9.
        for n in comma_detect'range loop
            comma_temp := align_sreg_d(n+9 downto n+3); -- abcdeif
            if (comma_temp = "0011111" or comma_temp = "1100000") then
                comma_detect(n) := in_cken and bool2bit(align_bit = n);
                comma_error(n)  := in_cken and bool2bit(align_bit /= n);
            else
                comma_detect(n) := '0';
                comma_error(n)  := '0';
            end if;
        end loop;
    end if;
end process;

-- Generate the "abcdei" and "fghj" words for the lookup table.
-- (Note transmission order is actually "abcdeifghj", NOT alphabetical.)
align_6b <= align_data(9 downto 4);
align_4b <= align_data(3 downto 0);

-- Symbol decoder using two-part lookup table.
p_decode : process(io_clk)
begin
    if rising_edge(io_clk) then
        -- Simple delay for clock-enable signal.
        lookup_cken <= align_cken;
        lookup_tsof <= align_tsof;

        -- Explicit detection for all twelve control codes.
        if (align_6b = "001111" or align_6b = "110000"                  -- K28.x
            or align_data = "1110101000" or align_data = "0001010111"   -- K23.7
            or align_data = "1101101000" or align_data = "0010010111"   -- K27.7
            or align_data = "1011101000" or align_data = "0100010111"   -- K29.7
            or align_data = "0111101000" or align_data = "1000010111")  -- K30.7
        then
            lookup_ctrl <= '1';
        else
            lookup_ctrl <= '0';
        end if;

        -- First lookup table segment (abcdei --> EDCBA)
        lookup_err <= '0';  -- Set default
        case align_6b is
        when "100111" => lookup_5b <= "00000";
        when "011000" => lookup_5b <= "00000";
        when "011101" => lookup_5b <= "00001";
        when "100010" => lookup_5b <= "00001";
        when "101101" => lookup_5b <= "00010";
        when "010010" => lookup_5b <= "00010";
        when "110001" => lookup_5b <= "00011";
        when "110101" => lookup_5b <= "00100";
        when "001010" => lookup_5b <= "00100";
        when "101001" => lookup_5b <= "00101";
        when "011001" => lookup_5b <= "00110";
        when "111000" => lookup_5b <= "00111";
        when "000111" => lookup_5b <= "00111";
        when "111001" => lookup_5b <= "01000";
        when "000110" => lookup_5b <= "01000";
        when "100101" => lookup_5b <= "01001";
        when "010101" => lookup_5b <= "01010";
        when "110100" => lookup_5b <= "01011";
        when "001101" => lookup_5b <= "01100";
        when "101100" => lookup_5b <= "01101";
        when "011100" => lookup_5b <= "01110";
        when "010111" => lookup_5b <= "01111";
        when "101000" => lookup_5b <= "01111";
        when "011011" => lookup_5b <= "10000";
        when "100100" => lookup_5b <= "10000";
        when "100011" => lookup_5b <= "10001";
        when "010011" => lookup_5b <= "10010";
        when "110010" => lookup_5b <= "10011";
        when "001011" => lookup_5b <= "10100";
        when "101010" => lookup_5b <= "10101";
        when "011010" => lookup_5b <= "10110";
        when "111010" => lookup_5b <= "10111";
        when "000101" => lookup_5b <= "10111";
        when "110011" => lookup_5b <= "11000";
        when "001100" => lookup_5b <= "11000";
        when "100110" => lookup_5b <= "11001";
        when "010110" => lookup_5b <= "11010";
        when "110110" => lookup_5b <= "11011";
        when "001001" => lookup_5b <= "11011";
        when "001111" => lookup_5b <= "11100";
        when "110000" => lookup_5b <= "11100";
        when "001110" => lookup_5b <= "11100";
        when "101110" => lookup_5b <= "11101";
        when "010001" => lookup_5b <= "11101";
        when "011110" => lookup_5b <= "11110";
        when "100001" => lookup_5b <= "11110";
        when "101011" => lookup_5b <= "11111";
        when "010100" => lookup_5b <= "11111";
        when others   => lookup_5b <= "11111";
            lookup_err <= align_lock and align_cken;
        end case;

        -- Second lookup table segment (fghj --> HGF)
        -- Note: Special cases for inverted control symbols.
        if (align_data = "1100000110") then     -- K.28.1+
            lookup_3b <= "001";
        elsif (align_data = "1100001010") then  -- K.28.2+
            lookup_3b <= "010";
        elsif (align_data = "1100000101") then  -- K.28.5+
            lookup_3b <= "101";
        elsif (align_data = "1100001001") then  -- K.28.6+
            lookup_3b <= "110";
        else
            case align_4b is                    -- All other cases
            when "1011" => lookup_3b <= "000";
            when "0100" => lookup_3b <= "000";
            when "1001" => lookup_3b <= "001";
            when "0101" => lookup_3b <= "010";
            when "1100" => lookup_3b <= "011";
            when "0011" => lookup_3b <= "011";
            when "1101" => lookup_3b <= "100";
            when "0010" => lookup_3b <= "100";
            when "1010" => lookup_3b <= "101";
            when "0110" => lookup_3b <= "110";
            when "1110" => lookup_3b <= "111";
            when "0001" => lookup_3b <= "111";
            when "0111" => lookup_3b <= "111";
            when "1000" => lookup_3b <= "111";
            when others => lookup_3b <= "111";
                lookup_err <= align_lock and align_cken;
            end case;
        end if;
    end if;
end process;

-- Detect start-of-frame token.
lookup_sof <= lookup_ctrl and bool2bit(lookup_3b = "111" and lookup_5b = "11011");

-- Packet encapsulation and configuration metadata.
p_meta : process(io_clk)
    variable cfg_sof : std_logic := '0';
    variable cfg_tok : std_logic := '0';
    variable cfg_ctr : integer range 0 to 2 := 0;
begin
    if rising_edge(io_clk) then
        -- Detect packet start/end/error tokens.
        if (align_lock = '0') then
            -- No upstream lock, clear flag.
            pkt_active  <= '0';
            pkt_tsof    <= (others => '0');
        elsif (lookup_cken = '1' and lookup_ctrl = '1') then
            -- Start of packet = K.27.7 (See Table 36-3).  Treat any
            -- other control token (end, error, etc.) as end of frame.
            pkt_active  <= lookup_sof;      -- Start of frame?
            pkt_tsof    <= lookup_tsof;     -- Latch timestamp
        end if;

        -- Receive link-configuration word (C1 or C2, see Table 36-3)
        if (align_lock = '0') then
            -- No upstream lock, clear configuration.
            cfg_rcvd_i  <= '0';
            cfg_word_i  <= (others => '0');
            cfg_tok     := '0';
            cfg_ctr     := 0;
        elsif (lookup_cken = '1') then
            -- Latch each received configuration byte (LSB first, see Figure 36-7a)
            if (cfg_ctr = 2) then
                cfg_word_i(7 downto 0) <= lookup_3b & lookup_5b;
            elsif (cfg_ctr = 1) then
                cfg_word_i(15 downto 8) <= lookup_3b & lookup_5b;
                cfg_rcvd_i <= '1';
            end if;

            -- After K28.5, look for D21.5 or D2.2 configuration word.
            if (cfg_tok = '1' and lookup_ctrl = '0' and lookup_5b = "10011" and lookup_3b = "101") then
                cfg_ctr := 2;   -- D21.5 = Start of C1
            elsif (cfg_tok = '1' and lookup_ctrl = '0' and lookup_5b = "00010" and lookup_3b = "010") then
                cfg_ctr := 2;   -- D2.2 = Start of C2
            elsif (cfg_ctr /= 0) then
                -- Countdown to end of the configuration "ordered set".
                cfg_ctr := cfg_ctr - 1;
            end if;

            -- K28.5 is the idle or configuration start token.
            cfg_tok := bool2bit(lookup_ctrl = '1' and lookup_5b = "11100" and lookup_3b = "101");
        end if;
    end if;
end process;

-- Error reporting for lost-lock and decode errors.
p_filter : process(io_clk)
    constant PENALTY : positive := 30;
    variable danger  : unsigned(7 downto 0) := (others => '0');
begin
    if rising_edge(io_clk) then
        -- Detect errors of various types:
        if (align_error = '1') then
            err_strobe <= '1';  -- Loss-of-lock is always reported
        elsif (ERR_STRICT and lookup_err = '1') then
            err_strobe <= '1';  -- Strict mode: Report every decode error
        elsif (danger > 200) then
            err_strobe <= '1';  -- Relaxed mode: Too many decode errors
        elsif (lookup_cken = '1') then
            err_strobe <= '0';  -- Sustain error strobe until next clock-enable.
        end if;

        -- For filtered mode, keep a running tally of the warning level:
        if (ERR_STRICT or align_lock = '0') then
            danger := (others => '0');  -- Disabled or reset
        elsif (lookup_err = '1') then
            danger := danger + PENALTY; -- Every decode error increments by N
        elsif (lookup_cken = '1' and lookup_sof = '1' and danger > 0) then
            danger := danger - 1;       -- Every good frame decrements by 1
        end if;
    end if;
end process;

-- Drive all outputs:
out_lock    <= align_lock;
out_cken    <= lookup_cken;
out_dv      <= pkt_active and not lookup_ctrl;
out_err     <= err_strobe;
out_data    <= lookup_3b & lookup_5b;
out_tsof    <= pkt_tsof;
cfg_rcvd    <= cfg_rcvd_i;
cfg_word    <= cfg_word_i;

end rtl;
