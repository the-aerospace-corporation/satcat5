--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the IPv4 router offload block
--
-- This is a unit test for the "offload" block, which applies forward
-- vs. offload decisions made by the upstream gateway, and provides
-- a memory-mapped interface (router2_mailmap) for the CPU to receive
-- and transmit offloaded packets.
--
-- The complete test takes less than 900 microseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.router2_common.all;
use     work.switch_types.all;

entity router2_offload_tb_helper is
    generic (
    IO_BYTES    : positive;         -- I/O width in bytes
    PORT_COUNT  : positive);        -- Number of router ports
end router2_offload_tb_helper;

architecture helper of router2_offload_tb_helper is

-- ConfigBus parameters.
constant DEVADDR    : integer := 42;

-- Clock and reset generation.
signal pre_clk      : std_logic := '0';
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference stream.
constant LOAD_BYTES : positive := 4;
signal fifo_din     : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_dout    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_wr_in   : std_logic := '0';
signal fifo_wr_ref  : std_logic := '0';
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_pdst     : std_logic_vector(PORT_COUNT-1 downto 0);
signal ref_empty    : std_logic;

-- Unit under test.
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_pdst      : std_logic_vector(PORT_COUNT downto 0);
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal in_empty     : std_logic;
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic;
signal out_pdst     : std_logic_vector(PORT_COUNT-1 downto 0);

-- High-level test control
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;
signal test_mode    : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;
signal test_dstmac  : mac_addr_t := (others => '0');
signal test_srcmac  : mac_addr_t := (others => '0');
signal test_pdst    : std_logic_vector(PORT_COUNT downto 0) := (others => '0');
signal test_regaddr : cfgbus_regaddr := 0;
signal test_wdata   : cfgbus_word := (others => '0');
signal test_wrcmd   : std_logic := '0';
signal test_rdcmd   : std_logic := '0';

begin

-- Clock and reset generation
-- (Taking care to avoid simulation artifacts from single-tick delays.)
pre_clk <= not pre_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
clk_100         <= pre_clk;         -- Matched delay
cfg_cmd.clk     <= pre_clk;         -- Matched delay

-- Drive all other ConfigBus signals.
-- Due to a bug in Vivado 2019.1, we cannot use "cfgbus_sim_tools"
-- for register addresses larger than 255, which are required here.
-- Workaround is to assign individual signals at the top level only.
cfg_cmd.sysaddr <= 0;
cfg_cmd.devaddr <= DEVADDR;
cfg_cmd.regaddr <= test_regaddr;
cfg_cmd.wdata   <= test_wdata;
cfg_cmd.wstrb   <= (others => test_wrcmd);
cfg_cmd.wrcmd   <= test_wrcmd;
cfg_cmd.rdcmd   <= test_rdcmd;
cfg_cmd.reset_p <= reset_p;

-- Input and reference FIFOs.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => PORT_COUNT + 1)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_din,
    in_meta         => test_pdst,
    in_nlast        => fifo_nlast,
    in_write        => fifo_wr_in,
    out_clk         => clk_100,
    out_data        => in_data,
    out_meta        => in_pdst,
    out_nlast       => in_nlast,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_empty       => in_empty,
    out_rate        => test_rate_i,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => PORT_COUNT)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_dout,
    in_meta         => test_pdst(PORT_COUNT-1 downto 0),
    in_nlast        => fifo_nlast,
    in_write        => fifo_wr_ref,
    out_clk         => clk_100,
    out_data        => ref_data,
    out_meta        => ref_pdst,
    out_nlast       => ref_nlast,
    out_valid       => out_ready,
    out_ready       => out_valid,
    out_empty       => ref_empty,
    out_rate        => test_rate_o,
    reset_p         => reset_p);

