--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus host with Ethernet packet interface
--
-- This is a unit test for the Ethernet to ConfigBus bridge.
-- It sends a series of read and write commands and verifies that they
-- are executed correctly and that the replies are correct.
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity cfgbus_host_eth_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_host_eth_tb;

architecture tb of cfgbus_host_eth_tb is

constant CFG_ETYPE      : mac_type_t := x"5C01";
constant REPLY_ETYPE    : mac_type_t := x"5C02";
constant CFG_MACADDR    : mac_addr_t := x"5A5ADEADBEEF";
constant HOST_MACADDR   : mac_addr_t := x"123456123456";

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- ConfigBus host interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;

-- Network streams.
signal rx_data      : byte_t := (others => '0');
signal rx_last      : std_logic := '0';
signal rx_valid     : std_logic := '0';
signal rx_ready     : std_logic;
signal rx_write     : std_logic;
signal rx_done      : std_logic := '0';
signal tx_data      : byte_t;
signal tx_last      : std_logic;
signal tx_valid     : std_logic;
signal tx_ready     : std_logic := '0';
signal tx_count     : natural := 0;
signal tx_done      : std_logic := '0';

-- Test control.
signal rate_tx      : real := 0.0;
signal rate_rx      : real := 0.0;
signal reg_val      : cfgbus_word;
signal test_index   : natural := 0;
signal test_start   : std_logic := '0';
shared variable test_pkt_tx : eth_packet;
shared variable test_pkt_rx : eth_packet;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Network stream generation.
p_net : process(clk_100)
    variable rx_rem : natural := 0;
    variable tx_rem : natural := 0;
    variable idle   : natural := 0;
    variable tx_end : std_logic := '0';
    variable tx_ref : byte_t := (others => '0');
begin
    if rising_edge(clk_100) then
        -- Reset counters at start of packet and update "done" flag.
        if (test_start = '1') then
            assert (tx_rem = 0)
                report "Test-start during Tx-busy." severity error;
            rx_rem      := test_pkt_rx.all'length;
            tx_rem      := test_pkt_tx.all'length;
            tx_end      := '0';
            tx_count    <= 0;
        elsif (tx_valid = '1' and tx_ready = '1') then
            tx_end      := tx_last;
            tx_count    <= tx_count + 1;
        end if;

        -- Update the "rx_done" and "tx_done" flags.
        rx_done <= bool2bit(rx_rem = 0);

        if (reset_p = '1' or test_start = '1') then
            tx_done <= '0';     -- Start of command
        elsif (tx_end = '1' and idle > 20) then
            tx_done <= '1';     -- Received expected reply-length
        elsif (idle > 100) then
            tx_done <= '1';     -- Idle timeout
        end if;

        -- Count idle cycles.
        if ((reset_p = '1') or (test_start = '1') or (rx_write = '1') or
            (tx_valid = '1' and tx_ready = '1')) then
            idle := 0;
        else
            idle := idle + 1;
        end if;

        -- Generate the command stream.
        if (reset_p = '1') then
            -- Global reset
            rx_data  <= (others => '0');
            rx_last  <= '0';
            rx_valid <= '0';
        elsif (rx_valid = '1' and rx_ready = '0') then
            -- Hold current data
            rx_data  <= rx_data;
            rx_last  <= rx_last;
            rx_valid <= '1';
            null;
        elsif (rx_rem > 0 and rand_bit(rate_rx) = '1') then
            -- Emit next byte.
            rx_data  <= test_pkt_rx.all(rx_rem-1 downto rx_rem-8);
            rx_last  <= bool2bit(rx_rem = 8);
            rx_valid <= '1';
            rx_rem   := rx_rem - 8;
        else
            -- Previous data consumed.
            rx_data  <= (others => '0');
            rx_last  <= '0';
            rx_valid <= '0';
        end if;

        -- Check the reply stream.
        if (tx_rem = 0) then
            assert (tx_valid = '0')
                report "Unexpected Tx-VALID." severity error;
        elsif (tx_valid = '1' and tx_ready = '1') then
            tx_ref := test_pkt_tx.all(tx_rem-1 downto tx_rem-8);
            tx_rem := tx_rem - 8;
            assert (tx_data = tx_ref)
                report "Tx-DATA mismatch." severity error;
            assert (tx_last = bool2bit(tx_rem = 0))
                report "Tx-LAST mismatch." severity error;
        end if;

        -- Flow-control randomization.
        tx_ready <= rand_bit(rate_tx);
    end if;
