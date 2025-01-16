--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This unit test takes less than 20 microseconds to complete, and should
-- be run in several configurations (see xsim_run.sh).

library IEEE;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_1164.ALL;

entity aes_gcm_tb is
    generic (
    KEY_LEN       : integer := 256; -- 256 or 128
    IS_ENCRYPT    : boolean := true; -- true = encrypt, false = decrypt
    DATA_WIDTH    : integer := 8);
end aes_gcm_tb;

architecture tb of aes_gcm_tb is

constant clk_period : time    := 10 ns;

signal key  : std_logic_vector(KEY_LEN-1  downto 0) := (others => '0');
signal iv   : std_logic_vector(95   downto 0) := (others => '0');
signal aad  : std_logic_vector(559 downto 0) := (others => '0');
signal test_in  : std_logic_vector(511 downto 0);
signal test_out : std_logic_vector(511 downto 0);
signal tag  : std_logic_vector(127  downto 0);
signal aad_len : integer range 0 to 560;
signal txt_len : integer range 0 to 512;
signal test_out_exp : std_logic_vector(511 downto 0);
signal tag_exp  : std_logic_vector(127 downto 0);

-- key/iv in
signal req_key      : std_logic;
signal req_iv       : std_logic;
signal key_iv_in_val    : std_logic_vector(1 downto 0) := "00";
signal key_iv_in        : std_logic_vector(DATA_WIDTH-1 downto 0);
-- aad/txt in
signal req_aad      : std_logic;
signal req_txt_in   : std_logic;
signal aad_txt_in_val   : std_logic_vector(1 downto 0) := "00";
signal aad_txt_in_last  : std_logic;
signal aad_txt_in       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
-- txt out
signal req_txt_out  : std_logic := '0';
signal txt_out_val      : std_logic;
signal txt_out_last     : std_logic;
signal txt_out          : std_logic_vector(DATA_WIDTH-1 downto 0);
-- tag out
signal req_tag_out  : std_logic := '0';
signal tag_out_val      : std_logic;
signal tag_out          : std_logic_vector(DATA_WIDTH-1 downto 0);
--system
signal reset_p          : std_logic := '0';
signal clk              : std_logic := '0';

signal input_key_s : std_logic := '1';
signal input_iv_s  : std_logic := '0';
signal input_aad_s : std_logic := '0';
signal input_txt_s : std_logic := '0';
signal read_txt_s  : std_logic := '0';
signal read_tag_s  : std_logic := '0';

signal start_test  : std_logic := '0';
signal started_test : std_logic := '0';
signal test_done   : std_logic := '0';

signal test_error : std_logic := '0';

begin

gcm_instance : entity work.aes_gcm
    generic map(KEY_LEN, IS_ENCRYPT, DATA_WIDTH,DATA_WIDTH)
    port map(
    -- key/iv in
    key_iv_in   => key_iv_in,
    key_iv_val  => key_iv_in_val,
    key_rdy     => req_key,
    iv_rdy      => req_iv,
    -- aad/txt in
    aad_txt_in  => aad_txt_in,
    aad_txt_last=> aad_txt_in_last,
    aad_txt_val => aad_txt_in_val,
    aad_rdy     => req_aad,
    txt_in_rdy  => req_txt_in,
    -- txt out
    txt_data    => txt_out,
    txt_last    => txt_out_last,
    txt_valid   => txt_out_val,
    txt_ready   => req_txt_out,
    -- tag out
    tag_data    => tag_out,
    tag_valid   => tag_out_val,
    tag_ready   => req_tag_out,
    --system
    reset_p     => reset_p,
    clk         => clk);

clk <= not clk after clk_period/2;

test : process(clk)
    variable idx : integer range 0 to 2047;
    variable key_cnt : integer range 0 to 127 := 0;
    variable iv_cnt  : integer range 0 to 127 := 0;
    variable aad_cnt : integer range 0 to 127 := 0;
    variable txt_cnt : integer range 0 to 127 := 0;
    variable tag_cnt : integer range 0 to 127 := 0;