-- Unit under test.
uut : entity work.router2_offload
    generic map(
    DEVADDR     => DEVADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    VLAN_ENABLE => false,
    BIG_ENDIAN  => true)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    in_dstmac   => test_dstmac,
    in_srcmac   => test_srcmac,
    in_pdst     => in_pdst,
    in_psrc     => 0,                   -- Not tested
    in_meta     => SWITCH_META_NULL,    -- Not tested
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    out_pdst    => out_pdst,
    out_meta    => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the output stream.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_valid = '1' and out_ready = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch" severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch" severity error;
            assert (out_pdst = ref_pdst)
                report "PDST mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Test if a given packet is IPv4.
    function is_ipv4(pkt: std_logic_vector) return boolean is
        variable etype : mac_type_t := pkt(pkt'left-95 downto pkt'left-110);
    begin
        return (etype = ETYPE_IPV4);
    end function;

    -- Write to a single ConfigBus register.
    -- (Cannot use "cfgbus_sim_tools" due to compatibility workaround.)
    procedure cfgbus_write(reg: cfgbus_regaddr; dat: cfgbus_word) is
    begin
        wait until rising_edge(cfg_cmd.clk);
        test_regaddr <= reg;
        test_wdata   <= dat;
        test_wrcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        test_wrcmd   <= '0';
        assert (cfg_cmd.regaddr = reg) severity failure;
    end procedure;

    -- Simultaneously load the designated packet data into the designated
    -- input and output FIFOs, making any required changes to header fields.
    procedure load_input(pkt: std_logic_vector) is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
    begin
        assert (LOAD_BYTES = 4) severity error;
        wait until rising_edge(clk_100);
        fifo_wr_in  <= '1';
        fifo_wr_ref <= or_reduce(test_pdst(PORT_COUNT-1 downto 0));
        while (rdpos < nbytes) loop
            if (rdpos + LOAD_BYTES >= nbytes) then
                fifo_nlast <= nbytes - rdpos;
            else
                fifo_nlast <= 0;
            end if;
            for n in 0 to LOAD_BYTES-1 loop
                -- Set the primary input.
                tmp := strm_byte_zpad(rdpos, pkt);
                fifo_din(31-8*n downto 24-8*n) <= tmp;
                -- Set the expected output.
                if (rdpos < ETH_HDR_DSTMAC + 6) then
                    tmp := strm_byte_value(rdpos, test_dstmac);
                elsif (rdpos < ETH_HDR_SRCMAC + 6) then
                    tmp := strm_byte_value(rdpos-ETH_HDR_SRCMAC, test_srcmac);
                elsif (rdpos = IP_HDR_TTL and is_ipv4(pkt)) then
                    tmp := std_logic_vector(unsigned(tmp) - 1);
                end if;
                fifo_dout(31-8*n downto 24-8*n) <= tmp;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk_100);
        end loop;
        fifo_wr_in  <= '0';
        fifo_wr_ref <= '0';
    end procedure;

    procedure load_offload(pkt: std_logic_vector) is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
    begin
        assert (LOAD_BYTES = 4) severity error;
        wait until rising_edge(clk_100);
        test_regaddr  <= RT_ADDR_TXRX_DAT;
        test_wrcmd    <= '1';
        fifo_wr_ref   <= '1';
        while (rdpos < nbytes) loop
            if (rdpos + LOAD_BYTES >= nbytes) then
                fifo_nlast <= nbytes - rdpos;
            else
                fifo_nlast <= 0;
            end if;
            for n in 0 to LOAD_BYTES-1 loop
                tmp := strm_byte_zpad(rdpos, pkt);
                fifo_dout(31-8*n downto 24-8*n) <= tmp;
                test_wdata(31-8*n downto 24-8*n) <= tmp;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk_100);
            test_regaddr <= test_regaddr + 1;
        end loop;
        test_wrcmd  <= '0';
        fifo_wr_ref <= '0';
        wait until rising_edge(clk_100);
        cfgbus_write(RT_ADDR_TX_MASK, resize(test_pdst, 32));
        cfgbus_write(RT_ADDR_TX_CTRL, i2s(nbytes, 32));
    end procedure;

    -- Compare reference packet to the offload receive buffer.
    procedure read_offload(pkt: std_logic_vector) is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
        variable ref    : cfgbus_word := (others => '0');
    begin
        assert (LOAD_BYTES = 4) severity error;
        -- First, read back the packet length.
        wait until rising_edge(cfg_cmd.clk);
        test_regaddr <= RT_ADDR_RX_CTRL;
        test_rdcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        wait for 1 ns;
        assert (cfg_ack.rdack = '1' and cfg_ack.rderr = '0')
            report "Missing reply." severity error;
        assert (cfg_ack.rdata = i2s(nbytes, 32))
            report "Length mismatch." severity error;
        -- Start reading packet contents.
        test_regaddr <= RT_ADDR_TXRX_DAT;
        while (rdpos < nbytes) loop
            for n in 0 to LOAD_BYTES-1 loop
                tmp := strm_byte_zpad(rdpos, pkt);
                ref(31-8*n downto 24-8*n) := tmp;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(cfg_cmd.clk);
            wait for 1 ns;
            test_regaddr <= test_regaddr + 1;
            assert (cfg_ack.rdack = '1' and cfg_ack.rderr = '0')
                report "Missing reply." severity error;
            assert (cfg_ack.rdata = ref)
                report "Read mismatch." severity error;
        end loop;
        -- Read completed, reset interrupt and flush receive buffer.
        test_rdcmd <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfgbus_write(RT_ADDR_RX_IRQ, x"00000001");
        cfgbus_write(RT_ADDR_RX_CTRL, x"00000001");
    end procedure;

    -- Wait for all transmissions to finish.
    -- (i.e., N consecutive cycles without an expected data transfer.)
    procedure wait_done is
        variable count_done, count_idle : integer := 0;
    begin
        wait for 1 us;
        while (count_done < 100) loop
            assert (count_idle < 10000)
                report "Test timeout." severity failure;
            if (in_empty = '1' and ref_empty = '1') then
                count_done := count_done + 1;
                count_idle := 0;
            elsif (in_valid = '1' and in_ready = '1') then
                count_done := 0;
                count_idle := 0;
            else
                count_done := 0;
                count_idle := count_idle + 1;
            end if;
            wait until rising_edge(clk_100);
        end loop;
    end procedure;

    -- Run a complete test with a single randomly-generated packet.
    procedure run_pkt(len, mode: natural) is
        variable pkt  : std_logic_vector(8*len-1 downto 0) := rand_bytes(len);
        variable pdst : std_logic_vector(PORT_COUNT-1 downto 0) := rand_vec(PORT_COUNT);
    begin
        -- Update test counter and randomize packet metadata.
        test_index  <= test_index + 1;
        test_mode   <= mode;
        test_dstmac <= rand_vec(48);
        test_srcmac <= rand_vec(48);
        -- Run a test with the selected input and output mode:
        case mode is
            when 0 =>   -- Input to primary output.
                test_pdst <= '0' & pdst;
                load_input(pkt);
                wait_done;
            when 1 =>   -- Input to offload port.
                test_pdst <= i2s(2**PORT_COUNT, test_pdst'length);
                load_input(pkt);
                wait_done;
                read_offload(pkt);
            when 2 =>   -- Input to both outputs.
                test_pdst <= '1' & pdst;
                load_input(pkt);
                wait_done;
                read_offload(pkt);
            when 3 =>   -- Offload to primary output.
                test_pdst <= '0' & pdst;
                load_offload(pkt);
                wait_done;
            when others =>
                report "Unsupported mode." severity failure;
        end case;
    end procedure;

    -- Run a series of randomly generated packets.
    -- (Minimum Ethernet header = 14 bytes, append 0-63 bytes of random data.)
    procedure run_series(ri, ro: real) is
    begin
        test_rate_i <= ri;
        test_rate_o <= ro;
        for n in 1 to 100 loop
            run_pkt(14 + rand_int(64), rand_int(4));
        end loop;
    end procedure;
begin
    -- Take control of ConfigBus signals (except clock and reset).
    test_regaddr    <= 0;
    test_wdata      <= (others => '0');
    test_wrcmd      <= '0';
    test_rdcmd      <= '0';

    -- Wait for reset to complete, then configure interrupt controller.
    wait for 2 us;
    cfgbus_write(RT_ADDR_RX_IRQ, x"00000001");

    -- Run tests under various flow-control conditions.
    run_series(1.0, 1.0);
    run_series(0.1, 0.9);
    run_series(0.9, 0.1);
    report "All tests completed!";
    wait;
end process;

end helper;

---------------------------------------------------------------------

entity router2_offload_tb is
    -- Unit testbench top level, no I/O ports
end router2_offload_tb;

architecture tb of router2_offload_tb is
begin

uut0 : entity work.router2_offload_tb_helper
    generic map(
    IO_BYTES    => 1,
    PORT_COUNT  => 4);

uut1 : entity work.router2_offload_tb_helper
    generic map(
    IO_BYTES    => 2,
    PORT_COUNT  => 4);

end tb;
