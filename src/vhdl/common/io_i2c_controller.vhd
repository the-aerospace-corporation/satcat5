--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- General-purpose I2C controller.
--
-- This block implements a flexible, software-controlled I2C bus controller.
-- Each bus operation (start-bit, stop-bit, byte transfer, etc.) is directly
-- commanded by an upstream state machine, one byte at a time.
--
-- The bus state-machine is compatible with clock stretching but does not
-- currently support multi-controller modes.  Since there is no distinction
-- between address and data bytes, it can support both 7-bit and 10-bit
-- address modes with the appropriate control logic.
--
-- The NOACK flag indicates the remote device did not send an expected
-- acknowledge bit.  It is cleared by each START opcode.
--
-- Generally, the top-level should instantiate a bidirectional buffer, to
-- connect SCL and SDA to their respective I/O pads.  (The raw signals
-- are left disconnected to facilitate pin-sharing and testing.)
--
-- Connect SCL_O and SDA_O to both the output and the tristate-enable:
--    u_pin_scl : bidir_io
--        generic map(EN_PULLUP => true)
--        port map(
--        io_pin  => scl_pin,
--        d_in    => scl_i,
--        d_out   => scl_o,
--        t_en    => scl_o);
--    u_pin_sda : bidir_io
--        generic map(EN_PULLUP => true)
--        port map(
--        io_pin  => sda_pin,
--        d_in    => sda_i,
--        d_out   => sda_o,
--        t_en    => sda_o);
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

-- Define a package with useful constants.
package i2c_constants is
    -- Address is a seven-bit field, not including the read/write flag.
    subtype i2c_addr_t is std_logic_vector(7 downto 1);
    constant I2C_ADDR_ANY   : i2c_addr_t := (others => '0');

    -- Count number of cycles per 1/4 output cycle.
    subtype i2c_clkdiv_t is unsigned(11 downto 0);

    -- Define command codes
    subtype i2c_cmd_t is std_logic_vector(3 downto 0);
    constant CMD_DELAY      : i2c_cmd_t := x"0";
    constant CMD_START      : i2c_cmd_t := x"1";
    constant CMD_RESTART    : i2c_cmd_t := x"2";
    constant CMD_STOP       : i2c_cmd_t := x"3";
    constant CMD_TXBYTE     : i2c_cmd_t := x"4";
    constant CMD_RXBYTE     : i2c_cmd_t := x"5";
    constant CMD_RXFINAL    : i2c_cmd_t := x"6";

    -- All I2C data is exchanged one byte at a time.
    subtype i2c_data_t is std_logic_vector(7 downto 0);

    -- Given clock rate and baud rate, calculate clock-divider setting.
    function i2c_get_clkdiv(ref_hz, baud_hz : positive) return i2c_clkdiv_t;
end package;

package body i2c_constants is
    function i2c_get_clkdiv(ref_hz, baud_hz : positive) return i2c_clkdiv_t is
        variable ratio  : positive := clocks_per_baud(ref_hz, 4*baud_hz);
        variable clkdiv : i2c_clkdiv_t := to_unsigned(ratio-1, 12);
    begin
        return clkdiv;
    end function;
end package body;

---------------------------- Main block ----------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.i2c_constants.all;

entity io_i2c_controller is
    port (
    -- External I2C signals (active-low, suitable for sharing)
    -- Note: Top level should instantiate tri-state buffer.
    -- Note: sclk_i is required for clock-stretching, otherwise optional.
    sclk_o      : out std_logic;
    sclk_i      : in  std_logic := '1';
    sdata_o     : out std_logic;
    sdata_i     : in  std_logic := '1';

    -- Configuration interface.
    cfg_clkdiv  : in  i2c_clkdiv_t;     -- SCLK-divider = 4*(N+1)
    cfg_nowait  : in  std_logic := '0'; -- Disable clock-stretching?

    -- Command interface, AXI flow-control.
    tx_opcode   : in  i2c_cmd_t;        -- Next command (see i2c_constants)
    tx_data     : in  i2c_data_t;       -- Transmit data (if applicable)
    tx_valid    : in  std_logic;        -- Flow control
    tx_ready    : out std_logic;        -- Flow control

    -- Received data interface
    rx_data     : out i2c_data_t;       -- Received data (if applicable)
    rx_write    : out std_logic;        -- Data-valid strobe
    bus_stop    : out std_logic;        -- Stop token sent to device
    bus_noack   : out std_logic;        -- Missing ACK from device

    -- Reference clock and reset
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic);
end io_i2c_controller;

