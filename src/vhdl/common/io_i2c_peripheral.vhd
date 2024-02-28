--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- General-purpose I2C peripheral.
--
-- This block listens to an attached I2C bus for commands addressed to a
-- particular 7-bit peripheral address, adjustable at runtime.  Once a
-- matching address is detected, it receives or transmits a stream of bytes
-- as appropriate until it receives a STOP token.
--
-- Generally, the top-level should instantiate a bidirectional buffer, to
-- connect SCL and SDA to their respective I/O pads.  For more details,
-- refer to "io_i2c_controller.vhd".  If clock stretching is not required,
-- then the output pin "SCL_O" may be left disconnected.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.i2c_constants.all;         -- io_i2c_controller.vhd

entity io_i2c_peripheral is
    port (
    -- External I2C signals (active-low, suitable for sharing)
    -- Note: Top level should instantiate tri-state buffer.
    -- Note: sclk_o is required for clock-stretching, otherwise optional.
    sclk_o      : out std_logic;
    sclk_i      : in  std_logic;
    sdata_o     : out std_logic;
    sdata_i     : in  std_logic;

    -- Set I2C device address.
    i2c_addr    : i2c_addr_t;

    -- Received data
    rx_data     : out i2c_data_t;       -- Received data byte
    rx_write    : out std_logic;        -- Received data strobe
    rx_start    : out std_logic;        -- Received START token
    rx_rdreq    : out std_logic;        -- Received READ request
    rx_stop     : out std_logic;        -- Received STOP token

    -- Transmit data (AXI flow-control)
    -- Note: I2C clock-stretching if expected Tx data is withheld.
    tx_data     : in  i2c_data_t;       -- Transmit data byte
    tx_valid    : in  std_logic;        -- AXI flow control
    tx_ready    : out std_logic;        -- AXI flow control

    -- Reference clock and reset
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic);
end io_i2c_peripheral;

architecture io_i2c_peripheral of io_i2c_peripheral is

type comm_states_t is (
    COMM_IDLE,      -- I2C bus is idle
    COMM_ADDRESS,   -- First byte is always I2C address
    COMM_IGNORE,    -- I2C transmitting to a different device
    COMM_DATA_WR,   -- Receiving write data
    COMM_DATA_RD    -- Sending read data
);

-- Input buffering.
signal sclk_i1      : std_logic := '1';     -- Sync'd clock from input pin
signal sclk_i2      : std_logic := '1';     -- Delayed clock from input pin
signal sclk_oo      : std_logic := '1';     -- Clock signal to output pin
signal sdata_i1     : std_logic := '1';     -- Sync'd data from input pin
signal sdata_i2     : std_logic := '1';     -- Delayed data from input pin
signal sdata_oo     : std_logic := '1';     -- Data signal to output pin

-- Bus state
signal i2c_state    : comm_states_t := COMM_IDLE;
signal i2c_bcount   : integer range 0 to 8 := 0;
signal i2c_rxbuff   : i2c_data_t := (others => '0');
signal i2c_rxwrite  : std_logic := '0';
signal i2c_txbuff   : i2c_data_t := (others => '1');
signal i2c_txcken   : std_logic;
signal i2c_txread   : std_logic;
signal i2c_start    : std_logic := '0';
signal i2c_rdreq    : std_logic := '0';
signal i2c_stop     : std_logic := '0';
signal addr_match   : std_logic;

begin

-- Buffer and synchronize raw bus signals.
sclk_o  <= sclk_oo;
sdata_o <= i2c_txbuff(7);   -- MSB-first

sync_sclk : sync_buffer
    port map(
    in_flag  => sclk_i,
    out_flag => sclk_i1,
    out_clk  => ref_clk);
sync_sdata : sync_buffer
    port map(
    in_flag  => sdata_i,
    out_flag => sdata_i1,
    out_clk  => ref_clk);

-- Drive all other top-level outputs.
rx_data     <= i2c_rxbuff;
rx_write    <= i2c_rxwrite;
rx_start    <= i2c_start;
rx_rdreq    <= i2c_rdreq;
rx_stop     <= i2c_stop;
tx_ready    <= i2c_txread;

-- Address matching, including the "general call" address.
addr_match  <= bool2bit(i2c_addr = i2c_rxbuff(7 downto 1))
            or bool2bit(i2c_addr = I2C_ADDR_ANY);

-- Update the output shift-register on falling edge or clock-stretch.
i2c_txcken <= (sclk_i2 and not sclk_i1) or (not sclk_oo);
i2c_txread <= i2c_txcken and bool2bit(i2c_state = COMM_DATA_RD and i2c_bcount = 0);

