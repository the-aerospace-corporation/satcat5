--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the IPv4 router's mailmap interface
--
-- This is a unit test for the "mailmap" port, which provides a ConfigBus
-- interface for diverting selected packets and, processing them in software.
-- This allows complex but low-rate tasks, such as ARP queries, to be
-- offloaded from FPGA fabric to software for significant resource savings.
--
-- The complete test takes just over 900 microseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.router2_common.all;

entity router2_mailmap_tb_helper is
    generic (
    BIG_ENDIAN  : boolean;          -- Byte order of ConfigBus host
    IO_BYTES    : positive;         -- I/O width in bytes
    PORT_COUNT  : positive;         -- Number of router ports
    VLAN_ENABLE : boolean;          -- Enable VLAN tag handling?
    IBUF_KBYTES : positive := 2;    -- Input buffer size in kilobytes
    OBUF_KBYTES : positive := 2);   -- Output buffer size in kilobytes
end router2_mailmap_tb_helper;

architecture helper of router2_mailmap_tb_helper is

-- ConfigBus parameters.
constant DEVADDR    : integer := 42;

-- Clock and reset generation.
signal pre_clk      : std_logic := '0';
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference stream.
constant LOAD_BYTES : positive := 4;
signal fifo_din     : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_vtag    : vlan_hdr_t := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal fifo_keep    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;
signal ref_ready    : std_logic;
signal ref_keep     : std_logic_vector(PORT_COUNT-1 downto 0);

-- Unit under test.
signal rx_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal rx_vtag      : vlan_hdr_t := (others => '0');
signal rx_nlast     : integer range 0 to IO_BYTES := 0;
signal rx_write     : std_logic := '0';
signal rx_commit    : std_logic := '0';
signal tx_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal tx_nlast     : integer range 0 to IO_BYTES;
signal tx_valid     : std_logic;
signal tx_ready     : std_logic := '0';
signal tx_keep      : std_logic_vector(PORT_COUNT-1 downto 0);

-- High-level test control
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;

begin

-- Clock and reset generation
-- (Taking care to avoid simulation artifacts from single-tick delays.)
pre_clk <= not pre_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
clk_100         <= pre_clk;         -- Matched delay
cfg_cmd.clk     <= pre_clk;         -- Matched delay
cfg_cmd.reset_p <= reset_p;

-- Input and reference FIFOs.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => VLAN_HDR_WIDTH)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_din,
    in_meta         => fifo_vtag,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk_100,
    out_data        => rx_data,
    out_meta        => rx_vtag,
    out_nlast       => rx_nlast,
    out_valid       => rx_write,
    out_ready       => '1',
    out_rate        => test_rate_i,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => PORT_COUNT)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_din,
    in_meta         => fifo_keep,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk_100,
    out_data        => ref_data,
    out_meta        => ref_keep,
    out_nlast       => ref_nlast,
    out_valid       => ref_valid,
    out_ready       => ref_ready,
    out_rate        => test_rate_o,
    reset_p         => reset_p);

-- Unit under test.
rx_commit <= rx_write and bool2bit(rx_nlast > 0);

