--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet 8b/10b encoder
--
-- This block implements an 8b/10b encoder that is compatible with Ethernet
-- Physical Coding Sublayer (IEEE 802.3 Section 3.36). This includes:
--   * Transmission of configuration metadata (the C1 and C2 ordered sets)
--   * Transmission of idle tokens (the I1 and I2 ordered sets)
--   * Frame encapsulation (start, end, and carrier-extend tokens)
--
-- Input is the byte-at-a-time data stream, usually sourced by eth_preamble_tx.
-- There is no upstream flow control; bit "H" is the MSB.  Output is the
-- encoded stream of 10-bit code groups, with bit "a" in the MSB, suitable
-- for SGMII serialization.
--
-- The full 802.3 standard can be downloaded here:
--   http://standards.ieee.org/getieee802/802.3.html
--   https://ieeexplore.ieee.org/xpl/mostRecentIssue.jsp?punumber=7428774
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_enc8b10b_table.all;

entity eth_enc8b10b is
    port (
    -- Input stream
    in_data     : in  std_logic_vector(7 downto 0);
    in_dv       : in  std_logic;        -- GMII data-valid
    in_err      : in  std_logic;        -- GMII error strobe
    in_cken     : in  std_logic := '1'; -- Clock enable (optional)
    in_frmst    : out std_logic;        -- Ready to start new frame?

    -- Link configuration mode.
    cfg_xmit    : in  std_logic := '0'; -- Transmit config?
    cfg_word    : in  std_logic_vector(15 downto 0);

    -- Output stream
    out_data    : out std_logic_vector(9 downto 0);
    out_cken    : out std_logic;

    -- System interface
    io_clk      : in  std_logic;        -- Data clock
    reset_p     : in  std_logic);       -- Reset / shutdown
end eth_enc8b10b;

architecture rtl of eth_enc8b10b is

-- Make 8b/10b input tokens using C.x.y or K.x.y notation:
subtype byte is std_logic_vector(7 downto 0);
function make_token(x,y:integer) return byte is
    variable xy : unsigned(7 downto 0) :=
        to_unsigned(y, 3) & to_unsigned(x, 5);
begin
    return std_logic_vector(xy);
end function;

-- Byte stream modification.
type strm_state_t is (
    STATE_IDLE,     -- Idle or start of new sequence
    STATE_CONFIG,   -- Configuration sequence
    STATE_DATA,     -- Normal data + end of frame
    STATE_EXT);     -- Carrier extend
signal strm_state   : strm_state_t := STATE_IDLE;
signal strm_data    : byte := make_token(28, 5);
signal strm_ctrl    : std_logic := '1'; -- Is next output a control token?
signal strm_even    : std_logic := '0'; -- Is next output an even-numbered token?
signal strm_cfgct   : integer range 0 to 5 := 0;
signal strm_cken    : std_logic := '0'; -- Clock-enable strobe
signal strm_idle1   : std_logic := '0'; -- Use I1 for next idle sequence?

-- 8b/10b encoder.
signal rom_addr     : rom_index := 0;
signal rom_lookup   : rom_word := (others => '0');
signal enc_data     : std_logic_vector(9 downto 0) := (others => '0');
signal enc_rdp      : std_logic := '0'; -- Running disparity for this token?
signal enc_cken     : std_logic := '0';

begin

-- Ready to start a new frame?
in_frmst <= bool2bit(strm_state = STATE_IDLE) and strm_even;

