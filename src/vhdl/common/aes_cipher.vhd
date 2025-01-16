--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------

-- performs the AES cipher computation outlined in FIPS 197.
-- all I/O uses simplified AXI handshake: both valid and rdy must be set for the data to be used.
-- on reset
--   pt_ready = '0' and key_ready = '1'
-- to use:
-- 1) the key must be loaded on key_data with key_valid = '1'
--    once the key is loaded, key_ready will fall and and the round keys are pre-computed.
--     this takes approximately 'num_rounds' clock cycles after loading the key,
--     where num_rounds = (KEY_WIDTH / 32) + 6.
-- 2) once the key is loaded,
--      pt_ready = '0' and key_ready = '1'
--    and one of two things can happen
--     2.1) key_valid='0' and pt_valid='1'  and a 128-bit PT state is loaded on pt_data.
--    the PT then undergoes the AES cipher calculation. once the CT is computed,
--    it is loaded on ct_data and 'ct_valid' is set.
--    once the CT has been read (ct_ready=ct_valid='1'), we return to step 2.
--      2.2) key_valid='1' we return to step 1.
-- throughput is roughly (128 bits / num_rounds) per clock cycle,
-- where num_rounds = (KEY_WIDTH / 32) + 6

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.common_functions.bool2bit;

entity aes_cipher is
    generic(
    -- 128 or 256 only! 192 isn't implemented (not part of MACsec)
    KEY_WIDTH   : natural := 256);
    port(
    -- in data (AXI-stream, PT = plaintext)
    pt_data     : in  std_logic_vector(127 downto 0);
    pt_valid    : in  std_logic;
    pt_ready    : out std_logic := '0';
    -- key data (AXI-stream)
    key_data    : in  std_logic_vector(KEY_WIDTH-1 downto 0);
    key_valid   : in  std_logic;
    key_ready   : out std_logic := '1';
    -- out data (AXI-stream, CT = cyphertext)
    ct_data     : out std_logic_vector(127 downto 0);
    ct_valid    : out std_logic := '0';
    ct_ready    : in  std_logic;
    --system
    reset_p     : in  std_logic;
    clk         : in  std_logic);
end aes_cipher;

architecture aes of aes_cipher is

-- 10 or 14 AES rounds for 128-bit and 256-bit keys, respectively
constant NR               : integer := (KEY_WIDTH/32+6);
-- the AES cipher performs NR rounds of computation,
-- but a computation takes NR+1 clock cycles including a cycle for loading the input
signal round              : integer range 0 to NR := 0;
signal key_round          : integer range 0 to NR := 0;
-- signals for the round key (pre)calculation
signal rnd_key_rdy        : std_logic := '0';
signal rnd_keys           : std_logic_vector(128*(NR+1)-1 downto 0) := (others => '0');
signal rcon               : std_logic_vector(7 downto 0) := x"01";
signal krnd_do_rcon       : boolean := false;
-- signals for the AES round calculation
signal rnd_out            : std_logic_vector(127 downto 0) := (others => '0');

function calc_sbox(data_in : std_logic_vector; num_bytes : integer)
    return std_logic_vector is
    variable data_out : std_logic_vector(num_bytes*8-1 downto 0);
    variable tmp_i    : std_logic_vector(7 downto 0);
    variable tmp_o    : std_logic_vector(7 downto 0);
