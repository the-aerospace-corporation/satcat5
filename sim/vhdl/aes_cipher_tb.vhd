--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This unit test takes less than 10 microseconds to complete.

library IEEE;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_1164.ALL;

entity aes_cipher_tb is
end aes_cipher_tb;

architecture aes_128_256_tb of aes_cipher_tb is

constant clk_period : time := 10 ns;

signal pt_rdy_256, pt_rdy_128     :  std_logic;
signal pt_val_256, pt_val_128     :  std_logic := '1';
signal pt_in_256,  pt_in_128      :  std_logic_vector(127 downto 0);
    -- key data
signal key_rdy_256, key_rdy_128   :  std_logic;
signal key_val_256, key_val_128   :  std_logic := '1';
signal key_in_256    :  std_logic_vector(255 downto 0);
signal key_in_128    :  std_logic_vector(127 downto 0);
    -- out data
signal ct_rdy_256, ct_rdy_128     :  std_logic;
signal ct_val_256, ct_val_128     :  std_logic;
signal ct_out_256, ct_out_128     :  std_logic_vector(127 downto 0);

signal start_test_1_256,start_test_2_256, test_started_256 : std_logic := '0';
signal error_256 : std_logic := '0';

signal start_test_1_128,start_test_2_128, test_started_128 : std_logic := '0';
signal error_128 : std_logic := '0';
--
signal reset : std_logic := '0';
signal clk   : std_logic := '0';
signal out_count_256 : natural := 0;
signal out_count_128 : natural := 0;

begin

aes_cipher_256_instance : entity work.aes_cipher
    generic map(256)
    port map (
    -- in data
    pt_data     => pt_in_256,
    pt_valid    => pt_val_256,
    pt_ready    => pt_rdy_256,
    -- key data
    key_data    => key_in_256,
    key_valid   => key_val_256,
    key_ready   => key_rdy_256,
    -- out data
    ct_data     => ct_out_256,
    ct_valid    => ct_val_256,
    ct_ready    => ct_rdy_256,
    --system
    reset_p     => reset,
    clk         => clk);

aes_cipher_128_instance : entity work.aes_cipher
    generic map(128)
    port map (
    -- in data
    pt_data     => pt_in_128,
    pt_valid    => pt_val_128,
    pt_ready    => pt_rdy_128,
    -- key data
    key_data    => key_in_128,
    key_valid   => key_val_128,
    key_ready   => key_rdy_128,
    -- out data
    ct_data     => ct_out_128,
    ct_valid    => ct_val_128,
    ct_ready    => ct_rdy_128,
    --system
    reset_p     => reset,
    clk         => clk);

clk <= not clk after clk_period/2;

test_256 : process(clk) is
begin
    if rising_edge(clk) then
        if start_test_1_256 = '1' and test_started_256 = '0' then
            test_started_256 <= '1';
            key_val_256 <= '1';
            pt_val_256 <= '1';
            ct_rdy_256 <= '1';
        elsif start_test_2_256 = '1' and test_started_256 = '0' then
            test_started_256 <= '1';
            pt_val_256 <= '1';
            ct_rdy_256 <= '1';
        end if;

        if key_rdy_256 = '1' and key_val_256 = '1' then
           key_val_256 <= '0';
        end if;
        if pt_rdy_256 = '1' and pt_val_256 = '1' and key_val_256 = '0' then
           pt_val_256 <= '0';
        end if;
        if ct_val_256 = '1' and ct_rdy_256 = '1' then
            out_count_256 <= out_count_256 + 1;
            ct_rdy_256 <= '0';
            test_started_256 <= '0';
        end if;
    end if;
end process;

