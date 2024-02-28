--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet frame verification
--
-- Given an Ethernet byte stream, detect frame boundaries and test
-- whether each packet is valid:
--  * Matching frame check sequence (CRC32)
--  * Maximum frame length is 1522 bytes (normal) or 9022 bytes (jumbo).
--  * Minimum frame length is either 64 bytes (normal mode) or 18 bytes
--    (if runt frames are allowed on this interface).
--  * Frame length at least 64 bytes (unless runt frames are allowed).
--  * If length is specified (EtherType <= 1530), verify exact match.
--
-- This block may additionally block frames that have an invalid source
-- address (e.g., 00-00-00-00-00-00) or a reserved destination address
-- (e.g., 01-80-C2-00-00-01).  Such frames assert the "revert" strobe
-- but not the "error" strobe.  See also: 802.3 Annex 31D.
--
-- This block optionally strips the frame-check sequence from the end of
-- each output frame; in this case it must be replaced before transmission.
--
-- For more information, refer to:
-- https://en.wikipedia.org/wiki/Ethernet_frame
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_check is
    generic (
    ALLOW_JUMBO : boolean := false;     -- Allow frames longer than 1522 bytes?
    ALLOW_MCTRL : boolean := false;     -- Allow frames to MAC-control address?
    ALLOW_RUNT  : boolean := false;     -- Allow frames below standard length?
    STRIP_FCS   : boolean := false;     -- Remove FCS from output?
    IO_BYTES    : positive := 1);       -- Width of input/output datapath?
    port (
    -- Input data stream (with strobe or NLAST for final byte)
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES := 0;
    in_last     : in  std_logic := '0'; -- Ignored if IO_BYTES > 1
    in_write    : in  std_logic;

    -- Output data stream (with pass/fail on last byte)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES := 0;
    out_write   : out std_logic;
    out_commit  : out std_logic;
    out_revert  : out std_logic;
    out_error   : out std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_check;

architecture eth_frame_check of eth_frame_check is

-- Minimum frame size depends on ALLOW_RUNT parameter.
-- (Returned size includes header, user data, and CRC.)
function MIN_USER_BYTES_LOCAL return integer is
begin
    if (ALLOW_RUNT) then
        return 0;
    else
        return MIN_FRAME_BYTES - HEADER_CRC_BYTES;
    end if;
end function;

-- Maximum frame size depends on the ALLOW_JUMBO parameter.
-- (Returned size includes header, user data, and CRC.)
function MAX_USER_BYTES_LOCAL return integer is
begin
    if (ALLOW_JUMBO) then
        return MAX_JUMBO_BYTES - HEADER_CRC_BYTES;
    else
        return MAX_FRAME_BYTES - HEADER_CRC_BYTES;
    end if;
end function;

-- Maximum "length" field is always 1530, even if jumbo frames are allowed.
constant MAX_USERLEN_BYTES : integer := 1530;

-- Local type definitions:
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

type result_t is record
    commit  : std_logic;
    revert  : std_logic;
    error   : std_logic;
end record;

-- Counter initializes to a negative number, so that the total
-- represents only the user data (i.e., no header/footer).
constant COUNT_INIT : signed(15 downto 0) := to_signed(-HEADER_CRC_BYTES, 16);

-- Format conversion for input.
signal in_nlast_mod : last_t;

-- Data stream aligned one cycle before "reg_data".
signal dly_data     : data_t;
signal dly_nlast    : last_t;
signal dly_write    : std_logic;

-- CRC calculation and matched-delay data.
signal crc_result   : crc_word_t := CRC_INIT;
signal crc_data     : data_t := (others => '0');
signal crc_nlast    : last_t := 0;
signal crc_write    : std_logic := '0';

-- All other frame-checking logic (sync'd to crc_*).
signal chk_mctrl    : std_logic_vector(5 downto 0) := (others => '0');
signal chk_badsrc   : std_logic_vector(5 downto 0) := (others => '0');
signal chk_etype    : unsigned(15 downto 0) := (others => '0');
signal chk_count    : signed(15 downto 0) := COUNT_INIT;
signal frm_ok       : std_logic := '0';
signal frm_keep     : std_logic := '0';
signal frm_result   : result_t;

-- Buffered output signals
signal buf_data     : data_t := (others => '0');
signal buf_nlast    : last_t := 0;
signal buf_write    : std_logic := '0';
signal buf_result   : result_t := (others => '0');

-- Modified output signals with no FCS (optional)
signal trim_data    : data_t := (others => '0');
signal trim_nlast   : last_t := 0;
signal trim_write   : std_logic := '0';
signal trim_result  : result_t := (others => '0');

begin

-- Legacy compatibility for combining "in_last" and "in_nlast":
-- (i.e., Overrides "in_nlast" only if IO_BYTES = 1.)
in_nlast_mod <= 0 when (in_write = '0')
           else 1 when (IO_BYTES = 1 and in_last = '1')
           else in_nlast;

-- Select CRC calculation using simple or parallel algorithm.
u_crc : entity work.eth_frame_parcrc2
    generic map(IO_BYTES => IO_BYTES)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast_mod,
    in_write    => in_write,
    dly_data    => dly_data,
    dly_nlast   => dly_nlast,
    dly_write   => dly_write,
    out_data    => crc_data,
    out_res     => crc_result,
    out_nlast   => crc_nlast,
    out_write   => crc_write,
    clk         => clk,
    reset_p     => reset_p);

-- Other frame-checking parameters:
p_frame : process(clk)
    -- Define special-case MAC addresses:
    constant MAC_MCTRL : mac_addr_t := x"0180C2000001";
    -- Count words for frame parsing using strm_byte_xx functions.
    constant WCOUNT_MAX : integer := 1 + div_floor(ETH_HDR_DATA, IO_BYTES);
    variable wcount : integer range 0 to WCOUNT_MAX := 0;
    -- Temporary variables (combinational logic only)
    variable incr   : integer range 1 to IO_BYTES;
    variable btmp, bref : byte_t;
begin
    if rising_edge(clk) then
        if (dly_write = '1') then
            -- Is the destination-MAC the control address? (Bytes 0-5)
            for n in 0 to 5 loop
                if (strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+n, wcount)) then
                    bref := strm_byte_value(n, MAC_MCTRL);
                    btmp := strm_byte_value(ETH_HDR_SRCMAC+n, dly_data);
                    chk_mctrl(n) <= bool2bit(bref = btmp);
                end if;
            end loop;

            -- Is the source-MAC the broadcast address? (Bytes 6-11 = 0xFF)
            for n in 0 to 5 loop
                if (strm_byte_present(IO_BYTES, ETH_HDR_SRCMAC+n, wcount)) then
                    btmp := strm_byte_value(ETH_HDR_SRCMAC+n, dly_data);
                    chk_badsrc(n) <= bool2bit(btmp = x"FF");
                end if;
            end loop;

            -- Store the Ethertype / Length field (12th + 13th bytes).
            if (strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+0, wcount)) then
                btmp := strm_byte_value(ETH_HDR_ETYPE+0, dly_data);
                chk_etype(15 downto 8) <= unsigned(btmp);
            end if;
            if (strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+1, wcount)) then
                btmp := strm_byte_value(ETH_HDR_ETYPE+1, dly_data);
                chk_etype(7 downto 0) <= unsigned(btmp);
            end if;

            -- How many new bytes in this word?
            if (dly_nlast = 0) then
                incr := IO_BYTES;
            else
                incr := dly_nlast;
            end if;

            -- Count user bytes in each frame, with overflow check.
            -- (Upper bound is a nice power of two, well above jumbo
            --  frame limit but trivial to check with bitwise logic.)
            if (wcount = 0) then
                chk_count <= COUNT_INIT + incr; -- First word in frame
            elsif (chk_count < 16384) then
                chk_count <= chk_count + incr;  -- All subsequent words
            end if;
        end if;

        -- Count words for frame parsing.
        if (reset_p = '1') then
            wcount := 0;
        elsif (dly_write = '1' and dly_nlast > 0) then
            wcount := 0;
        elsif (dly_write = '1' and wcount < WCOUNT_MAX) then
            wcount := wcount + 1;
        end if;
    end if;