begin
    -- for each byte in the input, use a LUT to compute SBOX
    for i in 1 to num_bytes loop
        tmp_i := data_in((8*i-1) downto 8*(i-1));
        case tmp_i is
            when x"00" => tmp_o := x"63";   when x"40" => tmp_o := x"09";   when x"80" => tmp_o := x"cd";   when x"c0" => tmp_o := x"ba";
            when x"01" => tmp_o := x"7c";   when x"41" => tmp_o := x"83";   when x"81" => tmp_o := x"0c";   when x"c1" => tmp_o := x"78";
            when x"02" => tmp_o := x"77";   when x"42" => tmp_o := x"2c";   when x"82" => tmp_o := x"13";   when x"c2" => tmp_o := x"25";
            when x"03" => tmp_o := x"7b";   when x"43" => tmp_o := x"1a";   when x"83" => tmp_o := x"ec";   when x"c3" => tmp_o := x"2e";
            when x"04" => tmp_o := x"f2";   when x"44" => tmp_o := x"1b";   when x"84" => tmp_o := x"5f";   when x"c4" => tmp_o := x"1c";
            when x"05" => tmp_o := x"6b";   when x"45" => tmp_o := x"6e";   when x"85" => tmp_o := x"97";   when x"c5" => tmp_o := x"a6";
            when x"06" => tmp_o := x"6f";   when x"46" => tmp_o := x"5a";   when x"86" => tmp_o := x"44";   when x"c6" => tmp_o := x"b4";
            when x"07" => tmp_o := x"c5";   when x"47" => tmp_o := x"a0";   when x"87" => tmp_o := x"17";   when x"c7" => tmp_o := x"c6";
            when x"08" => tmp_o := x"30";   when x"48" => tmp_o := x"52";   when x"88" => tmp_o := x"c4";   when x"c8" => tmp_o := x"e8";
            when x"09" => tmp_o := x"01";   when x"49" => tmp_o := x"3b";   when x"89" => tmp_o := x"a7";   when x"c9" => tmp_o := x"dd";
            when x"0a" => tmp_o := x"67";   when x"4a" => tmp_o := x"d6";   when x"8a" => tmp_o := x"7e";   when x"ca" => tmp_o := x"74";
            when x"0b" => tmp_o := x"2b";   when x"4b" => tmp_o := x"b3";   when x"8b" => tmp_o := x"3d";   when x"cb" => tmp_o := x"1f";
            when x"0c" => tmp_o := x"fe";   when x"4c" => tmp_o := x"29";   when x"8c" => tmp_o := x"64";   when x"cc" => tmp_o := x"4b";
            when x"0d" => tmp_o := x"d7";   when x"4d" => tmp_o := x"e3";   when x"8d" => tmp_o := x"5d";   when x"cd" => tmp_o := x"bd";
            when x"0e" => tmp_o := x"ab";   when x"4e" => tmp_o := x"2f";   when x"8e" => tmp_o := x"19";   when x"ce" => tmp_o := x"8b";
            when x"0f" => tmp_o := x"76";   when x"4f" => tmp_o := x"84";   when x"8f" => tmp_o := x"73";   when x"cf" => tmp_o := x"8a";
            when x"10" => tmp_o := x"ca";   when x"50" => tmp_o := x"53";   when x"90" => tmp_o := x"60";   when x"d0" => tmp_o := x"70";
            when x"11" => tmp_o := x"82";   when x"51" => tmp_o := x"d1";   when x"91" => tmp_o := x"81";   when x"d1" => tmp_o := x"3e";
            when x"12" => tmp_o := x"c9";   when x"52" => tmp_o := x"00";   when x"92" => tmp_o := x"4f";   when x"d2" => tmp_o := x"b5";
            when x"13" => tmp_o := x"7d";   when x"53" => tmp_o := x"ed";   when x"93" => tmp_o := x"dc";   when x"d3" => tmp_o := x"66";
            when x"14" => tmp_o := x"fa";   when x"54" => tmp_o := x"20";   when x"94" => tmp_o := x"22";   when x"d4" => tmp_o := x"48";
            when x"15" => tmp_o := x"59";   when x"55" => tmp_o := x"fc";   when x"95" => tmp_o := x"2a";   when x"d5" => tmp_o := x"03";
            when x"16" => tmp_o := x"47";   when x"56" => tmp_o := x"b1";   when x"96" => tmp_o := x"90";   when x"d6" => tmp_o := x"f6";
            when x"17" => tmp_o := x"f0";   when x"57" => tmp_o := x"5b";   when x"97" => tmp_o := x"88";   when x"d7" => tmp_o := x"0e";
            when x"18" => tmp_o := x"ad";   when x"58" => tmp_o := x"6a";   when x"98" => tmp_o := x"46";   when x"d8" => tmp_o := x"61";
            when x"19" => tmp_o := x"d4";   when x"59" => tmp_o := x"cb";   when x"99" => tmp_o := x"ee";   when x"d9" => tmp_o := x"35";
            when x"1a" => tmp_o := x"a2";   when x"5a" => tmp_o := x"be";   when x"9a" => tmp_o := x"b8";   when x"da" => tmp_o := x"57";
            when x"1b" => tmp_o := x"af";   when x"5b" => tmp_o := x"39";   when x"9b" => tmp_o := x"14";   when x"db" => tmp_o := x"b9";
            when x"1c" => tmp_o := x"9c";   when x"5c" => tmp_o := x"4a";   when x"9c" => tmp_o := x"de";   when x"dc" => tmp_o := x"86";
            when x"1d" => tmp_o := x"a4";   when x"5d" => tmp_o := x"4c";   when x"9d" => tmp_o := x"5e";   when x"dd" => tmp_o := x"c1";
            when x"1e" => tmp_o := x"72";   when x"5e" => tmp_o := x"58";   when x"9e" => tmp_o := x"0b";   when x"de" => tmp_o := x"1d";
            when x"1f" => tmp_o := x"c0";   when x"5f" => tmp_o := x"cf";   when x"9f" => tmp_o := x"db";   when x"df" => tmp_o := x"9e";
            when x"20" => tmp_o := x"b7";   when x"60" => tmp_o := x"d0";   when x"a0" => tmp_o := x"e0";   when x"e0" => tmp_o := x"e1";
            when x"21" => tmp_o := x"fd";   when x"61" => tmp_o := x"ef";   when x"a1" => tmp_o := x"32";   when x"e1" => tmp_o := x"f8";
            when x"22" => tmp_o := x"93";   when x"62" => tmp_o := x"aa";   when x"a2" => tmp_o := x"3a";   when x"e2" => tmp_o := x"98";
            when x"23" => tmp_o := x"26";   when x"63" => tmp_o := x"fb";   when x"a3" => tmp_o := x"0a";   when x"e3" => tmp_o := x"11";
            when x"24" => tmp_o := x"36";   when x"64" => tmp_o := x"43";   when x"a4" => tmp_o := x"49";   when x"e4" => tmp_o := x"69";
            when x"25" => tmp_o := x"3f";   when x"65" => tmp_o := x"4d";   when x"a5" => tmp_o := x"06";   when x"e5" => tmp_o := x"d9";
            when x"26" => tmp_o := x"f7";   when x"66" => tmp_o := x"33";   when x"a6" => tmp_o := x"24";   when x"e6" => tmp_o := x"8e";
            when x"27" => tmp_o := x"cc";   when x"67" => tmp_o := x"85";   when x"a7" => tmp_o := x"5c";   when x"e7" => tmp_o := x"94";
            when x"28" => tmp_o := x"34";   when x"68" => tmp_o := x"45";   when x"a8" => tmp_o := x"c2";   when x"e8" => tmp_o := x"9b";
            when x"29" => tmp_o := x"a5";   when x"69" => tmp_o := x"f9";   when x"a9" => tmp_o := x"d3";   when x"e9" => tmp_o := x"1e";
            when x"2a" => tmp_o := x"e5";   when x"6a" => tmp_o := x"02";   when x"aa" => tmp_o := x"ac";   when x"ea" => tmp_o := x"87";
            when x"2b" => tmp_o := x"f1";   when x"6b" => tmp_o := x"7f";   when x"ab" => tmp_o := x"62";   when x"eb" => tmp_o := x"e9";
            when x"2c" => tmp_o := x"71";   when x"6c" => tmp_o := x"50";   when x"ac" => tmp_o := x"91";   when x"ec" => tmp_o := x"ce";
            when x"2d" => tmp_o := x"d8";   when x"6d" => tmp_o := x"3c";   when x"ad" => tmp_o := x"95";   when x"ed" => tmp_o := x"55";
            when x"2e" => tmp_o := x"31";   when x"6e" => tmp_o := x"9f";   when x"ae" => tmp_o := x"e4";   when x"ee" => tmp_o := x"28";
            when x"2f" => tmp_o := x"15";   when x"6f" => tmp_o := x"a8";   when x"af" => tmp_o := x"79";   when x"ef" => tmp_o := x"df";
            when x"30" => tmp_o := x"04";   when x"70" => tmp_o := x"51";   when x"b0" => tmp_o := x"e7";   when x"f0" => tmp_o := x"8c";
            when x"31" => tmp_o := x"c7";   when x"71" => tmp_o := x"a3";   when x"b1" => tmp_o := x"c8";   when x"f1" => tmp_o := x"a1";
            when x"32" => tmp_o := x"23";   when x"72" => tmp_o := x"40";   when x"b2" => tmp_o := x"37";   when x"f2" => tmp_o := x"89";
            when x"33" => tmp_o := x"c3";   when x"73" => tmp_o := x"8f";   when x"b3" => tmp_o := x"6d";   when x"f3" => tmp_o := x"0d";
            when x"34" => tmp_o := x"18";   when x"74" => tmp_o := x"92";   when x"b4" => tmp_o := x"8d";   when x"f4" => tmp_o := x"bf";
            when x"35" => tmp_o := x"96";   when x"75" => tmp_o := x"9d";   when x"b5" => tmp_o := x"d5";   when x"f5" => tmp_o := x"e6";
            when x"36" => tmp_o := x"05";   when x"76" => tmp_o := x"38";   when x"b6" => tmp_o := x"4e";   when x"f6" => tmp_o := x"42";
            when x"37" => tmp_o := x"9a";   when x"77" => tmp_o := x"f5";   when x"b7" => tmp_o := x"a9";   when x"f7" => tmp_o := x"68";
            when x"38" => tmp_o := x"07";   when x"78" => tmp_o := x"bc";   when x"b8" => tmp_o := x"6c";   when x"f8" => tmp_o := x"41";
            when x"39" => tmp_o := x"12";   when x"79" => tmp_o := x"b6";   when x"b9" => tmp_o := x"56";   when x"f9" => tmp_o := x"99";
            when x"3a" => tmp_o := x"80";   when x"7a" => tmp_o := x"da";   when x"ba" => tmp_o := x"f4";   when x"fa" => tmp_o := x"2d";
            when x"3b" => tmp_o := x"e2";   when x"7b" => tmp_o := x"21";   when x"bb" => tmp_o := x"ea";   when x"fb" => tmp_o := x"0f";
            when x"3c" => tmp_o := x"eb";   when x"7c" => tmp_o := x"10";   when x"bc" => tmp_o := x"65";   when x"fc" => tmp_o := x"b0";
            when x"3d" => tmp_o := x"27";   when x"7d" => tmp_o := x"ff";   when x"bd" => tmp_o := x"7a";   when x"fd" => tmp_o := x"54";
            when x"3e" => tmp_o := x"b2";   when x"7e" => tmp_o := x"f3";   when x"be" => tmp_o := x"ae";   when x"fe" => tmp_o := x"bb";
            when x"3f" => tmp_o := x"75";   when x"7f" => tmp_o := x"d2";   when x"bf" => tmp_o := x"08";   when x"ff" => tmp_o := x"16";
            when others=> tmp_o := x"00";
        end case;
        data_out((8*i-1) downto 8*(i-1)) := tmp_o;
    end loop;
    return data_out;