begin
    if rising_edge(clk) then
        if start_test = '1' then
            input_key_s     <= '1';
            test_done       <= '0';
            started_test    <= '1';
            key_iv_in       <= (others => '0');
            test_out        <= (others => '0');
            tag             <= (others => '0');
            aad_txt_in_val  <= "00";
            aad_txt_in_last <= '0';
        end if;
        -- INPUT KEY
        if input_key_s = '1' then
            if req_key = '1' and key_iv_in_val = "01" then
                key_cnt := key_cnt + 1;
            end if;
            if key_cnt = (KEY_LEN / DATA_WIDTH) then
                key_iv_in_val <= "00";
                input_key_s <= '0';
                input_iv_s  <= '1';
                key_cnt := 0;
            else
                idx := DATA_WIDTH*key_cnt;
                key_iv_in <= key(KEY_LEN-1-idx downto KEY_LEN-idx-DATA_WIDTH);
                key_iv_in_val <= "01";
            end if;
        end if;
        -- INPUT IV
        if input_iv_s = '1' then
            if req_iv = '1' and key_iv_in_val = "10"  then
                iv_cnt := iv_cnt + 1;
            end if;
            if iv_cnt = (96 / DATA_WIDTH) then
                iv_cnt := 0;
                key_iv_in_val <= "00";
                input_iv_s <= '0';
                -- if there's no AAD, skip straight to PT
                if aad_len > 0 then
                    input_aad_s <= '1';
                else
                    input_txt_s <= '1';
                    read_txt_s  <= '1';
                end if;
            else
                idx := DATA_WIDTH*iv_cnt;
                key_iv_in <= iv(95-idx downto 96-idx-DATA_WIDTH);
                key_iv_in_val <= "10";
            end if;
        end if;
        -- INPUT AAD
        if input_aad_s = '1' then
            if req_aad = '1' and aad_txt_in_val(0) = '1' then
                aad_cnt := aad_cnt + 1;
            end if;
            if aad_cnt = (aad_len / DATA_WIDTH) then
                aad_cnt := 0;
                aad_txt_in_last <= '0';
                aad_txt_in_val  <= "00";
                input_aad_s <= '0';
                -- if there's no PT, skip straight to getting the tag
                if txt_len > 0 then
                    input_txt_s <= '1';
                    read_txt_s  <= '1';
                else
                    read_tag_s <= '1';
                end if;
            else
                idx := DATA_WIDTH*aad_cnt;
                aad_txt_in <= aad(aad_len-idx-1 downto aad_len-idx-DATA_WIDTH);
                -- if there's no PT, use the AUTH_ONLY val
                if txt_len = 0 then
                    aad_txt_in_val <= "11";
                else
                    aad_txt_in_val <= "01";
                end if;
                if aad_cnt = (aad_len / DATA_WIDTH) -1 then
                    aad_txt_in_last <= '1';
                end if;
            end if;
        end if;
        -- INPUT TXT
        if input_txt_s = '1' then
            if req_txt_in = '1' and aad_txt_in_val = "10" then
                txt_cnt := txt_cnt + 1;
            end if;
            if txt_cnt = txt_len/DATA_WIDTH then
                txt_cnt := 0;
                aad_txt_in_val <= "00";
                aad_txt_in_last <= '0';
                input_txt_s <= '0';
            else
                idx := DATA_WIDTH*txt_cnt;
                aad_txt_in <= test_in(txt_len-idx-1 downto txt_len-idx-DATA_WIDTH);
                aad_txt_in_val <= "10";
                if txt_cnt = (txt_len/DATA_WIDTH) -1 then
                    aad_txt_in_last <= '1';
                end if;
            end if;
        end if;
        -- OUTPUT TXT
        if read_txt_s = '1' then
            req_txt_out <= '1';
            if txt_out_val = '1' and req_txt_out = '1' then
                test_out(txt_len-1 downto 0) <= test_out(txt_len-DATA_WIDTH-1 downto 0) & txt_out;
                if txt_out_last = '1' then
                    req_txt_out <= '0';
                    read_txt_s <= '0';
                    read_tag_s <= '1';
                end if;
            end if;
        end if;
        -- OUTPUT TAG AND RESET
        if read_tag_s = '1' then
            req_tag_out <= '1';
            if tag_cnt = (128 / DATA_WIDTH) then
                req_tag_out <= '0';
                read_tag_s <= '0';
                tag_cnt := 0;
                test_done <= '1';
                started_test <= '0';
            elsif tag_out_val = '1' and req_tag_out = '1' then
                tag <= tag(127-DATA_WIDTH downto 0) & tag_out;
                tag_cnt := tag_cnt + 1;
            end if;
        end if;
    end if;