end process;

-- Check all frame validity requirements.
frm_ok <= bool2bit(
    (crc_result = CRC_RESIDUE) and
    (and_reduce(chk_badsrc) = '0') and
    (chk_count >= MIN_USER_BYTES_LOCAL) and
    (chk_count <= MAX_USER_BYTES_LOCAL) and
    (chk_etype > MAX_USERLEN_BYTES or chk_etype = unsigned(chk_count)));

-- Ignore frames to the special control address?
frm_keep <= frm_ok and bool2bit(ALLOW_MCTRL or and_reduce(chk_mctrl) = '0');

-- Fire the commit/revert/error strobes at end of frame.
frm_result.commit <= bool2bit(crc_nlast > 0) and frm_keep;
frm_result.revert <= bool2bit(crc_nlast > 0) and not frm_keep;
frm_result.error  <= bool2bit(crc_nlast > 0) and not frm_ok;

-- Simple buffered output.
p_out_reg : process(clk)
begin
    if rising_edge(clk) then
        buf_data    <= crc_data;
        buf_nlast   <= crc_nlast;
        buf_write   <= crc_write;
        buf_result  <= frm_result;
    end if;
end process;

-- Instantiate state machine to remove FCS from the end of each packet?
gen_strip : if STRIP_FCS generate
    p_strip : process(clk)
        -- Set delay to ensure we have at least four bytes in buffer.
        constant DELAY_MAX : integer := div_ceil(FCS_BYTES, IO_BYTES);
        type sreg_t is array(0 to DELAY_MAX) of data_t;
        variable sreg : sreg_t := (others => (others => '0'));
        -- Maximum "overflow" size if IO_BYTES doesn't divide evenly.
        function OVR_MAX return integer is
            constant dly : integer := DELAY_MAX * IO_BYTES;
        begin
            if (dly >= FCS_BYTES) then
                return dly - FCS_BYTES;
            else
                return dly;
            end if;
        end function;
        constant OVR_THR : integer := IO_BYTES - OVR_MAX;
        variable ovr_ct  : integer range 0 to OVR_MAX := 0;
        -- Countdown to detect when we've received at least four bytes.
        variable count : integer range 0 to DELAY_MAX := DELAY_MAX;
    begin
        if rising_edge(clk) then
            -- Delay input using a shift register.
            if (crc_write = '1' or ovr_ct > 0) then
                sreg := crc_data & sreg(0 to DELAY_MAX-1);
            end if;
            trim_data <= sreg(DELAY_MAX);

            -- Once the initial delay has elapsed, forward valid/nlast.
            if (ovr_ct > 0) then
                trim_write <= '1';      -- Extra trailing word
                trim_nlast <= ovr_ct;
            elsif (count = 0 and crc_nlast > 0) then
                trim_write <= '1';      -- End of input frame
                if (crc_nlast > OVR_THR) then
                    trim_nlast <= 0;    -- Overflow required
                else
                    trim_nlast <= crc_nlast + OVR_MAX;
                end if;
            else
                trim_write <= crc_write and bool2bit(count = 0);
                trim_nlast <= 0;        -- Forward delayed data
            end if;

            -- Drive the commit/revert/error strobes.
            if (ovr_ct > 0) then
                trim_result <= buf_result;      -- Delayed output
            elsif (count > 0 or crc_nlast > OVR_THR) then
                trim_result <= (others => '0'); -- Suppress output
            else
                trim_result <= frm_result;      -- Prompt output
            end if;

            -- Drive the overflow counter, if enabled.
            if (reset_p = '1' or OVR_MAX = 0) then
                ovr_ct := 0;
            elsif (crc_write = '1' and count < 2 and crc_nlast > OVR_THR) then
                ovr_ct := crc_nlast - OVR_THR;
            else
                ovr_ct := 0;
            end if;

            -- Counter suppresses the first four bytes in each frame.
            if (reset_p = '1') then
                count := DELAY_MAX; -- General reset
            elsif (crc_write = '1' and crc_nlast > 0) then
                count := DELAY_MAX; -- End of packet
            elsif (crc_write = '1' and count > 0) then
                count := count - 1; -- Countdown to zero
            end if;
        end if;
    end process;
end generate;

-- Select final output signal based on configuration.
out_data    <= trim_data            when STRIP_FCS else buf_data;
out_nlast   <= trim_nlast           when STRIP_FCS else buf_nlast;
out_write   <= trim_write           when STRIP_FCS else buf_write;
out_commit  <= trim_result.commit   when STRIP_FCS else buf_result.commit;
out_revert  <= trim_result.revert   when STRIP_FCS else buf_result.revert;
out_error   <= trim_result.error    when STRIP_FCS else buf_result.error;

end eth_frame_check;
