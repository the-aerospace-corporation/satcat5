--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ethernet 8b/10b encoder and decoder
--
-- This testbench connects the Ethernet 8b/10b encoder back-to-back with
-- the corresponding decoder.  The test sequence is:
--    1. Update variable bit-delay setting.
--    2. Wait for unlock (if applicable)
--    3. Wait for lock
--    4. Confirm configuration data received
--    5. Send and confirm several packets of random data
--    6. Repeat from step 1
--
-- A full test takes less than 2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.all;

entity eth_all8b10b_tb is
    -- Unit testbench top level, no I/O ports
end eth_all8b10b_tb;

architecture tb of eth_all8b10b_tb is

-- Clock and reset generation
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference and input streams.
signal ref_data     : std_logic_vector(7 downto 0) := (others => '0');
signal ref_last     : std_logic := '0';
signal in_data      : std_logic_vector(7 downto 0) := (others => '0');
signal in_dv        : std_logic := '0';
signal in_cken      : std_logic := '0';

-- Encoder output stream and bit-shifting.
signal enc_data     : std_logic_vector(9 downto 0);
signal enc_cken     : std_logic;
signal shft_data    : std_logic_vector(9 downto 0) := (others => '0');
signal shft_cken    : std_logic := '0';

-- Decoder output stream.
signal dec_lock     : std_logic;
signal dec_cken     : std_logic;
signal dec_dv       : std_logic;
signal dec_err      : std_logic;
signal dec_data     : std_logic_vector(7 downto 0);

-- Final output stream.
signal out_port     : port_rx_m2s;

-- Configuration Tx/Rx
signal cfg_txen     : std_logic := '0';
signal cfg_rcvd     : std_logic;
signal cfg_txdata   : std_logic_vector(15 downto 0) := (others => '0');
signal cfg_rxdata   : std_logic_vector(15 downto 0);

-- Overall test control
signal test_idx     : integer := 0;
signal test_shift   : integer range 0 to 9 := 0;
signal test_rate    : real := 0.0;
signal test_txen    : std_logic := '0';
signal comma_pcount : integer := 0;
signal comma_ncount : integer := 0;

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Reference and input stream generation.
p_src : process(clk_125)
    constant AMBLE_LEN  : integer := 8;
    constant IDLE_LEN   : integer := 10;
    constant PKT_MIN    : integer := 64;
    constant PKT_MAX    : integer := 1000;
    variable iseed1     : positive := 5535797;  -- Matching seeds for input, ref
    variable iseed2     : positive := 88051460;
    variable rseed1     : positive := 5535797;  -- Matching seeds for input, ref
    variable rseed2     : positive := 88051460;
    variable fseed1     : positive := 44025087;
    variable fseed2     : positive := 36130034;
    variable rand       : real := 0.0;
    variable ilen, icount : integer := 0;
    variable rlen, rcount : integer := 0;