-- I2C state machine
p_i2c : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        -- Set defaults for event strobes.
        i2c_start   <= '0';
        i2c_rdreq   <= '0';
        i2c_stop    <= '0';
        i2c_rxwrite <= '0';

        -- Delay both input signals so we can detect edges.
        sclk_i2     <= sclk_i1;
        sdata_i2    <= sdata_i1;

        -- Update received data on rising-edge SCLK.
        -- Fire the WRITE strobe at the end of each received byte.
        if (sclk_i2 = '0' and sclk_i1 = '1') then
            i2c_rxbuff  <= i2c_rxbuff(6 downto 0) & sdata_i1;
            i2c_rxwrite <= bool2bit(i2c_bcount = 7 and i2c_state = COMM_DATA_WR);
        end if;

        -- Drive the SCLK output (clock-stretching only)
        if (i2c_txread = '1') then
            sclk_oo <= tx_valid;    -- Hold clock low until we get data
        else
            sclk_oo <= '1';         -- Otherwise don't touch SCLK.
        end if;

        -- Update the SDATA output, usually on falling edge of SCLK.
        if (reset_p = '1') then
            -- Idle on reset
            i2c_txbuff <= (others => '1');
        elsif (i2c_state = COMM_ADDRESS) then
            -- Receiving address (send ACK if applicable)
            if (i2c_txcken = '1') then
                if (i2c_bcount = 8 and addr_match = '1') then
                    i2c_txbuff <= (others => '0');
                else
                    i2c_txbuff <= (others => '1');
                end if;
            end if;
        elsif (i2c_state = COMM_DATA_WR) then
            -- Receiving data from host (send ACK after each byte)
            if (i2c_txcken = '1') then
                if (i2c_bcount = 8) then
                    i2c_txbuff <= (others => '0');
                else
                    i2c_txbuff <= (others => '1');
                end if;
            end if;
        elsif (i2c_state = COMM_DATA_RD) then
            -- Sending data to host (one byte, MSB-first, then host sends ACK)
            if (i2c_txcken = '1') then
                if (i2c_bcount = 0) then
                    i2c_txbuff <= tx_data;
                else
                    i2c_txbuff <= i2c_txbuff(6 downto 0) & '1';
                end if;
            end if;
        else
            -- Idle in all other states.
            i2c_txbuff <= (others => '1');
        end if;

        -- Update internal state and bit-counter:
        if (reset_p = '1') then
            -- Global reset -> idle.
            i2c_state   <= COMM_IDLE;
            i2c_bcount  <= 0;
        elsif (sdata_i2 = '1' and sdata_i1 = '0' and sclk_i2 = '1' and sclk_i1 = '1') then
            -- I2C start token (falling-edge SDA while SCL = '1')
            i2c_state   <= COMM_ADDRESS;
            i2c_bcount  <= 0;
            i2c_start   <= '1';
        elsif (sdata_i2 = '0' and sdata_i1 = '1' and sclk_i2 = '1' and sclk_i1 = '1') then
            -- I2C stop token (rising-edge SDA while SCL = '1')
            i2c_state   <= COMM_IDLE;
            i2c_bcount  <= 0;
            i2c_stop    <= '1';
        elsif (sclk_i2 = '0' and sclk_i1 = '1') then
            -- Rising edge SCL: Increment bit counter
            i2c_bcount <= (i2c_bcount + 1) mod 9;
        elsif (sclk_i2 = '1' and sclk_i1 = '0') then
            -- Falling edge SCL: Update state based on received byte.
            if (i2c_state = COMM_ADDRESS and i2c_bcount = 8) then
                -- Matching address received?
                if (addr_match = '0') then
                    i2c_state <= COMM_IGNORE;   -- Not our address, ignore
                elsif (i2c_rxbuff(0) = '0') then
                    i2c_state <= COMM_DATA_WR;  -- Address + Write flag
                else
                    i2c_state <= COMM_DATA_RD;  -- Address + Read flag
                end if;
            elsif (i2c_state = COMM_DATA_RD and i2c_bcount = 0) then
                -- Stop reads if controller didn't send an acknowledge.
                if (i2c_rxbuff(0) = '1') then
                    i2c_state <= COMM_IGNORE;   -- End of multi-byte read
                else
                    i2c_rdreq <= '1';           -- Continued read
                end if;
            end if;
        end if;
    end if;
end process;

end io_i2c_peripheral;