uut : entity work.router2_mailmap
    generic map(
    DEVADDR     => DEVADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    VLAN_ENABLE => VLAN_ENABLE,
    IBUF_KBYTES => IBUF_KBYTES,
    OBUF_KBYTES => OBUF_KBYTES,
    BIG_ENDIAN  => BIG_ENDIAN)
    port map(
    rx_clk      => clk_100,
    rx_data     => rx_data,
    rx_nlast    => rx_nlast,
    rx_psrc     => 0,           -- Not tested
    rx_vtag     => rx_vtag,
    rx_write    => rx_write,
    rx_commit   => rx_commit,
    rx_revert   => '0',         -- Not tested
    tx_clk      => clk_100,
    tx_data     => tx_data,
    tx_nlast    => tx_nlast,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    tx_keep     => tx_keep,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Check the output stream.
ref_ready   <= tx_valid;
tx_ready    <= ref_valid;

p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (tx_valid = '1' and tx_ready = '1') then
            assert (tx_data = ref_data)
                report "DATA mismatch" severity error;
            assert (tx_nlast = ref_nlast)
                report "NLAST mismatch" severity error;
            assert (tx_keep = ref_keep)
                report "KEEP mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Simultaneously load the designated packet data into the input FIFO,
    -- the reference FIFO, and the ConfigBus transmit interface.
    procedure load_ref(pkt: std_logic_vector) is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
    begin
        assert (LOAD_BYTES = 4) severity error;
        wait until rising_edge(clk_100);
        cfg_cmd.regaddr <= RT_ADDR_TXRX_DAT;
        cfg_cmd.wrcmd   <= '1';
        fifo_write      <= '1';
        while (rdpos < nbytes) loop
            if (rdpos + LOAD_BYTES >= nbytes) then
                fifo_nlast <= nbytes - rdpos;
            else
                fifo_nlast <= 0;
            end if;
            for n in 0 to LOAD_BYTES-1 loop
                tmp := strm_byte_zpad(rdpos, pkt);
                fifo_din(31-8*n downto 24-8*n) <= tmp;
                if (BIG_ENDIAN) then
                    cfg_cmd.wdata(31-8*n downto 24-8*n) <= tmp;
                else
                    cfg_cmd.wdata(8*n+7 downto 8*n) <= tmp;
                end if;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk_100);
            cfg_cmd.regaddr <= cfg_cmd.regaddr + 1;
        end loop;
        cfg_cmd.wrcmd <= '0';
        fifo_write <= '0';
        wait until rising_edge(clk_100);
    end procedure;

    -- Compare reference packet to the ConfigBus memory-map data.
    procedure read_mem(pkt: std_logic_vector) is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
        variable ref    : cfgbus_word := (others => '0');
    begin
        assert (LOAD_BYTES = 4) severity error;
        -- First, read back the packet length.
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.regaddr <= RT_ADDR_RX_CTRL;
        cfg_cmd.rdcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        wait for 1 ns;
        assert (cfg_ack.rdack = '1' and cfg_ack.rderr = '0')
            report "Missing reply." severity error;
        assert (cfg_ack.rdata = i2s(nbytes, 32))
            report "Length mismatch." severity error;
        -- Start reading packet contents.
        cfg_cmd.regaddr <= RT_ADDR_TXRX_DAT;
        while (rdpos < nbytes) loop
            for n in 0 to LOAD_BYTES-1 loop
                tmp := strm_byte_zpad(rdpos, pkt);
                if (BIG_ENDIAN) then
                    ref(31-8*n downto 24-8*n) := tmp;
                else
                    ref(8*n+7 downto 8*n) := tmp;
                end if;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(cfg_cmd.clk);
            wait for 1 ns;
            cfg_cmd.regaddr <= cfg_cmd.regaddr + 1;
            assert (cfg_ack.rdack = '1' and cfg_ack.rderr = '0')
                report "Missing reply." severity error;
            assert (cfg_ack.rdata = ref)
                report "Read mismatch." severity error;
        end loop;
        -- Read completed, reset interrupt and flush receive buffer.
        cfg_cmd.rdcmd <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_RX_IRQ, x"00000001");
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_RX_CTRL, x"00000001");
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd <= '0';
    end procedure;

    -- Wait for all transmissions to finish.
    -- (i.e., N consecutive cycles without a data transfer.)
    procedure wait_done is
        variable count : integer := 0;
    begin
        wait for 1 us;
        while (count < 20) loop
            if ((rx_write = '1') or (ref_valid = '1' and ref_ready = '1') or (cfg_ack.irq = '0')) then
                count := 0;
            else
                count := count + 1;
            end if;
            wait until rising_edge(clk_100);
        end loop;
    end procedure;

    -- Run a complete test with a single randomly-generated packet.
    procedure run_pkt(len: positive) is
        variable pkt : std_logic_vector(8*len-1 downto 0) := rand_bytes(len);
    begin
        -- Update test counter and randomize packet metadata.
        test_index <= test_index + 1;
        fifo_keep  <= rand_vec(PORT_COUNT);
        fifo_vtag  <= rand_vec(VLAN_HDR_WIDTH);
        -- Load and transmit the frame.
        load_ref(pkt);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_TX_MASK, resize(fifo_keep, 32));
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_TX_CTRL, i2s(len, 32));
        -- Wait for the transmission to finish, then confirm memory contents.
        -- (Stream output is already checked against the reference FIFO.)
        wait_done;
        if (VLAN_ENABLE) then
            -- If VLAN is enabled, then buffer should include the VLAN tag.
            read_mem(insert_vtag_pkt(pkt, fifo_vtag).all);
        else
            -- Otherwise, receive buffer should match the original packet.
            read_mem(pkt);
        end if;
    end procedure;

    -- Run a series of randomly generated packets.
    -- (Minimum Ethernet header = 14 bytes, append 0-63 bytes of random data.)
    procedure run_series(ri, ro: real) is
    begin
        test_rate_i <= ri;
        test_rate_o <= ro;
        for n in 1 to 100 loop
            run_pkt(14 + rand_int(64));
        end loop;
    end procedure;
begin
    -- Take control of ConfigBus signals (except clock and reset).
    cfg_cmd.clk     <= 'Z';
    cfg_cmd.sysaddr <= 0;
    cfg_cmd.devaddr <= DEVADDR;
    cfg_cmd.regaddr <= 0;
    cfg_cmd.wdata   <= (others => '0');
    cfg_cmd.wstrb   <= (others => '1');
    cfg_cmd.wrcmd   <= '0';
    cfg_cmd.rdcmd   <= '0';
    cfg_cmd.reset_p <= 'Z';

    -- Wait for reset to complete, then configure interrupt controller.
    wait for 2 us;
    cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_RX_IRQ, x"00000001");

    -- Run tests under various flow-control conditions.
    run_series(1.0, 1.0);
    run_series(0.1, 0.9);
    run_series(0.9, 0.1);
    report "All tests completed!";
    wait;
end process;

end helper;

---------------------------------------------------------------------

entity router2_mailmap_tb is
    -- Unit testbench top level, no I/O ports
end router2_mailmap_tb;

architecture tb of router2_mailmap_tb is
begin

uut0 : entity work.router2_mailmap_tb_helper
    generic map(
    BIG_ENDIAN  => false,
    IO_BYTES    => 1,
    PORT_COUNT  => 4,
    VLAN_ENABLE => false);

uut1 : entity work.router2_mailmap_tb_helper
    generic map(
    BIG_ENDIAN  => true,
    IO_BYTES    => 2,
    PORT_COUNT  => 4,
    VLAN_ENABLE => true);

end tb;