end function;

function calc_mcols(data_in : std_logic_vector; num_words : integer)
    return std_logic_vector is
    variable data_out                                : std_logic_vector(num_words*32-1 downto 0);
    variable i0,i1,i2,i3,i02,i12,i22,i32,o0,o1,o2,o3 : std_logic_vector(7 downto 0);
begin
    for i in 1 to num_words loop
        -- break the word into bytes w = i0,i1,i2,i3
        i3  := data_in((32*i-25) downto 32*i-32);
        i2  := data_in((32*i-17) downto 32*i-24);
        i1  := data_in((32*i-9)  downto 32*i-16);
        i0  := data_in((32*i-1)  downto 32*i-8);
        -- compute i_k * x in GF(2^8), i.e. left-shift and add 0x1B if most significant bit is 1
        i02 := (i0(6 downto 0) & i0(7)) xor ('0'&'0'&'0'&i0(7)&i0(7)&'0'&i0(7)&'0');
        i12 := (i1(6 downto 0) & i1(7)) xor ('0'&'0'&'0'&i1(7)&i1(7)&'0'&i1(7)&'0');
        i22 := (i2(6 downto 0) & i2(7)) xor ('0'&'0'&'0'&i2(7)&i2(7)&'0'&i2(7)&'0');
        i32 := (i3(6 downto 0) & i3(7)) xor ('0'&'0'&'0'&i3(7)&i3(7)&'0'&i3(7)&'0');
        -- compute each byte of the output o0,o1,o2,o3
        -- 2 3 1 1
        -- 1 2 3 1
        -- 1 1 2 3
        -- 3 1 1 2
        o0  :=  i02           xor (i12 xor i1)  xor i2            xor i3;
        o1  :=  i0            xor i12           xor (i22 xor i2)  xor i3;
        o2  :=  i0            xor i1            xor i22           xor (i32 xor i3);
        o3  :=  (i02 xor i0)  xor i1            xor i2            xor i32;
        -- concatenate bytes for the output word
        data_out((32*i-1) downto 32*(i-1)) := o0 & o1 & o2 & o3;
    end loop;
    return data_out;
