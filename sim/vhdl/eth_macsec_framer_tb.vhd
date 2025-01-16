--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This unit test takes 510 microseconds to complete.

library IEEE;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_textio.all;
use STD.TEXTIO.ALL;

entity eth_macsec_framer_tb is
    generic (TEST_DATA_FOLDER : string := "../../sim/data");
end eth_macsec_framer_tb;

architecture tb of eth_macsec_framer_tb is

constant key_len    : integer := 256;

constant cfg_len    : integer := key_len + 96;

constant clk_period : time    := 10 ns;
constant data_width : integer := 8;
constant cfg_width  : integer := 8;

signal cfg  : std_logic_vector(cfg_len-1  downto 0);

-- config in
signal cfg_rdy      :  std_logic;
signal cfg_in_val       :   std_logic := '0';
signal cfg_in           :  std_logic_vector(cfg_width-1 downto 0);
-- frame in
signal data_in_rdy  :  std_logic;
signal data_in_val      :   std_logic := '0';
signal data_in_last     :   std_logic := '0'; -- EOF
signal data_in          :   std_logic_vector(data_width-1 downto 0);
-- frame out
signal data_out_rdy :   std_logic  := '0';
signal data_out_val     :  std_logic;
signal data_out_last    :  std_logic;
signal data_out         :  std_logic_vector(data_width-1 downto 0);
--system
signal reset_p          : std_logic := '0';
signal clk              : std_logic := '0';

signal input_cfg_s : std_logic := '1';
signal input_data_s  : std_logic := '0';
signal read_data_s  : std_logic := '0';

signal frame_number : integer range 0 to 100;
signal data_in_val_i : std_logic := '0';

signal first_test : std_logic := '1';
signal start_test  : std_logic := '0';
signal started_test : std_logic := '0';
signal test_done   : std_logic := '0';

begin

u_macsec_framer : entity work.eth_macsec_framer
    generic map(key_len, data_width, 8)
    port map(
    -- config in
    cfg_data    => cfg_in,
    cfg_valid   => cfg_in_val,
    cfg_ready   => cfg_rdy,
    -- frame in
    in_data     => data_in,
    in_last     => data_in_last,
    in_valid    => data_in_val,
    in_ready    => data_in_rdy,
    -- frame out
    out_data    => data_out,
    out_last    => data_out_last,
    out_valid   => data_out_val,
    out_ready   => data_out_rdy,
    --system
    reset_p     => reset_p,
    clk         => clk);

clk <= not clk after clk_period/2;
data_in_val <= data_in_val_i;

test : process(clk)
    variable idx : integer range 0 to 16383 := 0;
    variable cfg_bytes : integer range 0 to 2*cfg_len/8 := 0;
    variable in_bytes  : integer range 0 to 1520 := 0;
    variable out_bytes : integer range 0 to 1540 := 0;
    file     infile1,infile2  : text;
    variable my_line1,my_line2 : line;
    variable tmp_d_in, tmp_d_out : std_logic_vector(7 downto 0);
    variable tmp_len : integer;
begin
    if rising_edge(clk) then
        if start_test = '1' then
        -- on the first frame, set both key and IV before sending the frame
        -- after, only send frames
            if first_test = '1' then
                input_cfg_s <= '1';
                first_test <= '0';
                file_open(infile1, TEST_DATA_FOLDER & "/random_ethernet.txt", read_mode);
                file_open(infile2, TEST_DATA_FOLDER & "/random_macsec.txt", read_mode);
            else
                input_data_s <= '1';
                read_data_s <= '1';
            end if;
            if(not endfile(infile1) and not endfile(infile2)) then
                readline(infile1,my_line1);
                readline(infile2,my_line2);
                hread(my_line1,tmp_d_in);
                data_in <= tmp_d_in;
                data_in_val_i <= '1';
            else
                report "file IO error!!" severity error;
            end if;
            test_done <= '0';
            started_test <= '1';
        end if;
        -- INPUT CFG
        if input_cfg_s = '1' then
            if cfg_rdy = '1' and cfg_in_val = '1' then
                cfg_bytes := cfg_bytes + data_width/8;
            end if;
            if cfg_bytes = (cfg_len / 8) then
                cfg_in_val <= '0';
                input_cfg_s  <= '0';
                input_data_s  <= '1';
                read_data_s <= '1';
                cfg_bytes := 0;
            else
                idx := cfg_bytes*8;
                cfg_in <= cfg(cfg_len-1-idx downto cfg_len-idx-data_width);
                cfg_in_val <= '1';
            end if;
        end if;
        -- INPUT FRAME
        if input_data_s = '1' then
            if data_in_rdy = '1' and data_in_val_i = '1' then
                in_bytes := in_bytes + data_width/8;
                if my_line1'length > 1 then
                    hread(my_line1,tmp_d_in);
                    data_in_val_i <= '1';
                    data_in <= tmp_d_in;
                    if my_line1'length < 2 then
                        data_in_last <= '1';
                    end if;
                else
                    in_bytes := 0;
                    data_in_last <= '0';
                    data_in_val_i  <= '0';
                    input_data_s <= '0';
                end if;
            end if;
        end if;
        -- OUTPUT FRAME
        if read_data_s = '1' then
            data_out_rdy <= '1';
            if data_out_val = '1' and data_out_rdy = '1' then
                out_bytes := out_bytes + data_width/8;
                hread(my_line2,tmp_d_out);
                assert (tmp_d_out = data_out) report "data mismatch in " & integer'image(frame_number) severity error;
                if data_out_last = '1' then
                    assert (my_line2'length < 2) report "length mismatch: frame " & integer'image(frame_number) severity error;
                    data_out_rdy <= '0';
                    read_data_s <= '0';
                    out_bytes := 0;
                    test_done <= '1';
                    started_test <= '0';
                end if;
            end if;
        end if;
    end if;
end process;

test_control : process
begin
    -- first frame, set key, IV, starting packet number
    cfg  <= x"feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308cafebabefacedbaddecaf888";
    for i in 0 to 49 loop
        start_test <= '1';
        wait until rising_edge(started_test);
        start_test <= '0';
        wait until rising_edge(test_done);
        frame_number <= frame_number + 1;
    end loop;
    report "All tests complete!";
    wait;
end process;

end tb;