end process;

-- Unit under test.
rx_write <= rx_valid and rx_ready;
uut : entity work.cfgbus_host_eth
    generic map(
    CFG_ETYPE   => CFG_ETYPE,
    CFG_MACADDR => CFG_MACADDR,
    MIN_FRAME   => 0)       -- Padding disabled
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    rx_data     => rx_data,
    rx_last     => rx_last,
    rx_valid    => rx_valid,
    rx_ready    => rx_ready,
    tx_data     => tx_data,
    tx_last     => tx_last,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    txrx_clk    => clk_100,
    reset_p     => reset_p);

-- Attach ConfigBus to a single read-write register.
u_reg : cfgbus_register
    generic map(
    DEVADDR     => 123,
    REGADDR     => 456)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => reg_val);

-- Test control.
p_test : process
    subtype addr_word is std_logic_vector(31 downto 0);
    constant OPCODE_NOOP    : byte_t := x"00";
    constant OPCODE_WR_RPT  : byte_t := x"2F";
    constant OPCODE_WR_INC  : byte_t := x"3F";
    constant OPCODE_RD_RPT  : byte_t := x"40";
    constant OPCODE_RD_INC  : byte_t := x"50";
    constant OPCODE_ERROR   : byte_t := x"FF";
    constant RDSTATUS_OK    : byte_t := x"00";
    constant RDSTATUS_ERR   : byte_t := x"FF";
    constant ADDR_REG       : addr_word := i2s(123 * 1024 + 456, 32);
    constant ADDR_ZERO      : addr_word := (others => '0');
    constant DATA_NULL      : std_logic_vector(-1 downto 0) := (others => '0');
    constant DATA_ZERO      : cfgbus_word := (others => '0');

    -- Create a command packet using router test functions.
    impure function make_cmd(
        opcode  : byte_t;
        addr    : addr_word;
        wordct  : positive;
        wrval   : std_logic_vector)
        return std_logic_vector
    is
        constant len : positive := 64 + wrval'length;
        constant seq : byte_t := i2s(test_index mod 256, 8);
        constant cmd : std_logic_vector(len-1 downto 0)
            := opcode & i2s(wordct-1, 8) & seq & x"00" & addr & wrval;
    begin
        return cmd;
    end function;

    -- Create a reply packet using router test functions.
    impure function make_ack(
        opcode  : byte_t;
        addr    : addr_word;
        wordct  : positive;
        rdval   : std_logic_vector)
        return std_logic_vector
    is
        constant len : positive := 64 + rdval'length;
        constant seq : byte_t := i2s(test_index mod 256, 8);
        constant ack : std_logic_vector(len-1 downto 0)
            := opcode & i2s(wordct-1, 8) & seq & x"00" & addr & rdval;
    begin
        return ack;
    end function;

    -- Send command and set expected reply (if any).
    procedure send_recv(cmd, ack : std_logic_vector) is
    begin
        -- Trigger start of test.
        wait until rising_edge(clk_100);
        test_index  <= test_index + 1;
        test_start  <= '1';
        test_pkt_rx := make_eth_fcs(CFG_MACADDR, HOST_MACADDR, CFG_ETYPE, cmd);
        test_pkt_tx := make_eth_fcs(HOST_MACADDR, CFG_MACADDR, REPLY_ETYPE, ack); 
        wait until rising_edge(clk_100);
        test_start  <= '0';
        -- Wait until Tx/Rx process is done.
        wait until (tx_done = '1') and (rx_done = '1');
    end procedure;

    procedure check_reply_len(lbl : string; len : integer) is
    begin
        if (len = 0 and tx_count > 0) then
            report lbl & ": Unexpected reply." severity error;
        elsif (len > 0 and tx_count = 0) then
            report lbl & ": Missing reply." severity error;
        elsif (len /= tx_count) then
            report lbl & ": Reply-length mismatch." severity error;
        end if;
    end procedure;

    -- Run a sequence of tests under specified flow conditions.
    procedure test_seq(ri, ro : real) is
        variable reg : cfgbus_word := (others => '0');
    begin
        -- Set flow-control conditions.
        rate_rx <= ri;
        rate_tx <= ro;

        -- Send a no-op.
        send_recv(make_cmd(OPCODE_NOOP, ADDR_ZERO, 1, DATA_NULL),
                  make_ack(OPCODE_NOOP, ADDR_ZERO, 1, DATA_NULL));
        check_reply_len("No-op", 26);

        -- Send a few nominal commands.
        for n in 1 to 20 loop
            reg := rand_vec(32);
            send_recv(make_cmd(OPCODE_WR_RPT, ADDR_REG, 1, reg),
                      make_ack(OPCODE_WR_RPT, ADDR_REG, 1, DATA_NULL));
            assert (reg_val = reg)
                report "Register value mismatch." severity error;
            check_reply_len("Wr1", 26);
            send_recv(make_cmd(OPCODE_RD_RPT, ADDR_REG, 1, DATA_NULL),
                      make_ack(OPCODE_RD_RPT, ADDR_REG, 1, reg & RDSTATUS_OK));
            check_reply_len("Rd1", 31);
        end loop;

        -- Send a few multi-word commands.
        for n in 1 to 20 loop
            reg := rand_vec(32);
            send_recv(make_cmd(OPCODE_WR_RPT, ADDR_REG, 3, reg & reg & reg),
                      make_ack(OPCODE_WR_RPT, ADDR_REG, 3, DATA_NULL));
            assert (reg_val = reg)
                report "Register value mismatch." severity error;
            check_reply_len("Wr3", 26);
            send_recv(make_cmd(OPCODE_WR_INC, ADDR_REG, 2, reg & reg),
                      make_ack(OPCODE_WR_INC, ADDR_REG, 2, DATA_NULL));
            check_reply_len("Wr2", 26);
            assert (reg_val = reg)
                report "Register value mismatch." severity error;
            send_recv(make_cmd(OPCODE_RD_RPT, ADDR_REG, 3, DATA_NULL),
                      make_ack(OPCODE_RD_RPT, ADDR_REG, 3, reg & reg & reg & RDSTATUS_OK));
            check_reply_len("Rd3", 39);
            send_recv(make_cmd(OPCODE_RD_INC, ADDR_REG, 2, DATA_NULL),
                      make_ack(OPCODE_RD_INC, ADDR_REG, 2, reg & DATA_ZERO & RDSTATUS_ERR));
            check_reply_len("Rd2", 35);
        end loop;

        -- Try to read an invalid address (reply with error).
        send_recv(make_cmd(OPCODE_RD_RPT, ADDR_ZERO, 1, DATA_NULL),
                  make_ack(OPCODE_RD_RPT, ADDR_ZERO, 1, DATA_ZERO & RDSTATUS_ERR));
        check_reply_len("RdErr", 31);

        -- Try to send an invalid opcode (reply with error).
        send_recv(make_cmd(OPCODE_ERROR, ADDR_REG, 1, DATA_NULL),
                  make_ack(OPCODE_ERROR, ADDR_REG, 1, DATA_NULL));
        check_reply_len("BadOp", 26);

        -- Confirm the register hasn't been changed.
        assert (reg_val = reg)
            report "Register value mismatch." severity error;
    end;
begin
    wait until falling_edge(reset_p);
    wait for 1 us;

    -- Run the same test sequence under different flow-control conditions.
    test_seq(1.0, 1.0);
    test_seq(0.1, 0.9);
    test_seq(0.9, 0.1);

    report "All tests completed.";
    wait;
end process;

end tb;
