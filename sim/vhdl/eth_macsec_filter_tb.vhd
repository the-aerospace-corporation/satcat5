--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This unit test takes ~121 microseconds to complete.

library IEEE;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_textio.all;
use STD.TEXTIO.ALL;

entity eth_macsec_filter_tb is
end eth_macsec_filter_tb;

architecture tb of eth_macsec_filter_tb is
    constant MAX_FRAME_SIZE_BYTES : integer := 1500;
    type frame_size_type is array (0 to 15) of integer;
    signal frame_size : frame_size_type := (1,1500,1500,897,123,980,1499,5,2,100,100,100,100,100,100,100);
    signal frame_number : integer range 0 to 15 := 0;

    constant clk_period : time    := 10 ns;
    constant data_width : integer := 8;

    -- frame in
    signal in_ready : std_logic;
    signal in_valid : std_logic := '0';
    signal in_last  : std_logic := '0'; -- EOF
    signal in_data  : std_logic_vector(data_width-1 downto 0);
    -- frame out
    signal out_ready : std_logic  := '0';
    signal out_valid : std_logic;
    signal out_last  : std_logic;
    signal out_sof   : std_logic;
    signal out_data  : std_logic_vector(data_width-1 downto 0);
    --
    signal out_len  : unsigned(10 downto 0);
    signal out_err  : std_logic;
    --system
    signal reset_p  : std_logic := '0';
    signal clk      : std_logic := '0';

    signal input_data_s  : std_logic := '0';
    signal read_data_s  : std_logic := '0';

    signal in_val_i : std_logic := '0';

    signal first_test : std_logic := '1';
    signal start_test  : std_logic := '0';
    signal started_test : std_logic := '0';
    signal test_done   : std_logic := '0';

    signal test_error : std_logic := '0';

begin
    filter_instance : entity work.eth_macsec_filter
        generic map (
            DATA_WIDTH_BYTES      => 1,
            MAX_FRAME_SIZE_BYTES  => 1500,
            MAX_FRAME_DEPTH       => 3)
        port map (
            -- frame in (AXI-stream)
            in_ready    => in_ready,
            in_valid    => in_valid,
            in_last     => in_last,
            in_data     => in_data,
            -- frame out (AXI-stream)
            out_ready   => out_ready,
            out_valid   => out_valid,
            out_first   => out_sof,
            out_last    => out_last,
            out_data    => out_data,
            -- additional frame out meta-data
            out_frame_length => out_len,
            out_auth_fail    => out_err,
            --system
            reset_p          => reset_p,
            clk              => clk);

    clk <= not clk after clk_period/2;
    in_valid <= in_val_i;

    test : process(clk, frame_number)
        variable idx : integer range 0 to 16383 := 0;
        variable in_bytes  : integer range 0 to 1600 := 0;
        variable out_bytes : integer range 0 to 1600 := 0;
        variable tmp_d_in, tmp_d_out : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if start_test = '1' then
                test_done    <= '0';
                started_test <= '1';
                input_data_s <= '1';
                in_data      <=  (others => '0');
                in_val_i     <= '1';
                out_bytes    := 0;
                in_bytes     := 0;
            end if;
            -- INPUT FRAME
            if input_data_s = '1' then
                if in_ready = '1' and in_val_i = '1' then
                    in_bytes := in_bytes + 1;
                    if in_bytes = frame_size(frame_number) then
                        -- frames 3,4,6 fail authentication
                        if frame_number = 3 or frame_number = 4 or frame_number = 6 then
                            in_data <= (others => '0');
                        else
                            in_data <= (others => '1');
                        end if;
                        in_last  <= '1';
                    elsif in_bytes = frame_size(frame_number) + 1 then
                        in_last      <= '0';
                        in_val_i     <= '0';
                        input_data_s <= '0';
                        read_data_s  <= '1';
                    else
                        in_data  <=  std_logic_vector(to_unsigned((frame_size(frame_number) * in_bytes),8));
                    end if;
                end if;
            end if;
            -- OUTPUT FRAME
            if read_data_s = '1' then
                out_ready <= '1';
                if out_sof = '1' then
                    -- check reported length
                    assert (frame_size(frame_number) = to_integer(out_len))
                        report "incorrectly reported length in " & integer'image(frame_number)
                        severity error;
                elsif out_err = '1' then
                    assert (frame_number = 3 or frame_number = 4 or frame_number = 6)
                        report "unexpected unauthenticated frame " & integer'image(frame_number)
                        severity error;
                    out_ready <= '0';
                    read_data_s <= '0';
                    test_done <= '1';
                    started_test <= '0';
                elsif out_valid = '1' and out_ready = '1' then
                    tmp_d_out := std_logic_vector(to_unsigned((frame_size(frame_number) * out_bytes),8));
                    assert (tmp_d_out = out_data)
                        report "data mismatch in " & integer'image(frame_number)
                        severity error;
                    out_bytes := out_bytes + data_width/8;
                    if out_last = '1' then
                        out_ready <= '0';
                        read_data_s <= '0';
                        test_done <= '1';
                        started_test <= '0';
                        --
                        assert (frame_size(frame_number) = out_bytes)
                            report "received length mismatch in " & integer'image(frame_number)
                            severity error;
                        -- we intentionally corrupted frame 3,4,6
                        -- so we should not have received these frames
                        assert (frame_number /= 3) report "frame 3 should not have passed authentication!" severity error;
                        assert (frame_number /= 4) report "frame 4 should not have passed authentication!" severity error;
                        assert (frame_number /= 6) report "frame 6 should not have passed authentication!" severity error;
                    end if;
                end if;
            end if;
        end if;
    end process;

    test_control : process
    begin
        for i in 0 to 15 loop
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            start_test <= '1';
            wait until rising_edge(started_test);
            start_test <= '0';
            wait until rising_edge(test_done);
            frame_number <= frame_number +1;
        end loop;
        report "All tests complete!";
        wait;
    end process;
end tb;