end process;

test_control : process
    variable pl : integer range 0 to 512;
    variable al : integer range 0 to 560;
begin
    -- test cases 2 and 14
    pl := 128;
    al := 0;
    txt_len <= pl;
    aad_len <= al;
    key  <= (others => '0');
    iv <= (others => '0');
    aad(559 downto al)<= (others => '0');
    if IS_ENCRYPT then
        test_in(pl-1 downto 0) <= (others => '0');
        test_in(511 downto pl)<= (others => '0');
        if KEY_LEN = 128 then
            test_out_exp(pl-1 downto 0) <= x"0388dace60b6a392f328c2b971b2fe78";
            test_out_exp(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"ab6e47d42cec13bdf53a67b21257bddf";
        else
            test_out_exp(pl-1 downto 0) <= x"cea7403d4d606b6e074ec5d3baf39d18";
            test_out_exp(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"d0d1c8a799996bf0265b98b5d48ab919";
        end if;
    else
        test_out_exp(pl-1 downto 0) <= (others => '0');
        test_out_exp(511 downto pl)<= (others => '0');
        if KEY_LEN = 128 then
            test_in(pl-1 downto 0) <= x"0388dace60b6a392f328c2b971b2fe78";
            test_in(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"ab6e47d42cec13bdf53a67b21257bddf";
        else
            test_in(pl-1 downto 0) <= x"cea7403d4d606b6e074ec5d3baf39d18";
            test_in(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"d0d1c8a799996bf0265b98b5d48ab919";
        end if;
    end if;
    start_test <= '1';
    wait until rising_edge(started_test);
    start_test <= '0';
    wait until rising_edge(test_done);
    for i in 0 to 511 loop
        if test_out_exp(i) /= test_out(i) then
            test_error <= '1';
            report "Text mismatch in test case 2/14" severity error;
            exit;
        end if;
    end loop;
    for i in 0 to 127 loop
        if tag_exp(i) /= tag(i) then
            test_error <= '1';
            report "Tag mismatch in test case 2/14" severity error;
            exit;
        end if;
    end loop;
    wait for 20 ns;

    -- test cases 3 and 15
    pl := 512;
    al := 0;
    txt_len <= pl;
    aad_len <= al;
    aad(559 downto al)<= (others => '0');
    iv <= x"cafebabefacedbaddecaf888";
    if IS_ENCRYPT then
        test_in(pl-1 downto 0) <= x"d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255";
        if KEY_LEN = 128 then
            key  <= x"feffe9928665731c6d6a8f9467308308";
            test_out_exp(511 downto 0) <= x"42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985";
            tag_exp(127 downto 0) <= x"4d5c2af327cd64a62cf35abd2ba6fab4";
        else
            key  <= x"feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";
            test_out_exp(511 downto 0) <= x"522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad";
            tag_exp(127 downto 0) <= x"b094dac5d93471bdec1a502270e3cc6c";
        end if;
    else
        test_out_exp(pl-1 downto 0) <= x"d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255";
        if KEY_LEN = 128 then
            key  <= x"feffe9928665731c6d6a8f9467308308";
            test_in(511 downto 0) <= x"42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985";
            tag_exp(127 downto 0) <= x"4d5c2af327cd64a62cf35abd2ba6fab4";
        else
            key  <= x"feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";
            test_in(511 downto 0) <= x"522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad";
            tag_exp(127 downto 0) <= x"b094dac5d93471bdec1a502270e3cc6c";
        end if;
    end if;
    start_test <= '1';
     wait until rising_edge(started_test);
    start_test <= '0';
    wait until rising_edge(test_done);
    for i in 0 to 511 loop
        if test_out_exp(i) /= test_out(i) then
            test_error <= '1';
            report "Text mismatch in test case 3/15" severity error;
            exit;
        end if;
    end loop;
    for i in 0 to 127 loop
        if tag_exp(i) /= tag(i) then
            test_error <= '1';
            report "Tag mismatch in test case 3/15" severity error;
            exit;
        end if;
    end loop;
    wait for 20 ns;

    -- test cases 4 and 16
    pl := 480;
    al := 160;
    txt_len <= pl;
    aad_len <= al;
    iv <= x"cafebabefacedbaddecaf888";
    aad(al-1 downto 0) <= x"feedfacedeadbeeffeedfacedeadbeefabaddad2";
    aad(559 downto al)<= (others => '0');
    if IS_ENCRYPT then
        test_in(pl-1 downto 0) <= x"d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39";
        test_in(511 downto pl)<= (others => '0');
        if KEY_LEN = 128 then
            key  <= x"feffe9928665731c6d6a8f9467308308";
            test_out_exp(pl-1 downto 0) <= x"42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091";
            test_out_exp(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"5bc94fbc3221a5db94fae95ae7121a47";
        else
            key  <= x"feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";
            test_out_exp(pl-1 downto 0) <= x"522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662";
            test_out_exp(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"76fc6ece0f4e1768cddf8853bb2d551b";
        end if;
    else
        test_out_exp(pl-1 downto 0) <= x"d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39";
        test_out_exp(511 downto pl)<= (others => '0');
        if KEY_LEN = 128 then
            key  <= x"feffe9928665731c6d6a8f9467308308";
            test_in(pl-1 downto 0) <= x"42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091";
            test_in(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"5bc94fbc3221a5db94fae95ae7121a47";
        else
            key  <= x"feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";
            test_in(pl-1 downto 0) <= x"522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662";
            test_in(511 downto pl) <= (others => '0');
            tag_exp(127 downto 0) <= x"76fc6ece0f4e1768cddf8853bb2d551b";
        end if;
    end if;
    start_test <= '1';
     wait until rising_edge(started_test);
    start_test <= '0';
    wait until rising_edge(test_done);
    for i in 0 to 511 loop
        if test_out_exp(i) /= test_out(i) then
            test_error <= '1';
            report "Text mismatch in test case 4/16" severity error;
            exit;
        end if;
    end loop;
    for i in 0 to 127 loop
        if tag_exp(i) /= tag(i) then
            test_error <= '1';
            report "Tag mismatch in test case 4/16" severity error;
            exit;
        end if;
    end loop;
    wait for 20 ns;
    -- must be 1,2,4,8 or 16 due to length of test vectors
    if DATA_WIDTH /= 32 then
        -- authentication only test
        if KEY_LEN = 128 then
            key  <= x"AD7A2BD03EAC835A6F620FDCB506B345";
            tag_exp(127 downto 0) <= x"F09478A9B09007D06F46E9B6A1DA25DD";
        else
            key  <= x"E3C08A8F06C6E3AD95A70557B23F75483CE33021A9C72B7025666204C69C0B72";
            tag_exp(127 downto 0) <= x"2F0BC5AF409E06D609EA8B7D0FA5EA50";
        end if;
        iv <= x"12153524C0895E81B2C28465";
        pl := 0;
        al := 560;
        txt_len <= pl;
        aad_len <= al;
        test_in(511 downto pl)<= (others => '0');
        aad(al-1 downto 0) <= x"D609B1F056637A0D46DF998D88E5222AB2C2846512153524C0895E8108000F101112131415161718191A1B1C1D1E1F202122232425262728292A2B2C2D2E2F30313233340001";
        start_test <= '1';
         wait until rising_edge(started_test);
        start_test <= '0';
        wait until rising_edge(test_done);
        for i in 0 to 127 loop
            if tag_exp(i) /= tag(i) then
                test_error <= '1';
                report "Tag mismatch in authentication only test case" severity error;
                exit;
            end if;
        end loop;
    end if;
    report "All tests complete!";
    wait;
end process;

end tb;