begin
    if rising_edge(clk_125) then
        -- Input stream, with flow-control randomization:
        uniform(fseed1, fseed2, rand);
        if (rand < test_rate) then
            in_cken <= '1';
            if (icount = 0) then
                -- Once enabled, start new packet.
                if (test_txen = '1') then
                    icount := icount + 1;
                end if;
            elsif (icount < AMBLE_LEN) then
                -- Packet preamble.
                in_data <= x"55";
                in_dv   <= '1';
                icount  := icount + 1;
            elsif (icount = AMBLE_LEN) then
                -- Start-of-packet delimiter + decide packet length.
                uniform(iseed1, iseed2, rand);
                ilen := PKT_MIN + integer(floor(real(PKT_MAX-PKT_MIN) * rand));
                in_data <= x"D5";
                in_dv   <= '1';
                icount  := icount + 1;
            elsif (icount <= AMBLE_LEN + ilen) then
                -- Generate each byte of packet.
                uniform(iseed1, iseed2, rand);
                in_data <= i2s(integer(floor(rand*256.0)), 8);
                in_dv   <= '1';
                icount  := icount + 1;
            elsif (icount < AMBLE_LEN + ilen + IDLE_LEN) then
                -- Idle period after each packet.
                in_data <= (others => '0');
                in_dv   <= '0';
                icount  := icount + 1;
            else
                -- Get ready to start next packet.
                in_data <= (others => '0');
                in_dv   <= '0';
                icount  := 0;
                ilen    := 0;
            end if;
        else
            in_cken <= '0';
        end if;

        -- Reference stream generation.
        if (rcount = 0) then
            -- Start of new packet.
            uniform(rseed1, rseed2, rand);
            rlen := PKT_MIN + integer(floor(real(PKT_MAX-PKT_MIN) * rand));
            rcount := 1;
            uniform(rseed1, rseed2, rand);
            ref_data <= i2s(integer(floor(rand*256.0)), 8);
        elsif (out_port.write = '1' and ref_last = '1') then
            -- End of packet, revert to idle.
            rcount := 0;
            rlen   := 0;
            ref_data <= (others => '0');
            ref_last <= '0';
        elsif (out_port.write = '1') then
            -- Generate next byte and update counter.
            uniform(rseed1, rseed2, rand);
            rcount := rcount + 1;
            ref_data <= i2s(integer(floor(rand*256.0)), 8);
            ref_last <= bool2bit(rcount = rlen);
        end if;
    end if;
end process;

-- Unit under test: Encoder
uut_enc : entity work.eth_enc8b10b
    port map(
    in_data     => in_data,
    in_dv       => in_dv,
    in_err      => '0', -- Not tested
    in_cken     => in_cken,
    cfg_xmit    => cfg_txen,
    cfg_word    => cfg_txdata,
    out_data    => enc_data,
    out_cken    => enc_cken,
    io_clk      => clk_125,
    reset_p     => reset_p);

-- Bit shifting (to test token alignment).
p_shft : process(clk_125)
    variable sreg : std_logic_vector(18 downto 0) := (others => '0');
begin
    if rising_edge(clk_125) then
        if (enc_cken = '1') then
            sreg := sreg(8 downto 0) & enc_data; -- MSB first
        end if;
        shft_data <= sreg(9+test_shift downto test_shift);
        shft_cken <= enc_cken;
    end if;
end process;

-- Unit under test: Decoder
uut_dec : entity work.eth_dec8b10b
    port map(
    io_clk      => clk_125,
    in_lock     => '1', -- Not tested
    in_cken     => shft_cken,
    in_data     => shft_data,
    out_lock    => dec_lock,
    out_cken    => dec_cken,
    out_dv      => dec_dv,
    out_err     => dec_err,
    out_data    => dec_data,
    cfg_rcvd    => cfg_rcvd,
    cfg_word    => cfg_rxdata);

-- Preamble removal.
u_amble : entity work.eth_preamble_rx
    port map(
    raw_clk     => clk_125,
    raw_lock    => dec_lock,
    raw_cken    => dec_cken,
    raw_data    => dec_data,
    raw_dv      => dec_dv,
    raw_err     => dec_err,
    rate_word   => get_rate_word(1000),
    status      => (others => '0'),
    rx_data     => out_port);

-- Reference data checking and raw stream inspection.
p_check : process(clk_125)
    function count_bits(x : std_logic_vector) return integer is
        variable count : integer := 0;
    begin
        for n in x'range loop
            if (x(n) = '1') then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

    variable wd, rd     : integer := 0;
    variable rxerr_d    : std_logic := '0';
    variable wtemp      : std_logic_vector(5 downto 0) := (others => '0');
