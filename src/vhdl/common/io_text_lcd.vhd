--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Streaming LCD interface controller
--
-- This module controls the S162D LCD display that is included with the
-- AC701 Artix-7 Evaluation Kit.  New text is written to a small buffer,
-- one byte at a time.  A newline character transfers that working buffer
-- to the LCD display.
--
-- See also: ST7066U datasheet:
--  https://www.newhavendisplay.com/app_notes/ST7066U.pdf
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity io_text_lcd is
    generic (
    REFCLK_HZ   : integer;          -- Reference clock frequency
    MSG_WAIT    : integer := 255);  -- Minimum time before refresh (msec)
    port (
    -- LCD interface
    lcd_db      : out std_logic_vector(3 downto 0);  -- Data (4-bit mode)
    lcd_e       : out std_logic;      -- Chip enable
    lcd_rw      : out std_logic;      -- Read / write-bar
    lcd_rs      : out std_logic;      -- Data / command-bar

    -- Streaming data interface
    strm_clk    : in  std_logic;
    strm_data   : in  std_logic_vector(7 downto 0);
    strm_wr     : in  std_logic;
    reset_p     : in  std_logic);
end io_text_lcd;

architecture io_text_lcd of io_text_lcd is

-- Define various character constants and LCD command codes.
subtype nybb_t is std_logic_vector(3 downto 0);
subtype char_t is std_logic_vector(7 downto 0);
constant CHAR_NEWLINE_CR : char_t := "00001101";
constant CHAR_NEWLINE_LF : char_t := "00001010";
constant CHAR_SPACE      : char_t := "00100000";

-- Timing strobes.
signal strobe_4MHz      : std_logic := '0';
signal strobe_1kHz      : std_logic := '0';

-- Byte-level controller commands.
signal wr_byte      : std_logic := '0';  -- Normal write strobe
signal wr_nybb      : std_logic := '0';  -- Special write (one nibble only)
signal wr_is_cmd    : std_logic := '0';
signal wr_data      : char_t := (others => '0');

-- Higher-level controller commands.
signal cmd_busy     : std_logic := '0';
signal cmd_ready    : std_logic := '0';

-- Small FIFO for incoming data.
signal fifo_data    : char_t;
signal fifo_avail   : std_logic;
signal fifo_empty   : std_logic;
signal fifo_accept  : std_logic := '1';
signal fifo_rd      : std_logic := '0';
signal fifo_wr      : std_logic;

begin

-----------------------------------------------------------------
-- LCD Controller
-----------------------------------------------------------------

-- The "RW" pin (Read / Write-bar) is always set to write mode.
lcd_rw <= '0';

-- Simple clock divider to get strobes at 4MHz and 1kHz.
p_clkdiv : process(strm_clk)
    -- Calculate outer clock divider to get just under 4 MHz.
    constant DIV_OUTER : integer := (REFCLK_HZ + 3999999) / 4000000;  -- Round up
    constant DIV_INNER : integer := 4000;
    variable div1 : integer range 0 to DIV_OUTER-1 := DIV_OUTER-1;
    variable div2 : integer range 0 to DIV_INNER-1 := DIV_INNER-1;
begin
    if rising_edge(strm_clk) then
        strobe_4MHz <= bool2bit(div1 = 0);
        strobe_1kHz <= bool2bit(div1 = 0 and div2 = 0);

        if (reset_p = '1') then
            div1 := DIV_OUTER-1;
            div2 := DIV_INNER-1;
        elsif (div1 = 0) then
            div1 := DIV_OUTER-1;
            if (div2 = 0) then
                div2 := DIV_INNER-1;
            else
                div2 := div2 - 1;
            end if;
        else
            div1 := div1 - 1;
        end if;
    end if;
end process;

-- Low-level interface: Send byte, receive byte
p_lcd : process(strm_clk)
    variable state_ctr : integer range 0 to 5 := 0;