-- Modify byte stream by inserting idle or config sequences.
-- See also: Table 36-3, Sections 36.2.4.10 through .17
p_mod : process(io_clk)
begin
    if rising_edge(io_clk) then
        if (reset_p = '1') then
            -- System reset / shutdown.
            strm_state  <= STATE_IDLE;
            strm_data   <= make_token(28, 5);
            strm_ctrl   <= '1'; -- K28.5
            strm_even   <= '0';
            strm_cfgct  <= 0;
        elsif (in_cken = '1') then
            case strm_state is
            when STATE_IDLE =>      -- Idle (even/odd tokens)
                if (strm_even = '0') then
                    if (strm_idle1 = '1') then
                        strm_data <= make_token(5, 6);
                        strm_ctrl <= '0';   -- D5.6 = End of Idle1
                    else
                        strm_data <= make_token(16, 2);
                        strm_ctrl <= '0';   -- D16.2 = End of Idle2
                    end if;
                elsif (in_dv = '1') then
                    -- Start of new packet (replaces a preamble token).
                    strm_data <= make_token(27, 7);
                    strm_ctrl <= '1';   -- K27.7 = Start of packet
                    strm_state <= STATE_DATA;
                elsif (cfg_xmit = '1') then
                    -- Start of configuration token.
                    strm_data <= make_token(28, 5);
                    strm_ctrl <= '1';   -- K28.5 = Start of config
                    strm_state <= STATE_CONFIG;
                else
                    -- Start of next idle token.
                    strm_data   <= make_token(28, 5);
                    strm_ctrl   <= '1'; -- K28.5 = Idle start
                end if;
            when STATE_CONFIG =>    -- Configuration sequence
                -- Generate next byte...
                if (strm_cfgct = 0) then
                    strm_data <= make_token(21, 5);
                    strm_ctrl <= '0';   -- D21.5 (Start C1)
                elsif (strm_cfgct = 3) then
                    strm_data <= make_token(2, 2);
                    strm_ctrl <= '0';   -- D2.2 (Start C2)
                elsif (strm_cfgct = 1 or strm_cfgct = 4) then
                    strm_data <= cfg_word(7 downto 0);
                    strm_ctrl <= '0';   -- Config word, LSBs first
                else
                    strm_data <= cfg_word(15 downto 8);
                    strm_ctrl <= '0';   -- Config word, MSBs second
                    strm_state <= STATE_IDLE;   -- Done with sequence
                end if;
                -- Update counter state to alternate C1/C2.
                if (strm_cfgct = 5) then
                    strm_cfgct <= 0;
                else
                    strm_cfgct <= strm_cfgct + 1;
                end if;
            when STATE_DATA =>      -- Normal data + end of frame
                if (in_err = '1') then
                    strm_data <= make_token(30, 7);
                    strm_ctrl <= '1';   -- K30.7 = Error
                elsif (in_dv = '1') then
                    strm_data <= in_data;
                    strm_ctrl <= '0';   -- Normal data
                else
                    strm_data <= make_token(29, 7);
                    strm_ctrl <= '1';   -- K29.7 = End of packet
                    strm_state <= STATE_EXT;
                end if;
            when STATE_EXT =>       -- Carrier extend (to next even boundary)
                strm_data <= make_token(23, 7);
                strm_ctrl <= '1';   -- K23.7 = Carrier extend
                if (strm_even = '0') then
                    strm_state <= STATE_IDLE;
                end if;
            end case;
            strm_even <= not strm_even;
        end if;

        -- Update the polarity flag for selecting I1 vs. I2.
        if (reset_p = '1') then
            strm_idle1 <= '0';  -- Next token = I2
        elsif (strm_cken = '1' and strm_ctrl = '1') then
            strm_idle1 <= enc_rdp;
        end if;

        -- Update the clock-enable strobe.
        strm_cken <= in_cken and not reset_p;
    end if;
end process;

-- 8b/10b encoder tables. See eth_enc8b10b_table.vhd.
rom_addr <= to_integer(unsigned(std_logic_vector'
    (strm_ctrl & enc_rdp & strm_data)));
rom_lookup <= ENC_TABLE(rom_addr);

-- Update 8b/10b encoder state.
p_enc : process(io_clk)
begin
    if rising_edge(io_clk) then
        -- Update running disparity flag.
        if (strm_cken = '1') then
            enc_rdp  <= enc_rdp xor rom_lookup(10);
        end if;
        -- Remap output bits from ROM order (abcdefghij)
        -- to IEEE 802.3 order (abcdeifghj)
        enc_data <= rom_lookup(9 downto 5) & rom_lookup(1)
                  & rom_lookup(4 downto 2) & rom_lookup(0);
        enc_cken <= strm_cken;
    end if;
end process;

-- Drive outputs.
out_data <= enc_data;
out_cken <= enc_cken;

end rtl;