begin
    if rising_edge(clk_125) then
        -- Inspect encoded token stream.
        if (enc_cken = '1') then
            -- Measure running disparity (0's vs. 1's)
            wd := count_bits(enc_data) - 5; -- Disparity this word
            rd := rd + wd;                  -- Total running disparity
            assert (abs(wd) <= 1)
                report "Excess word disparity: " & integer'image(wd)
                severity error;
            assert (abs(rd) <= 1)
                report "Excess running disparity: " & integer'image(rd)
                severity error;
            -- Count occurrence of comma+ and comma-.
            wtemp := enc_data(9 downto 4); -- abcdeif
            if (test_txen = '0') then
                comma_pcount <= 0;
                comma_ncount <= 0;
            elsif (wtemp = "001111") then
                comma_pcount <= comma_pcount + 1;
            elsif (wtemp = "110000") then
                comma_ncount <= comma_ncount + 1;
            end if;
        end if;

        -- Compare final output to reference.
        if (out_port.write = '1') then
            assert (out_port.data = ref_data)
                report "Data mismatch" severity error;
            assert (out_port.last = ref_last)
                report "Last mismatch" severity error;
        end if;

        -- Watch for rising-edge of the error signal.
        if (out_port.rxerr = '1' and rxerr_d = '0') then
            assert (test_txen = '0')
                report "Unexpected error strobe" severity error;
        end if;
        rxerr_d := out_port.rxerr;
    end if;
end process;

-- Overall test control.
p_test : process
    procedure run_test(shft, npkt : integer; rate : real) is
        variable rempkt, timeout : integer := 0;
    begin
        -- Set test conditions.
        report "Starting test #" & integer'image(test_idx + 1);
        test_idx    <= test_idx + 1;
        test_shift  <= shft;
        test_rate   <= rate;
        test_txen   <= '0';
        cfg_txen    <= '1';
        cfg_txdata  <= i2s(123 * (test_idx + 1), 16);
        wait until rising_edge(clk_125);

        -- Wait for decoder unlock.
        timeout     := integer(round(10000.0 / rate));
        while (dec_lock = '1' and timeout > 0) loop
            wait until rising_edge(clk_125);
            timeout := timeout - 1;
        end loop;
        assert (dec_lock = '0')
            report "Decoder still locked after shift." severity error;
        wait until rising_edge(clk_125);
        wait until rising_edge(clk_125);

        -- Wait for decoder lock.
        timeout     := integer(round(10000.0 / rate));
        while (cfg_rcvd = '0' and timeout > 0) loop
            wait until rising_edge(clk_125);
            timeout := timeout - 1;
        end loop;
        assert (dec_lock = '1')
            report "Decoder not locked." severity error;
        if (cfg_rcvd = '1') then
            assert (cfg_rxdata = cfg_txdata)
                report "Configuration mismatch." severity error;
        else
            report "Missing configuration word." severity error;
        end if;

        -- Switch to data mode and transmit a few packets.
        timeout     := integer(round(2.0 * real(npkt * 1000) / rate));
        rempkt      := npkt;
        cfg_txen    <= '0';
        test_txen   <= '1';
        while (timeout > 0 and rempkt > 0) loop
            wait until rising_edge(clk_125);
            timeout := timeout - 1;
            if (out_port.write = '1' and ref_last = '1') then
                rempkt := rempkt - 1;
            end if;
        end loop;
        assert (rempkt = 0)
            report "Timeout waiting for packet data." severity error;
        report "Received packets: " & integer'image(npkt-rempkt) & " of " & integer'image(npkt);

        -- Sanity check: Should have received more comma+ than comma-.
        assert (2*comma_pcount > 3*comma_ncount)
            report "Expected majority Comma+: " & integer'image(comma_pcount)
                & " vs. " & integer'image(comma_ncount)
            severity error;

        -- Disable transmission and wait for data to flush.
        test_txen   <= '0';
        wait for 10 us;
    end procedure;
begin
    wait until (reset_p = '0');
    wait for 1 us;

    run_test(0, 10, 1.0);
    run_test(1, 20, 1.0);
    run_test(2, 20, 0.5);
    run_test(3, 40, 0.7);
    run_test(4, 40, 0.9);
    run_test(5, 40, 0.9);
    run_test(6, 40, 0.9);
    run_test(7, 40, 0.9);
    run_test(8, 40, 0.9);
    run_test(9, 40, 0.9);
    report "All tests completed!";
    wait;
end process;

end tb;