architecture io_i2c_controller of io_i2c_controller is

-- Input buffering.
signal sclk_oo      : std_logic := '1';     -- Clock signal to output pin
signal sclk_od      : std_logic := '1';     -- Delayed output (matched to sclk_id)
signal sclk_id      : std_logic := '1';     -- Sync'd clock from input pin
signal sdata_id     : std_logic := '1';     -- Sync'd data from input pin
signal sdata_oo     : std_logic := '1';     -- Data signal to output pin

-- Clock divider state
signal clk_phase    : integer range 0 to 3 := 0;  -- Count 0 to 3 each bit
signal clk_rnext    : std_logic := '0';     -- Strobe: Read bit from device
signal clk_wnext    : std_logic := '0';     -- Strobe: About to change to next bit

-- Command state
signal byte_read    : std_logic := '0';
signal byte_final   : std_logic := '0';
signal cmd_noack    : std_logic := '0';
signal cmd_bcount   : integer range 0 to 8 := 0;
signal rx_sreg      : i2c_data_t := (others => '0');

begin

-- Buffer and synchronize raw bus signals.
sclk_o  <= sclk_oo;
sdata_o <= sdata_oo;

sync_sclk : sync_buffer
    port map(
    in_flag  => sclk_i,
    out_flag => sclk_id,
    out_clk  => ref_clk);
sync_sdata : sync_buffer
    port map(
    in_flag  => sdata_i,
    out_flag => sdata_id,
    out_clk  => ref_clk);

-- Drive all other top-level outputs.
tx_ready    <= clk_wnext and byte_final;
rx_data     <= rx_sreg;
rx_write    <= clk_wnext and byte_read;
bus_noack   <= cmd_noack;
bus_stop    <= clk_wnext and bool2bit(tx_opcode = CMD_STOP);

-- Clock divider state machine:
p_clkdiv : process(ref_clk)
    -- Count number of cycles per 1/4 output cycle.  (Round up)
    variable clk_counter : i2c_clkdiv_t := (others => '1');
    variable next_phase  : std_logic := '0';
begin
    if rising_edge(ref_clk) then
        -- Increment clock-phase on the cycle after WNEXT/RNEXT.
        if (tx_valid = '0') then
            clk_phase <= 0;
        elsif (next_phase = '1') then
            if (clk_phase = 3) then
                clk_phase <= 0;
            else
                clk_phase <= clk_phase + 1;
            end if;
        end if;

        -- Default values for read/write/next strobes.
        clk_wnext   <= '0';
        clk_rnext   <= '0';
        next_phase  := '0';

        -- Countdown timer to the next clock-phase increment.
        if (tx_valid = '0') then
            -- Clock is idle; reset all counters.
            clk_counter := cfg_clkdiv;
        elsif (cfg_nowait = '0' and sclk_id = '0' and sclk_od = '1') then
            -- Remote device is requesting clock-stretch.
            -- Reset counter to avoid race conditions on restart.
            clk_counter := cfg_clkdiv;
        elsif (clk_counter > 0) then
            -- Countdown to end of current clock phase.
            clk_counter := clk_counter - 1;
        else
            -- Countdown reached zero, increment phase.
            clk_counter := cfg_clkdiv;
            next_phase  := '1';
            clk_rnext   <= bool2bit(clk_phase = 1);
            clk_wnext   <= bool2bit(clk_phase = 3);
        end if;
    end if;
end process;

-- Clock output logic:
p_clock : process(ref_clk)
    variable sclk_d1 : std_logic := '1';