begin
    if rising_edge(strm_clk) then
        cmd_busy <= wr_byte or wr_nybb or bool2bit(state_ctr > 0);

        if (reset_p = '1') then
            lcd_db       <= (others => '0');
            lcd_e        <= '0';    -- Chip enable (active high)
            lcd_rs       <= '0';    -- '0' for command, '1' for data
            state_ctr    := 0;
        elsif (state_ctr /= 0) then
            -- Move on to the next state each time the strobe pulses.
            -- Enable pulse width must be at least 220 ns, with a 500 ns cycle time = 2 / (4 MHz).
            -- Setup and hold times are all very large (see datasheet).
            assert(wr_byte = '0' and wr_nybb = '0')
                report "LCD Control: Illegal write, still busy" severity warning;
            if (strobe_4MHz = '1') then
                case state_ctr is
                    when 5 =>  -- Wait one cycle to meet setup requirements for RS, RW pins
                        lcd_e   <= '0';
                    when 4 =>  -- Enable high; write first nibble
                        lcd_e   <= '1';
                        lcd_db  <= wr_data(7 downto 4);
                    when 3 =>  -- Enable low.
                        lcd_e   <= '0';
                    when 2 =>  -- Enable high; write second nibble
                        lcd_e   <= '1';
                        lcd_db  <= wr_data(3 downto 0);
                    when 1 =>  -- Enable low;.
                        lcd_e   <= '0';
                    when 0 =>  -- Unreachable (see above)
                        assert(false);
                end case;
                state_ctr := state_ctr - 1;
            end if;
        elsif (wr_byte = '1' or wr_nybb = '1') then
            -- Starting a read or write command.
            -- Store the output data for later, and start on the next strobe event.
            assert(wr_byte = '0' or wr_nybb = '0')
                report "LCD Control: Illegal write, nybb+byte" severity warning;
            if (wr_nybb = '1') then
                state_ctr := 3;  -- Only write one nibble (bits 3-0)
            else
                state_ctr := 5;  -- Normal case -> read or write full byte.
            end if;
            lcd_rs   <= not wr_is_cmd;
        end if;
    end if;
end process;

cmd_ready <= not (cmd_busy or wr_byte or wr_nybb);

-- Higher-level LCD initialization and refresh.
p_ctrl : process(strm_clk)
    constant INIT_WAIT : integer := 63; -- Need >40 ms delay before first write
    constant MAX_WAIT  : integer := int_max(INIT_WAIT, MSG_WAIT);
    type lcd_state_t is (IDLE, INIT, UPDATE_START, UPDATE_TRANSFER, UPDATE_FINISH);
    variable lcd_state  : lcd_state_t := INIT;
    variable counter    : integer range 0 to MAX_WAIT := INIT_WAIT;
    variable first_line : std_logic := '1';