end;

function calc_srows(data_in : std_logic_vector(127 downto 0))
    return std_logic_vector is
    variable data_out : std_logic_vector(127 downto 0);
begin
    data_out(127 downto 96) := data_in(127 downto 120) & data_in(87  downto  80) & data_in(47  downto 40 ) & data_in(7   downto 0);
    data_out(95  downto 64) := data_in(95  downto 88 ) & data_in(55  downto  48) & data_in(15  downto 8  ) & data_in(103 downto 96);
    data_out(63  downto 32) := data_in(63  downto 56 ) & data_in(23  downto  16) & data_in(111 downto 104) & data_in(71  downto 64);
    data_out(31  downto 0 ) := data_in(31  downto 24 ) & data_in(119 downto 112) & data_in(79  downto 72 ) & data_in(39  downto 32);
    return data_out;
end;

function calc_next_rnd_key(
    prev_full_key : std_logic_vector(KEY_WIDTH-1 downto 0);
    do_rcon       : boolean;
    rcon_byte     : std_logic_vector(7 downto 0))
return std_logic_vector is
    variable next_rnd_key : std_logic_vector(127 downto 0);
    variable sbox_word    : std_logic_vector( 31 downto 0);
    variable rcon_word    : std_logic_vector( 31 downto 0);
    variable w0,w1,w2,w3  : std_logic_vector( 31 downto 0);
