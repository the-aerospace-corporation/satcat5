--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Status reporting using Ethernet broadcast packets
--
-- This block sends out a status message, on demand or at a fixed interval.
-- It is typically used as part of the virtual Ethernet port for command
-- and control functions.  The message is simply a fixed-length bit-vector,
-- set by the parent block, and sent most-significant byte first.
--
-- When the status message is read, regardless of cause, this blocks sends
-- the "stat_read" signal.  Outputs are available as a simple strobe or
-- as a toggle signal, which can be useful for clock-domain crossing.
--
-- The dataa output is a byte-stream with AXI flow-control; each message
-- consists of a full Ethernet frame with the following format:
--    MAC destination: Constant (default broadcast = FF-FF-FF-FF-FF-FF)
--    MAC source: Constant (default "SatCat" = 53-61-74-43-61-74)
--    Ethertype: Constant (default 0x5C00)
--    Payload: Fixed-length status vector (big-endian user data)
--    Frame check sequence (FCS): 4 bytes, CRC32
--
-- If the status vector is shorter than 46 bytes, then the result will be
-- a runt frame. If this is undesirable, enable zero-padding before the
-- FCS by setting the "MIN_FRAME" generic to 64 bytes.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity config_send_status is
    generic (
    MSG_BYTES       : natural := 0;     -- Bytes per status message (0 = none)
    MSG_ETYPE       : std_logic_vector(15 downto 0) := x"5C00";
    MAC_DEST        : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";
    MAC_SOURCE      : std_logic_vector(47 downto 0) := x"5A5ADEADBEEF";
    AUTO_DELAY_CLKS : natural := 0;     -- Send every N clocks, or 0 for on-demand
    MIN_FRAME_BYTES : natural := 0);    -- Pad to minimum frame size?
    port (
    -- Status message, and optional write strobe (send immediately)
    status_val  : in  std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');
    status_wr   : in  std_logic := '0';

    -- Send signal each time the status word is read.
    stat_read_p : out std_logic;    -- Strobe
    stat_read_t : out std_logic;    -- Toggle

    -- Output stream, with flow control
    out_data    : out byte_t;
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end config_send_status;

architecture rtl of config_send_status is

constant FRAME_BYTES : integer := MSG_BYTES + 14;
subtype frame_t is std_logic_vector(8*FRAME_BYTES-1 downto 0);

signal msg_temp     : frame_t;
signal msg_start    : std_logic := '0';
signal msg_data     : byte_t := (others => '1');
signal msg_last     : std_logic := '0';
signal msg_valid    : std_logic := '0';
signal msg_ready    : std_logic;
signal msg_done_p   : std_logic := '0';
signal msg_done_t   : std_logic := '0';
signal status_reg   : std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');

begin

-- Countdown to next automatic message, if applicable.
gen_auto : if (AUTO_DELAY_CLKS > 0) generate
    p_start : process(clk)
        constant COUNT_RST : integer := AUTO_DELAY_CLKS-1;
        variable count : integer range 0 to COUNT_RST := COUNT_RST;
    begin
        if rising_edge(clk) then
            if (reset_p = '1') then
                msg_start <= '0';
                count := COUNT_RST;
            elsif (status_wr = '1' or count = 0) then
                msg_start <= '1';
                count := COUNT_RST;
            else
                msg_start <= '0';
                count := count - 1;
            end if;
        end if;
    end process;
end generate;

gen_manual : if (AUTO_DELAY_CLKS < 1) generate
    msg_start <= status_wr; -- No auto, manual only
end generate;

-- Latch status word at start of new message.
p_status : process(clk)
begin
    if rising_edge(clk) then
        if (msg_start = '1' and (msg_valid = '0' or msg_last = '1')) then
            status_reg <= status_val;
        end if;
    end if;
end process;

-- Concatenate the full frame contents for readability.
-- (Most of this should be optimized away...)
msg_temp <= MAC_DEST & MAC_SOURCE & MSG_ETYPE & status_reg;

-- Message formatting state machine.
p_msg : process(clk)
    function get_byte(x : frame_t; b : integer) return byte_t is
        variable temp : byte_t := x(8*b+7 downto 8*b);
    begin
        return temp;
    end function;
    variable byte_idx : integer range 0 to FRAME_BYTES-1 := 0;
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            -- Global reset -> idle state.
            msg_data    <= (others => '1');
            msg_last    <= '0';
            msg_valid   <= '0';
            byte_idx    := 0;
        elsif (msg_valid = '0' or (msg_ready = '1' and msg_last = '1')) then
            -- Get ready to start next packet.
            -- Note: First byte is always destination MAC.
            msg_data    <= get_byte(msg_temp, FRAME_BYTES-1);
            msg_last    <= bool2bit(FRAME_BYTES = 1);
            msg_valid   <= msg_start;
            byte_idx    := FRAME_BYTES-1;
        elsif (msg_ready = '1') then
            -- Emit the next byte in the frame:
            msg_data    <= get_byte(msg_temp, byte_idx-1);
            msg_last    <= bool2bit(byte_idx = 1);
            msg_valid   <= '1';
            -- Decrement byte counter.
            byte_idx    := byte_idx - 1;
        end if;
    end if;
end process;

-- Send the "done" indicator at the end of each frame.
p_done : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            msg_done_p  <= '0';
            msg_done_t  <= '0';
        elsif (msg_last = '1' and msg_valid = '1' and msg_ready = '1') then
            msg_done_p  <= '1';
            msg_done_t  <= not msg_done_t;
        else
            msg_done_p  <= '0';
        end if;
    end if;
end process;

stat_read_p <= msg_done_p;
stat_read_t <= msg_done_t;

-- Append zeros to minimum frame size, if applicable, then append FCS.
u_fcs : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME_BYTES, -- Zero-pad, if applicable.
    STRIP_FCS   => false)           -- Input stream has no FCS.
    port map(
    in_data     => msg_data,
    in_last     => msg_last,
    in_valid    => msg_valid,
    in_ready    => msg_ready,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

end rtl;