begin
    if rising_edge(ref_clk) then
        -- Two-cycle matched delay for comparing to input.
        sclk_od <= reset_p or sclk_d1;
        sclk_d1 := reset_p or sclk_oo;

        -- Main output pin
        if (reset_p = '1') then
            -- Reset to idle state.
            sclk_oo <= '1';
        elsif (tx_valid = '0' or tx_opcode = CMD_DELAY) then
            -- No command or explicit delay, leave SCLK where it is.
            sclk_oo <= sclk_oo;
        else
            -- Normal case: 0/1/1/0 (including restart)
            -- Start bit:   1/1/1/0
            -- Stop bit:    0/1/1/1
            case clk_phase is
                when 0 => sclk_oo <= bool2bit(tx_opcode = CMD_START);
                when 1 => sclk_oo <= '1';
                when 2 => sclk_oo <= '1';
                when 3 => sclk_oo <= bool2bit(tx_opcode = CMD_STOP);
            end case;
        end if;
    end if;
end process;

-- Main state machine:
p_dout : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        -- Drive the byte-final and byte-read flags.
        byte_final <= bool2bit(cmd_bcount = 8) or
            bool2bit(tx_opcode = CMD_START or tx_opcode = CMD_RESTART or
                     tx_opcode = CMD_STOP or tx_opcode = CMD_DELAY);
        byte_read <= bool2bit(cmd_bcount = 7) and
            bool2bit(tx_opcode = CMD_RXBYTE or tx_opcode = CMD_RXFINAL);

        -- Received data shift register:
        if (clk_rnext = '1') then
            rx_sreg <= rx_sreg(6 downto 0) & sdata_id;  -- MSB first
        end if;

        -- Sticky error flag for missing ACK from remote device.
        if (reset_p = '1') then
            cmd_noack <= '0';       -- Clear on bus reset
        elsif (tx_opcode = CMD_START and clk_wnext = '1') then
            cmd_noack <= '0';       -- Clear on START token
        elsif (tx_opcode = CMD_TXBYTE and clk_rnext = '1') then
            -- Expect ACK during 8th bit of each CMD_TXBYTE.
            if (cmd_bcount = 8 and sdata_id = '1') then
                cmd_noack <= '1';   -- Set on missing ACK.
            end if;
        end if;

        -- Drive the output signal and update bit-counter.
        if (reset_p = '1') then
            -- Reset to idle state.
            sdata_oo    <= '1';
            cmd_bcount  <= 0;
        elsif (tx_valid = '0' or tx_opcode = CMD_DELAY) then
            -- Idle or delay command, no change to output.
            cmd_bcount  <= 0;
        elsif (tx_opcode = CMD_START or tx_opcode = CMD_RESTART) then
            -- Start bits transition high-to-low in middle of bit period.
            sdata_oo    <= bool2bit(clk_phase < 2);
            cmd_bcount  <= 0;
        elsif (tx_opcode = CMD_STOP) then
            -- Stop bits transition low-to-high in middle of bit period.
            sdata_oo    <= bool2bit(clk_phase >= 2);
            cmd_bcount  <= 0;
        elsif (tx_opcode = CMD_TXBYTE) then
            -- Send 8 bits, MSB first; then wait for ACK.
            if (cmd_bcount < 8) then
                sdata_oo <= tx_data(7-cmd_bcount);
            else
                sdata_oo <= '1';
            end if;
            -- Update bit counter.
            if (clk_wnext = '1') then
                cmd_bcount <= (cmd_bcount + 1) mod 9;
            end if;
        elsif (tx_opcode = CMD_RXBYTE or tx_opcode = CMD_RXFINAL) then
            -- Receive 8 bits, MSB first, then send ACK unless final.
            sdata_oo <= bool2bit(cmd_bcount < 8 or tx_opcode = CMD_RXFINAL);
            -- Update bit counter.
            if (clk_wnext = '1') then
                cmd_bcount <= (cmd_bcount + 1) mod 9;
            end if;
        end if;
    end if;
end process;

end io_i2c_controller;