update_inputs_256 : process is
begin
    -- Appendix C FIPS 197
    pt_in_256 <= x"00112233445566778899aabbccddeeff";
    key_in_256 <= x"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    start_test_1_256 <= '1';
    wait until rising_edge(test_started_256);
    start_test_1_256 <= '0';
    wait until falling_edge(test_started_256);
    if ct_out_256 /= x"8ea2b7ca516745bfeafc49904b496089" then
        error_256 <= '1';
    end if;

    -- Appendix F.1.5  NIST 800-38A
    -- https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38a.pdf
    pt_in_256 <= x"6bc1bee22e409f96e93d7e117393172a";
    key_in_256 <= x"603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4";
    start_test_1_256 <= '1';
    wait until rising_edge(test_started_256);
    start_test_1_256 <= '0';
    wait until falling_edge(test_started_256);
    if ct_out_256 /= x"f3eed1bdb5d2a03c064b5a7e3db181f8" then
        error_256 <= '1';
    end if;

    pt_in_256 <= x"ae2d8a571e03ac9c9eb76fac45af8e51";
    start_test_2_256 <= '1';
    wait until rising_edge(test_started_256);
    start_test_2_256 <= '0';
    wait until falling_edge(test_started_256);
    if ct_out_256 /= x"591ccb10d410ed26dc5ba74a31362870" then
        error_256 <= '1';
    end if;

    pt_in_256 <= x"30c81c46a35ce411e5fbc1191a0a52ef";
    start_test_2_256 <= '1';
    wait until rising_edge(test_started_256);
    start_test_2_256 <= '0';
    wait until falling_edge(test_started_256);
    if ct_out_256 /= x"b6ed21b99ca6f4f9f153e7b1beafed1d" then
        error_256 <= '1';
    end if;

    pt_in_256 <= x"f69f2445df4f9b17ad2b417be66c3710";
    start_test_2_256 <= '1';
    wait until rising_edge(test_started_256);
    start_test_2_256 <= '0';
    wait until falling_edge(test_started_256);
    if ct_out_256 /= x"23304b7a39f9f3ff067d8d8f9e24ecc7" then
        error_256 <= '1';
    end if;
    report "AES-256 ECB check done";
    if error_256 = '1' then
        report "AES-256 CT mismatch." severity error;
    end if;
    wait;
end process;

test_128 : process(clk) is
begin
    if rising_edge(clk) then
        if start_test_1_128 = '1' and test_started_128 = '0' then
            test_started_128 <= '1';
            key_val_128 <= '1';
            pt_val_128 <= '1';
            ct_rdy_128 <= '1';
        elsif start_test_2_128 = '1' and test_started_128 = '0' then
            test_started_128 <= '1';
            pt_val_128 <= '1';
            ct_rdy_128 <= '1';
        end if;

        if key_rdy_128 = '1' and key_val_128 = '1' then
           key_val_128 <= '0';
        end if;
        if pt_rdy_128 = '1' and pt_val_128= '1' and key_val_128 = '0' then
           pt_val_128 <= '0';
        end if;
        if ct_val_128 = '1' and ct_rdy_128 = '1' then
            out_count_128 <= out_count_128 + 1;
            ct_rdy_128 <= '0';
            test_started_128 <= '0';
        end if;
    end if;
end process;

update_inputs_128 : process is
begin
    -- Appendix C FIPS 197
    pt_in_128 <= x"00112233445566778899aabbccddeeff";
    key_in_128 <= x"000102030405060708090a0b0c0d0e0f";
    start_test_1_128 <= '1';
    wait until rising_edge(test_started_128);
    start_test_1_128 <= '0';
    wait until falling_edge(test_started_128);
    if ct_out_128 /= x"69c4e0d86a7b0430d8cdb78070b4c55a" then
        error_128 <= '1';
    end if;

    -- Appendix F.1.1  NIST 800-38A
    -- https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38a.pdf
    pt_in_128 <= x"6bc1bee22e409f96e93d7e117393172a";
    key_in_128 <= x"2b7e151628aed2a6abf7158809cf4f3c";
    start_test_1_128 <= '1';
    wait until rising_edge(test_started_128);
    start_test_1_128 <= '0';
    wait until falling_edge(test_started_128);
    if ct_out_128 /= x"3ad77bb40d7a3660a89ecaf32466ef97" then
        error_128 <= '1';
    end if;

    pt_in_128 <= x"ae2d8a571e03ac9c9eb76fac45af8e51";
    start_test_2_128 <= '1';
    wait until rising_edge(test_started_128);
    start_test_2_128 <= '0';
    wait until falling_edge(test_started_128);
    if ct_out_128 /= x"f5d3d58503b9699de785895a96fdbaaf" then
        error_128 <= '1';
    end if;

    pt_in_128 <= x"30c81c46a35ce411e5fbc1191a0a52ef";
    start_test_2_128 <= '1';
    wait until rising_edge(test_started_128);
    start_test_2_128 <= '0';
    wait until falling_edge(test_started_128);
    if ct_out_128 /= x"43b1cd7f598ece23881b00e3ed030688" then
        error_128 <= '1';
    end if;

    pt_in_128 <= x"f69f2445df4f9b17ad2b417be66c3710";
    start_test_2_128 <= '1';
    wait until rising_edge(test_started_128);
    start_test_2_128 <= '0';
    wait until falling_edge(test_started_128);
    if ct_out_128 /= x"7b0c785e27e8ad3f8223207104725dd4" then
        error_128 <= '1';
    end if;
    report "AES-128 ECB check done";
    if error_128 = '1' then
        report "AES-128 CT mismatch." severity error;
    end if;
    wait;
end process;

end aes_128_256_tb;