begin
    sbox_word := calc_sbox(prev_full_key(31 downto 0), 4);
    -- for AES 256,
    -- in even rounds, do a RCON shift + SBOX
    -- in odd rounds, only do SBOX
    -- for AES 128, always do RCON shift + SBOX
    if do_rcon then
        rcon_word := (sbox_word(23 downto 16) xor rcon_byte) & sbox_word(15 downto 0) & sbox_word(31 downto 24);
    else
        rcon_word := sbox_word;
    end if;
    -- xor with key from 2 rounds ago
    w0 := prev_full_key(KEY_WIDTH-1  downto KEY_WIDTH-32 ) xor rcon_word;
    w1 := prev_full_key(KEY_WIDTH-33 downto KEY_WIDTH-64 ) xor w0;
    w2 := prev_full_key(KEY_WIDTH-65 downto KEY_WIDTH-96 ) xor w1;
    w3 := prev_full_key(KEY_WIDTH-97 downto KEY_WIDTH-128) xor w2;
    return (w0 & w1 & w2 & w3);
end;

function calc_next_aes_round(
    rnd_in   : std_logic_vector(127 downto 0);
    rnd_key  : std_logic_vector(127 downto 0);
    last_rnd : boolean)
return std_logic_vector is
    variable sbox_o  : std_logic_vector(127 downto 0);
    variable srows_o : std_logic_vector(127 downto 0);
begin
    sbox_o  := calc_sbox(rnd_in, 16);
    srows_o := calc_srows(sbox_o);
    if last_rnd then
        return rnd_key xor srows_o;
    else
        return rnd_key xor calc_mcols(srows_o, 4);
    end if;
end;

begin

---------------------------------
--  ROUND KEY PRE CALCULATIONS --
---------------------------------
key_ready <= bool2bit(round = 0 and key_round = 0);