begin
    if rising_edge(strm_clk) then
        fifo_rd     <= '0';
        wr_byte     <= '0';
        wr_nybb     <= '0';

        -- Main LCD state machine:
        if (reset_p = '1') then
            -- Start at the beginning of the init sequence.
            lcd_state       := INIT;
            counter         := INIT_WAIT;
            first_line      := '1';
        elsif (lcd_state = IDLE) then
            -- Idle, waiting for next display refresh.
            if (counter > 0) then
                -- Delay countdown after each message.
                if (strobe_1kHz = '1') then
                    counter := counter - 1;
                end if;
            elsif (fifo_avail = '1') then
                -- Start screen refresh process.
                lcd_state  := UPDATE_START;
                first_line := '1';
                counter    := 2;
            end if;
        elsif (lcd_state = INIT) then
            -- Initialization sequence involves several writes, with long delays
            -- in between each write.  Use a countdown driven by the 1 kHz strobe.
            -- See the recommended initialization sequence in the datasheet.
            if (strobe_1kHz = '1' and cmd_ready = '1') then
                wr_is_cmd <= '1';
                case counter is
                    when 12 => -- (Wakeup pulse #1)
                        wr_nybb <= '1'; wr_data <= x"33";
                    when  7 => -- (Wakeup pulse #2)
                        wr_nybb <= '1'; wr_data <= x"33";
                    when  6 => -- (Wakeup pulse #3)
                        wr_nybb <= '1'; wr_data <= x"33";
                    when  5 => -- Function set = 4-bit mode, 2 lines, 5x10 font
                        wr_byte <= '1'; wr_data <= x"2C";
                    when  4 => -- Function set (must be repeated due to 4-bit switch)
                        wr_byte <= '1'; wr_data <= x"2C";
                    when  3 => -- Display off, cursor off
                        wr_byte <= '1'; wr_data <= x"08";
                    when  2 => -- Display clear + wait 2 msec
                        wr_byte <= '1'; wr_data <= x"01";
                    when  0 => -- Entry mode set + done
                        wr_byte <= '1'; wr_data <= x"06";
                    when others => null; -- All others are just a delay
                end case;
                -- Done with init?
                if (counter = 0) then
                    lcd_state := IDLE;
                else
                    counter := counter - 1;
                end if;
            end if;
        elsif (lcd_state = UPDATE_START) then
            -- Before we start the transfer, clear and disable the display.
            -- Otherwise, the refresh will be visible, character by character.
            -- (We use the worst-case delay between all commands, so we don't
            --  have to poll the busy flag.)
            if (strobe_1kHz = '1' and cmd_ready = '1') then
                wr_is_cmd <= '1';
                case counter is
                    when 2 => -- Display off, cursor off
                        wr_byte <= '1'; wr_data <= x"08";
                    when 1 => -- Display clear (takes ~1.5 msec)
                        wr_byte <= '1'; wr_data <= x"01";
                    when others => null;    -- Delay / idle
                end case;
                -- Done with pre-update init?
                if (counter = 0) then
                    lcd_state := UPDATE_TRANSFER;
                    counter   := 15;
                else
                    counter   := counter - 1;
                end if;
            end if;
        elsif (lcd_state = UPDATE_TRANSFER) then
            -- Transfer each byte from FIFO to the LCD.
            if (strobe_1kHz = '1' and cmd_ready = '1') then
                -- Send next FIFO byte, replacing special or missing characters.
                wr_is_cmd <= '0';
                wr_byte   <= '1';
                -- Replace special or missing characters.
                if (fifo_avail = '0') then
                    wr_data <= CHAR_SPACE;  -- No data --> placeholder.
                elsif (fifo_data = CHAR_NEWLINE_CR) then
                    wr_data <= CHAR_SPACE;  -- Newline --> placeholder.
                    fifo_rd <= '1';         -- Consume this character
                elsif (fifo_data = CHAR_NEWLINE_LF) then
                    wr_data <= CHAR_SPACE;  -- Newline --> placeholder.
                    fifo_rd <= '0';         -- Hold until EOL, see below.
                else
                    wr_data <= fifo_data;   -- Normal character, copy to LCD.
                    fifo_rd <= '1';
                end if;
                -- Update countdown, move to next state.
                if (counter = 0) then
                    lcd_state := UPDATE_FINISH;
                else
                    counter := counter - 1;
                end if;
            end if;

        elsif (lcd_state = UPDATE_FINISH) then
            -- Finished transferring one line.
            if (strobe_1kHz = '1' and cmd_ready = '1') then
                -- Handle end-of-line commands.
                wr_is_cmd  <= '1';
                wr_byte    <= '1';
                if (first_line = '1') then
                    -- End of first line -> set write address to start of second line.
                    wr_data    <= x"C0";    -- Set display data address = 0x40
                    lcd_state  := UPDATE_TRANSFER;
                    counter    := 15;       -- Second line = 16 characters
                    first_line := '0';
                else
                    -- Update complete!  Re-enable the display, then revert to idle.
                    wr_data   <= x"0C";     -- Display on, cursor off
                    counter   := MSG_WAIT;  -- Min delay before next refresh
                    lcd_state := IDLE;
                end if;
                -- Consume newline character from FIFO, if applicable.
                if (fifo_avail = '1' and fifo_data = CHAR_NEWLINE_LF) then
                    fifo_rd <= '1';
                end if;
            end if;
        end if;
    end if;
end process;

-- Small FIFO for incoming data.
fifo_wr <= strm_wr and fifo_accept;
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,  -- Each word 8 bits
    DEPTH_LOG2  => 5)  -- Depth 2^5 = 32 bytes
    port map(
    in_data     => strm_data,
    in_write    => fifo_wr,
    out_data    => fifo_data,
    out_valid   => fifo_avail,
    out_read    => fifo_rd,
    fifo_empty  => fifo_empty,
    reset_p     => reset_p,
    clk         => strm_clk);

-- Ignore FIFO inputs once full, or messages may get jumbled.
p_msgctrl : process(strm_clk)
    variable mid_msg : std_logic := '0';
    variable char_ct : integer range 0 to 15 := 0;
    variable line_ct : integer range 0 to 1 := 0;
begin
    if rising_edge(strm_clk) then
        -- Update FIFO accept/reject state.
        if (reset_p = '1') then
            fifo_accept <= '1'; -- Global reset, accept new data.
        elsif (fifo_empty = '1' and mid_msg = '0') then
            fifo_accept <= '1'; -- Idle state, accept new data.
        elsif (strm_wr = '1' and line_ct = 1 and (char_ct = 15 or strm_data = CHAR_NEWLINE_LF)) then
            fifo_accept <= '0'; -- Two full lines --> stop accepting.
        end if;

        -- Count accepted characters/lines in buffer.
        if (fifo_wr = '1') then
            -- Count each accepted character...
            if (char_ct = 15 or strm_data = CHAR_NEWLINE_LF) then
                -- End of line (Newline or 16 other characters).
                char_ct := 0;
                line_ct := 1 - line_ct;
            else
                -- Keep counting regular characters.
                char_ct := char_ct + 1;
            end if;
        elsif (fifo_empty = '1') then
            -- Reset between messages.
            char_ct := 0;
            line_ct := 0;
        end if;

        -- Check if we are in the middle of an input line.
        if (reset_p = '1') then
            mid_msg := '0';
        elsif (strm_wr = '1') then
            mid_msg := bool2bit(strm_data /= CHAR_NEWLINE_LF);
        end if;
    end if;
end process;

end io_text_lcd;