-- monitors the inputs, updates the state, and changes the inputs to the compute functions
key_round_proc : process(clk)
begin
    if rising_edge(clk) then
        -- start the round key calculation when there is no data in the pipeline
        -- and a new key is pushed. do not allow a new key until the round key computation is complete
        -- or a reset occurs (round = 0)
        if (reset_p = '1') then
            -- on reset, go to round 0, disable key circuitry,
            key_round   <= 0;
            rnd_key_rdy <= '0';
        elsif (key_round = 0 and key_valid = '1') then
             -- beginning rnd_key computations
             rnd_key_rdy <= '0';
             -- load the full key, either 128 or 256 bits
             -- and compute the first round key
             rnd_keys(128+KEY_WIDTH-1 downto 0) <=
                key_data & calc_next_rnd_key(key_data, true, x"01");
             -- update the state for the next round
             -- a "round key" is 128 bits, so a 256 bit key is 2 round keys and a 128 bit key is 1 round key
             if (KEY_WIDTH = 256) then
                -- since we load all 256 bits of the key, we did 2 rounds at once
                -- and then computed one round, so the next round is 3
                key_round    <= 3;
                krnd_do_rcon <= false;
             else
                -- if 128, only we load one round then compute one round
                -- so the next round is 2
                key_round    <= 2;
                krnd_do_rcon <= true;
             end if;
             rcon  <= x"02";   -- reset rcon
        elsif (key_round > 0) then
            -- calculate the round key,
            rnd_keys  <=  rnd_keys(128*NR-1 downto 0) &
                          calc_next_rnd_key(rnd_keys(KEY_WIDTH-1 downto 0), krnd_do_rcon, rcon);
            -- the calculations will be complete on the next clock cycle, so back to round 0
            if key_round = NR then
                key_round   <= 0;   -- back to round 0
                rnd_key_rdy <= '1'; -- round keys are ready
            else
            -- if not the final round, then
            -- update state for the next round
                key_round <= key_round + 1;
                if KEY_WIDTH = 256 then             -- AES-128 does rcon every round
                    krnd_do_rcon <= not krnd_do_rcon;  -- do rcon every other round for AES 256
                end if;
                if krnd_do_rcon then             -- update rcon when used
                    if rcon(7) = '1' then
                        rcon  <= x"1b";
                    else
                        rcon  <= rcon(6 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

-----------------------------
--  AES ROUND CALCULATIONS --
-----------------------------
pt_ready <= bool2bit(round = 0 or (round = NR and ct_ready = '1'))
       and bool2bit(key_round = 0 and rnd_key_rdy = '1');
ct_valid <= bool2bit(round = NR);
ct_data  <= rnd_out;

cipher_round_proc : process(clk)
    variable idx : integer range 0 to 128*(NR+1)-1 := 0;
begin
    -- on reset, go to round 0, disable round circuitry,
    -- lower output flags
    if rising_edge(clk) then
        -- if the round keys are calculated, pt is inputted,
        -- and a new key is NOT being inputted, we start an AES round
        if (reset_p = '1') then
            round <= 0;
        elsif (key_round > 0) then
            null;
        elsif ((round = 0 or (round = NR and ct_ready = '1')) and
            rnd_key_rdy = '1' and pt_valid = '1' and key_valid ='0') then
            -- update state:
            round   <= 1;
            -- load pt and XOR with the current round key
            idx     := 128*NR-1;
            rnd_out <= calc_next_aes_round(
                pt_data xor rnd_keys(128*(NR+1)-1 downto 128*NR),
                rnd_keys(idx downto idx-127), false);
        -- allow a concurrent read/write in the last round:
        -- last round with new input given, jump to round 1
        -- last round but new input not given, back to round 0
        elsif (round = NR and ct_ready = '1' and pt_valid = '0') then
            round   <= 0;
        -- standard round
        elsif (round > 0 and round < NR) then
            round   <= round + 1;
            idx     := 128*NR-1 - round*128;
            rnd_out <= calc_next_aes_round(
                rnd_out, rnd_keys(idx downto idx-127), (round = NR-1));
        end if;
    end if;
end process;

end architecture aes;
