--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------

-- performs AES-GCM encryption as described in NIST 800-38D
-- https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-38d.pdf
-- all I/O uses simplified AXI handshake: both valid and rdy must be set for the data to be used
-- on reset, key_rdy = iv_rdy = '1' and aad_rdy = txt_in_rdy = '0'
-- the FSM for a typical use of AES-GCM is intricate. to use:
--  1) a (128 or 256 bit) key must be loaded in key_iv_in with key_iv_val = "01".
--     when the key is loaded, key_rdy will fall
--  2) a 96-bit IV must be loaded in key_iv_in with key_iv_val = "10"
--     when the IV is loaded, IV_rdy will fall
--  3) once the key and IV are loaded, all non-reset inputs are ignored
--     i.e. key_rdy = iv_rdy = aad_rdy = txt_in_rdy = '0'
--    and some pre-computations occur, specifically:
--    3.1) once the key is loaded, the ECB round keys take 14 clock cycles to compute
--    3.2) once the round keys are complete, 'H' takes 14 clock cycles to compute
--    3.3) once the IV is loaded and H is complete, E[Y_0] takes 14 clock cycles to compute.
--   a few clock cycles are dedicated to internal handshakes,
--   and the module will be ready for TXT input 46 clock cycles after the key is loaded
--   or 16 clock cycles after the IV is loaded, whichever is later
--  4) once pre-computations are complete, we have
--     key_rdy = iv_rdy = aad_rdy = txt_in_rdy = '1'
--     and the module will idle until one of 5 things happen:
--     4.1) key_iv_val = "01" and a new key is loaded on key_iv_in. this goes back to step 1)
--          and aad_rdy and txt_in_rdy will fall
--     4.2) key_iv_val = "10" and a new IV is loaded on key_iv_in. this goes to step 2)
--          and key_rdy, aad_rdy, and txt_in_rdy will fall
--          the new E[Y_0] will be computed (round keys and 'H' are not recomputed),
--          and we will return to step 4) 16 clock cycles after the IV is loaded.
--     4.3) key_iv_val = "00" and aad_txt_val = "01" and AAD is loaded on aad_txt_in.
--          key_rdy, iv_rdy, and txt_in_rdy will fall and
--          aad_rdy will stay set until 128 bits of AAD are loaded or aad_txt_last is set.
--          the module then performs some computations on the AAD and aad_rdy will rise.
--          we stay in this step until aad_txt_last is set with the final AAD word.
--          we then move to step 5.
--     4.4) key_iv_val = "00" and aad_txt_val = "11" and AAD is loaded on aad_txt_in.
--          this is 'authenticaiton_only' mode (no TXT input) and is identical to 4.3,
--          except we move straight to step 6 (no TXT output).
--     4.5) key_iv_val = "00" and aad_txt_val = "10" and TXT is loaded on aad_txt_in.
--          we move straight to step 5. (no AAD)
--  5) once AAD is complete (or no AAD is sent), we have
--      key_rdy = iv_rdy = aad_rdy = '0' and = txt_in_rdy = '1'
--     set key_iv_val = "00" and aad_txt_val = "10" and TXT is loaded on aad_txt_in.
--     txt_in_rdy will stay set until 128 bits of TXT are loaded or aad_txt_last is set.
--     the module then performs some computations on the TXT, txt_in_rdy will rise,
--     and txt_valid will rise as soon as data becomes available.
--     txt_in_rdy will not rise if the previous output TXT buffer is unread
--     and the output TXT buffer will not advance until txt_ready is set (AXI handshake).
--     if input is available immediately, and txt_ready is asserted, then 128 bits of TXT
--     are read, processed, and outputted in 16-20 clock cycles, depending on DATA_WIDTH.
--     we stay in this step until aad_txt_last is set with the final TXT word. we then move to step 6.
--  6) once all TXT input is complete (or there is no TXT input), the ICV tag computations are finalized
--     and 'tag_val' will rise and the tag words will be written to 'tag_out'. no inputs are allowed during this time.
--     once all 128 bits of the tag are read ('tag_ready' must be set), we return to step 4.

-- the module can be used for AES-GCM-128 or AES-GCM-256 (but not AES-GCM-196, for now)
-- and can be operated as either an encrypter or decrypter.
-- the input and output must have the same DATA_WIDTH (due to zero-padding).
-- AES-GCM-256 throughput for DATA_WIDTH >= 16 is ~16 clock cycles per 128 bits of AAD+TXT
--                        for DATA_WIDTH = 8 is ~18 clock cycles per 128 bits of AAD+TXT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.common_functions.bool2bit;

entity aes_gcm is
    generic(
    KEY_WIDTH   : integer   := 256; -- 128 or 256 only
    IS_ENCRYPT  : boolean   := true; -- true is encrypt, false decrypt
    DATA_WIDTH  : integer   := 8;   -- must divide 128.
    CFG_WIDTH   : integer   := 8);  -- must divide both 128 and 96. so 1,2,4,8,16, or 32
    port(
    -- Shared key and iv in
    key_iv_in   : in  std_logic_vector(CFG_WIDTH-1 downto 0);
    key_iv_val  : in  std_logic_vector(1 downto 0); -- 00 none, 01 key, 10 iv, 11 reserved
    key_rdy     : out std_logic;
    iv_rdy      : out std_logic;
    -- Shared aad and txt in
    aad_txt_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    aad_txt_last: in  std_logic;
    aad_txt_val : in  std_logic_vector(1 downto 0); -- none, 01 aad, 10 txt, 11 auth only
    aad_rdy     : out std_logic;
    txt_in_rdy  : out std_logic;
    -- Cyphertext out (AXI-stream)
    txt_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    txt_last    : out std_logic;
    txt_valid   : out std_logic;
    txt_ready   : in  std_logic;
    -- Tag out (AXI-stream)
    tag_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    tag_valid   : out std_logic;
    tag_ready   : in  std_logic;
    --system
    reset_p     : in  std_logic;
    clk         : in  std_logic);
end aes_gcm;

architecture aes_gcm of aes_gcm is

-- the number of times the input must be read to get a full:
-- txt/aad/tag state, IV, and key
constant N_D_WORDS   : integer := 128 / DATA_WIDTH ;
constant N_KEY_WORDS : integer := KEY_WIDTH / CFG_WIDTH ;
constant N_IV_WORDS  : integer := 96 / CFG_WIDTH ;

-- the aes-gcm state diagram is somewhat complicated,
-- since we need to be able to update the key and IV,
-- and we can use it for only authentication (all AAD),
-- only encryption (all TXT), or both (AAD+TXT).
-- we initialize to GCM_NEED_KEY, then once a key is loaded,
-- step through CALC_KEY and CALC_H. then an IV must be loaded
-- and we step through GCM_CALC_IV and go to GCM_IDLE.
-- from GCM_IDLE, we can either
--   load a new key and go to GCM_NEED_KEY
--   load a new IV and go to GCM_NEED_IV
--   load AAD and go to GCM_READ_A
--   load TXT and go to GCM_READ_P
type gcm_states_t is (GCM_NEED_KEY, GCM_CALC_KEY, GCM_CALC_H,
                      GCM_NEED_IV,  GCM_CALC_IV,
                      GCM_IDLE,
                      GCM_READ_A, GCM_CALC_A,
                      GCM_READ_P, GCM_CALC_P,
                      GCM_CALC_TAG, GCM_WRITE_TAG);
signal gcm_state : gcm_states_t := GCM_NEED_KEY;

-- buffers for i/o data
signal tag_q     : std_logic_vector(127 downto 0) := (others => '0');
signal txt_i_q   : std_logic_vector(127 downto 0) := (others => '0');
signal txt_o_q   : std_logic_vector(127 downto 0) := (others => '0');
signal aad_q     : std_logic_vector(127 downto 0) := (others => '0');
signal key       : std_logic_vector(KEY_WIDTH-1 downto 0) := (others => '0');
signal iv        : std_logic_vector(95 downto 0) := (others => '0');

-- how many "words" of length DATA_WIDTH have been loaded into the various I/O buffers
signal key_i_buff_state : integer range 0 to N_KEY_WORDS := 0;
signal iv_i_buff_state  : integer range 0 to N_IV_WORDS  := 0;
signal aad_i_buff_state : integer range 0 to N_D_WORDS   := 0;
signal txt_i_buff_state : integer range 0 to N_D_WORDS   := 0;
signal txt_o_buff_state : integer range 0 to N_D_WORDS   := 0;
signal tag_o_buff_state : integer range 0 to N_D_WORDS   := 0;

-- counter tracks the number of 128-bit states used with the current key+IV
-- counter is encrypted using the aes_cipher and written to ct_ctr
-- aes-gcm does not encrypt the PT itself, it XORs the PT with ct_ctr
signal ctr    : std_logic_vector(127 downto 0) := (others => '0');
signal ct_ctr : std_logic_vector(127 downto 0) := (others => '0');

-- h and E[Y_0] are precomputed and used throughout the aes-gcm calculation
signal h      : std_logic_vector(127 downto 0) := (others => '0');
signal ey0    : std_logic_vector(127 downto 0) := (others => '0');

-- AAD and TXT length
signal len_A        : unsigned(63 downto 0)     := (others => '0');
signal len_C        : unsigned(63 downto 0)     := (others => '0');
signal txt_last_pos : integer range 0 to N_D_WORDS := N_D_WORDS-1;
-- tracking AAD and TXT last flag
signal aad_last, txt_done, aad_last_q, txt_last_q : std_logic := '0';
signal auth_only, auth_only_q : std_logic := '0';

signal ct_ctr_started : std_logic := '0';

-- aes_cipher I/O
signal aes_pt_rdy, aes_pt_val, aes_key_rdy, aes_key_val, aes_ct_rdy, aes_ct_val : std_logic := '0';

-- gf(2^128) multiplier I/O
signal mult_in, mult_out : std_logic_vector(127 downto 0) := (others => '0');
signal mult_in_rdy, mult_in_val, mult_out_rdy, mult_out_val : std_logic := '0';

-- used to signal between state control process and I/O processes
-- these are '1' when the current gcm_state allows the specified input type
signal key_rdy_s    : std_logic := '1';
signal iv_rdy_s     : std_logic := '0';
signal aad_rdy_s    : std_logic := '0';
signal txt_i_rdy_s  : std_logic := '0';
-- similarly, '1' when an output TXT/TAG 128-bit state is ready to start
-- unloading to the out-buffers
signal txt_o_eof_s  : std_logic;
signal txt_o_rdy_s  : std_logic := '0';
signal tag_rdy_s    : std_logic := '0';

-- equal to txt_out_val and tag_out_val but can be read
signal tag_out_i    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
signal txt_out_i    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
signal tag_val_i    : std_logic := '0';
signal txt_val_i    : std_logic := '0';

-- used to signal between state control process and I/O processes
signal clear_key_buffer   : std_logic := '0';
signal clear_iv_buffer    : std_logic := '0';
signal clear_txt_i_buffer : std_logic := '0';
signal clear_aad_buffer   : std_logic := '0';
signal clear_txt_o_buffer : std_logic := '0';
signal clear_tag_buffer   : std_logic := '0';

begin

u_aes : entity work.aes_cipher
    generic map(KEY_WIDTH)
    port map(
    -- in data
    pt_data    => ctr,
    pt_valid   => aes_pt_val,
    pt_ready   => aes_pt_rdy,
    -- key data
    key_data   => key,
    key_valid  => aes_key_val,
    key_ready  => aes_key_rdy,
    -- out data
    ct_data    => ct_ctr,
    ct_valid   => aes_ct_val,
    ct_ready   => aes_ct_rdy,
    --system
    reset_p    => reset_p,
    clk        => clk);

-- with a digit size of 16 or larger, the multiplier is not the bottleneck
-- digit size 8 or lower, it becomes the bottleneck
u_gf_mult : entity work.aes_gcm_gf_mult
    generic map(16, true, true, true)
    port map(
    in_data_a   => mult_in,
    in_data_b   => h,
    in_valid    => mult_in_val,
    in_ready    => mult_in_rdy,
    -- out data
    out_data_ab => mult_out,
    out_valid   => mult_out_val,
    out_ready   => mult_out_rdy,
    -- sys
    reset_p     => reset_p,
    clk         => clk);

key_rdy_s    <= bool2bit(gcm_state = GCM_NEED_KEY or gcm_state = GCM_IDLE);
iv_rdy_s     <= bool2bit(gcm_state = GCM_CALC_KEY or gcm_state = GCM_CALC_H
                      or gcm_state = GCM_NEED_IV  or gcm_state = GCM_IDLE);
aad_rdy_s    <= bool2bit(gcm_state = GCM_IDLE     or gcm_state = GCM_READ_A   or gcm_state = GCM_CALC_A);
txt_i_rdy_s  <= bool2bit(gcm_state = GCM_IDLE     or gcm_state = GCM_READ_P   or gcm_state = GCM_CALC_P);


key_rdy      <= key_rdy_s and bool2bit(key_i_buff_state < N_KEY_WORDS);
iv_rdy       <= iv_rdy_s and bool2bit(iv_i_buff_state  < N_IV_WORDS);
aad_rdy      <= aad_rdy_s and bool2bit(aad_i_buff_state < N_D_WORDS) and not aad_last;
txt_in_rdy   <= txt_i_rdy_s and bool2bit(txt_i_buff_state < N_D_WORDS) and not txt_done;

-- reading in the key
load_key : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1' or clear_key_buffer = '1') then
            -- wait for the update_state process to use the key before resetting the buffer
            key_i_buff_state <= 0;
            key <= (others => '0');
        elsif (key_rdy_s = '1' and key_i_buff_state < N_KEY_WORDS and key_iv_val = "01") then
            -- when the key buffer is not full and rdy=val='1',
            -- add the current key_in 'word' to the buffer and update the buffer state
            key( KEY_WIDTH-1-CFG_WIDTH*key_i_buff_state downto
                 KEY_WIDTH-  CFG_WIDTH*key_i_buff_state-CFG_WIDTH) <= key_iv_in;
            key_i_buff_state <= key_i_buff_state + 1;
        end if;
    end if;
end process;

-- reading in the IV
load_iv : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1' or clear_iv_buffer = '1') then
            -- wait for the update_state process to use the IV before resetting the buffer
            iv_i_buff_state <= 0;
            iv <= (others => '0');
        elsif (iv_rdy_s = '1' and iv_i_buff_state < N_IV_WORDS and key_iv_val = "10") then
            -- when the IV buffer is not full and rdy=val='1',
            -- add the current iv_in 'word' to the buffer and update the buffer state
            iv( 95 - CFG_WIDTH*iv_i_buff_state downto
                96 - CFG_WIDTH*iv_i_buff_state - CFG_WIDTH) <= key_iv_in;
            iv_i_buff_state <= iv_i_buff_state + 1;
        end if;
    end if;
end process;

-- reading the AAD
load_aad : process(clk)
    variable clk_en : std_logic;
begin
    if rising_edge(clk) then
        -- when the AAD buffer is not full and rdy=val='1',
        -- add the current aad_in 'word' to the buffer, update the buffer state,
        -- and check whether this is the last AAD 'word'
        clk_en := aad_rdy_s and aad_txt_val(0) and bool2bit(aad_i_buff_state < N_D_WORDS);
        -- Count off the length for each block.
        if (reset_p = '1' or clear_tag_buffer = '1') then
            len_A <= (others => '0');
        elsif (clk_en = '1') then
            len_A <= len_A + DATA_WIDTH;
        end if;
        -- Update other end-of-data flags.
        if (reset_p = '1' or clear_tag_buffer = '1') then
            aad_last  <= '0';
            auth_only <= '0';
        elsif (clk_en = '1' and aad_txt_last = '1') then
            aad_last  <= '1';
            auth_only <= bool2bit(aad_txt_val = "11");
        end if;
        -- wait for the update_state process to use the current AAD 128-bit state before resetting the buffer
        if (reset_p = '1' or clear_aad_buffer = '1') then
            aad_i_buff_state <= 0;
            aad_q <= (others => '0');
        elsif (clk_en = '1') then
            aad_q( 127 - DATA_WIDTH*aad_i_buff_state downto
                   128 - DATA_WIDTH*aad_i_buff_state - DATA_WIDTH) <= aad_txt_in;
            if (aad_txt_last = '1') then
                aad_i_buff_state <= N_D_WORDS; -- Skip to end (zero-pad)
            else
                aad_i_buff_state <= aad_i_buff_state+1;
            end if;
        end if;
    end if;
end process;

-- reading the TXT_IN (pt or ct depending on mode)
load_txt : process(clk)
    variable clk_en : std_logic;
begin
    if rising_edge(clk) then
        -- when the AAD buffer is not full and rdy=val='1',
        -- add the current aad_in 'word' to the buffer, update the buffer state,
        -- and check whether this is the last AAD 'word'
        clk_en := txt_i_rdy_s and bool2bit(txt_i_buff_state < N_D_WORDS and aad_txt_val = "10");
        -- Count the cyphertext length.
        if (reset_p = '1' or clear_tag_buffer = '1') then
            len_C <= (others => '0');
        elsif (clk_en = '1') then
            len_C <= len_C + DATA_WIDTH;
        end if;
        -- Update other end-of-data flags.
        if (reset_p = '1' or clear_tag_buffer = '1') then
            txt_done     <= '0';
            txt_last_pos <= N_D_WORDS-1;
        elsif (clk_en = '1' and aad_txt_last = '1') then
            txt_done     <= '1';
            txt_last_pos <= txt_i_buff_state; -- save the index of the last word
        end if;
        -- wait for the update_state process to use the current TXT 128-bit state before resetting the buffer
        if (reset_p = '1' or clear_txt_i_buffer = '1') then
            txt_i_buff_state <= 0;
            txt_i_q          <= (others => '0');
        elsif (clk_en = '1') then
            txt_i_q( 127 - DATA_WIDTH*txt_i_buff_state downto
                     128 - DATA_WIDTH*txt_i_buff_state - DATA_WIDTH) <= aad_txt_in;
            if (aad_txt_last = '1') then
                txt_i_buff_state <= N_D_WORDS;  -- Skip to end (zero-pad)
            else
                txt_i_buff_state <= txt_i_buff_state + 1;
            end if;
         end if;
    end if;
end process;

-- writing the TXT_OUT (ct or pt depending on mode)
txt_data    <= txt_out_i;
txt_valid   <= txt_val_i;
txt_o_eof_s <= aes_ct_val and bool2bit(txt_i_buff_state = N_D_WORDS);

offload_txt : process(clk)
    variable o_buff_state : integer range 0 to N_D_WORDS := 0;
begin
    if rising_edge(clk) then
        txt_val_i <= '0';
        if (reset_p = '1' or txt_o_buff_state = N_D_WORDS) then
            txt_o_rdy_s <= '0'; -- Reset or end-of-block.
        elsif (gcm_state = GCM_READ_P and txt_o_eof_s = '1') then
            txt_o_rdy_s <= '1'; -- Ready to accept data.
        end if;
        if (reset_p = '1' or clear_txt_o_buffer = '1') then
            -- wait for the update_state process to acknowledge that
            -- the TXT has been read before resetting the buffer
            txt_o_buff_state <=  0;
        elsif (txt_o_rdy_s = '1' and txt_o_buff_state < N_D_WORDS) then
            -- when the buffer has valid data, write data to txt_out
            -- only advance to the next buffer state when the RX is ready to receive (rdy=val='1')
            o_buff_state := txt_o_buff_state;
            if txt_ready = '1' and txt_val_i = '1' then
                o_buff_state := o_buff_state + 1;
                -- if this is the last word, send the last_word flag and advance the buffer to the empty state
                -- so we don't send the 0 padded bytes
            end if;
            if o_buff_state < N_D_WORDS then
                txt_out_i <= txt_o_q(127 - DATA_WIDTH*o_buff_state
                              downto 128 - DATA_WIDTH*o_buff_state - DATA_WIDTH);
                txt_val_i <= '1';
            end if;
            if txt_last_q = '1' and o_buff_state = txt_last_pos then
                txt_last <= '1';
            elsif txt_last_q = '1' and o_buff_state = txt_last_pos + 1 then
                o_buff_state := N_D_WORDS;
                txt_last <= '0';
            end if;
            txt_o_buff_state <= o_buff_state;
        end if;
    end if;
end process;

-- writing the TAG to output
tag_data  <= tag_out_i;
tag_valid <= tag_val_i;

offload_tag : process(clk)
    variable o_buff_state : integer range 0 to N_D_WORDS := 0;
begin
    if rising_edge(clk) then
        tag_val_i <= '0';
        if (reset_p = '1' or clear_tag_buffer = '1') then
            -- wait for the update_state process to acknowledge that
            -- the TAG has been read before resetting the buffer
            tag_o_buff_state <= 0;
        elsif (tag_rdy_s = '1' and tag_o_buff_state < N_D_WORDS) then
            -- when the buffer has valid data, write data to tag_out
            -- only advance to the next buffer state when the RX is ready to receive (rdy=val='1')
            o_buff_state := tag_o_buff_state;
            if tag_ready = '1' and tag_val_i = '1' then
                o_buff_state := o_buff_state + 1;
            end if;
            if o_buff_state < N_D_WORDS then
                tag_out_i <=   tag_q(127 - DATA_WIDTH*o_buff_state
                              downto 128 - DATA_WIDTH*o_buff_state - DATA_WIDTH);
                tag_val_i <= '1';
            end if;
            tag_o_buff_state <= o_buff_state;
        end if;
    end if;
end process;

-- when the key has been acknowledged by AES_cipher, reset the buffer
clear_key_buffer   <= bool2bit(gcm_state = GCM_NEED_KEY) and aes_key_rdy and aes_key_val;
-- when IV has been acknowledged by AES_cipher, reset the buffer
clear_iv_buffer    <= bool2bit(gcm_state = GCM_NEED_IV) and aes_pt_rdy and aes_pt_val;
-- when the current AAD has been sent to the multiplier, reset the buffer
clear_aad_buffer   <= bool2bit(gcm_state = GCM_READ_A) and mult_in_rdy and mult_in_val;
-- when the current TXT_IN has been sent to the multiplier and AES_cipher, reset the buffer
clear_txt_i_buffer <= bool2bit(gcm_state = GCM_READ_P and txt_i_buff_state = N_D_WORDS)
                  and aes_ct_val and not txt_o_rdy_s;
-- when the full output buffer has been reset, reset
clear_txt_o_buffer <= txt_o_rdy_s and bool2bit(txt_o_buff_state = N_D_WORDS);
-- when the full tag buffer has been read, reset
-- also reset the last_aad and last_txt flags and len_A and len_C for the next block
clear_tag_buffer   <= bool2bit(gcm_state = GCM_WRITE_TAG and tag_o_buff_state = N_D_WORDS and txt_o_buff_state = 0);

-- main control process: updates inputs to the compute processes, monitors I/O process,
-- and changes states when appropriate conditions are met
update_state : process(clk)
    variable ct_tmp : std_logic_vector(127 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        ---------------------------------------------------------
        -- Note: This entire process is one big if/elsif chain...
        ---------------------------------------------------------
        if (reset_p = '1') then
            -- we always boot/reset to the NEED_KEY state
            gcm_state    <= GCM_NEED_KEY;
            aes_key_val  <= '0';
            aes_pt_val   <= '0';
            aes_ct_rdy   <= '0';
            mult_in_val  <= '0';
            mult_out_rdy <= '0';

        -- from the IDLE state, we can enter a number of read states.
        -- updating the key is highest priority
        -- updating the IV is second highest priority
        -- if there's no IV or key being push, we can start reading AAD
        -- if there's not valid AAD, IV, or key being pushed, we can jump straight to TXT
        elsif gcm_state = GCM_IDLE then
            if key_iv_val = "01" then
                gcm_state <= GCM_NEED_KEY;
            elsif key_iv_val = "10" then
                gcm_state <= GCM_NEED_IV;
            elsif aad_txt_val = "01" or aad_txt_val = "11" then
                gcm_state <= GCM_READ_A;
            elsif aad_txt_val = "10" then
                gcm_state <= GCM_READ_P;
            end if;

        -- remain in the NEED_KEY state until the input key is fully read.
        -- then start the round key calculations
        elsif gcm_state = GCM_NEED_KEY and key_i_buff_state = N_KEY_WORDS then
            aes_key_val <= '1';
            -- wait for key handshake from AES_cipher before going to next state
            if aes_key_rdy = '1' and aes_key_val = '1' then
                aes_key_val <= '0';
                gcm_state   <= GCM_CALC_KEY;
            end if;

        -- while round key calculations complete, load the all zero vector to compute H
        elsif gcm_state = GCM_CALC_KEY then
            -- send the all 0 vector as PT input to AES_cipher:
            ctr           <= (others => '0');
            aes_pt_val    <= '1';
            -- wait for the round key calculations in AES_cipher to complete
            -- and for PT handshake from AES_cipher before going to next state
            if aes_pt_rdy = '1' and aes_pt_val = '1' then
                aes_pt_val  <= '0';
                aes_ct_rdy  <= '1';
                gcm_state   <= GCM_CALC_H;
            end if;

        -- wait for AES_cipher to complete H calculation before processing the IV
        elsif gcm_state = GCM_CALC_H and aes_ct_val = '1' and aes_ct_rdy = '1' then
            -- h = CT(0)
            h          <= ct_ctr;
            aes_ct_rdy <= '0';
            gcm_state  <= GCM_NEED_IV;

        -- after H is computed, we require the user to input an IV. they may have already done this in parallel
        -- since IV text can be loaded in any of the preceding states. however it's not used till here.
        -- once IV is loaded, start the E[Y_0] computation
        elsif gcm_state = GCM_NEED_IV and iv_i_buff_state = N_IV_WORDS then
            -- ey0 = CT(iv & 0x0001) where iv is 12 bytes
            ctr(127 downto 32) <= iv;
            ctr(31  downto  0) <= (0 => '1', others => '0');
            aes_pt_val         <= '1';
            -- wait for PT handshake from AES_cipher
            if aes_pt_rdy = '1' and aes_pt_val = '1' then
                aes_pt_val <= '0';
                aes_ct_rdy <= '1';
                gcm_state  <= GCM_CALC_IV;
            end if;

        -- wait for AES_cipher to complete E[Y_0] calculation
        -- once E[Y_0] is computed, enter the idle state (ready for AAD/txt input or a new key/IV)
        elsif gcm_state = GCM_CALC_IV and aes_ct_val = '1' and aes_ct_rdy = '1' then
            aes_ct_rdy <= '0';
            ey0        <= ct_ctr;
            gcm_state  <= GCM_IDLE;

        -- we read in AAD and update the tag (with prior AAD data) in parallel
        -- when the AAD buffer is full and the multiplier isn't busy,
        -- compute tag_{i+1} = (tag_i + AAD_i) * H
        elsif gcm_state = GCM_READ_A and aad_i_buff_state = N_D_WORDS then
            mult_in     <= tag_q xor aad_q;
            mult_in_val <= '1';
            -- wait for GF_multiplier handshake
            if mult_in_rdy = '1' and mult_in_val = '1' then
                aad_last_q   <= aad_last; -- flags from the read process that are used later
                auth_only_q  <= auth_only;
                --
                mult_in_val  <= '0';
                mult_out_rdy <= '1';
                gcm_state    <= GCM_CALC_A;
            end if;

        -- we enter the CALC_AAD state when a full state (128 bits) of AAD has been sent to the GF multiplier
        -- (potentially zero-padded by the load process)
        -- wait for the multiplier to be done, then update the tag
        elsif gcm_state = GCM_CALC_A and mult_out_val = '1' and mult_out_rdy = '1' then
            tag_q        <= mult_out;
            mult_out_rdy <= '0';
            -- if the user sent a 'last' flag in the previous state,
            -- then we're done with AAD. if not, read more AAD.
            -- if the user used the 'authentication only' mode,
            -- then finalize the ICV tag
            if aad_last_q = '1' then
                if auth_only_q = '1' then
                    gcm_state   <= GCM_CALC_TAG;
                    -- tag_N     = (tag_{N-1} + (lenA & lenC)) * H
                    mult_in     <= mult_out xor std_logic_vector(len_A & len_C);
                    mult_in_val <= '1';
                else
                    gcm_state <= GCM_READ_P;
                end if;
            else
                gcm_state <= GCM_READ_A;
            end if;

        -- we read in TXT, compute the CT, update the tag, output TXT all in parallel.
        -- the timing here is tricky, but they all take similar amounts of time.
        -- when the input buffer is full, new input is not allowed until the output buffer is emptied
        -- otherwise previous output data gets overwritten.
        elsif gcm_state = GCM_READ_P then
            -- when we get the first word of a new 128-bit state, increment the counter
            -- and start an AES cipher calculation.
            if ct_ctr_started = '0' and aad_txt_val = "10" and txt_last_q = '0' then
                ctr            <= std_logic_vector(unsigned(ctr) + 1);
                aes_pt_val     <= '1';
                ct_ctr_started <= '1';
            end if;
            -- AES_cipher TXT_IN handshake complete
            if aes_pt_rdy = '1' and aes_pt_val = '1' then
                aes_pt_val   <= '0';
                aes_ct_rdy   <= '0';
            end if;
            -- wait for the TXT input buffer to be full,
            --      for the previous TXT output to be empty, and
            --      for the AES cipher calculation to complete.
            -- we then fill the TXT output buffer and clear the TXT input buffer
            -- start the multiplier to compute tag_{i+1} = (tag_i + CT) * H
            if (txt_o_eof_s = '1' and txt_o_rdy_s = '0') then
                -- the multiplier input is different for encrypt and decrypt:
                -- if encrypter, first XOR the (PT) input TXT with the CT_CTR to get the CT
                -- if decrypter, the input TXT is the CT
                if IS_ENCRYPT then
                    -- the counter CT must have trailing zeros if TXT_IN was zero-padded
                    ct_tmp := ct_ctr;
                    if txt_last_pos < N_D_WORDS-1 then
                        ct_tmp(127-((txt_last_pos+1)*DATA_WIDTH) downto 0) := (others => '0');
                    end if;
                    mult_in <= tag_q xor txt_i_q xor ct_tmp;
                else
                    mult_in <= tag_q xor txt_i_q;
                end if;
                mult_in_val <= '1';
                -- output TXT is ready to be read
                -- so signal to the offload_txt process
                txt_o_q     <= txt_i_q xor ct_ctr;
                txt_last_q  <= txt_done;
                aes_ct_rdy  <= '1';
                -- we can start a new counter CT computation
                ct_ctr_started <= '0';
                -- go to next state
                gcm_state <= GCM_CALC_P;
            end if;

        -- waiting for the H*CT calculation to complete
        elsif gcm_state = GCM_CALC_P then
            -- when we get the first word of a new 128-bit state, increment the counter
            -- and start an AES cipher calculation.
            if ct_ctr_started = '0' and aad_txt_val = "10" and txt_last_q = '0' then
                ctr            <= std_logic_vector(unsigned(ctr) + 1);
                aes_pt_val     <= '1';
                ct_ctr_started <= '1';
            end if;
            -- AES_cipher TXT_IN handshake complete
            if aes_pt_rdy = '1' and aes_pt_val = '1' then
                aes_pt_val   <= '0';
                aes_ct_rdy   <= '0';
            end if;
            -- GF_multiplier input handshake
            if mult_in_val = '1' and mult_in_rdy = '1' then
                -- completed handshake
                mult_in_val  <= '0';
                mult_out_rdy <= '1';
            end if;
            -- wait for the multiplier to complete to update the tag
            if mult_out_rdy = '1' and mult_out_val = '1' then
                tag_q        <= mult_out;
                mult_out_rdy <= '0';
                 -- if the user sent a LAST flag in this block,
                -- then move to the final tag calculations.
                -- all input buffers should be clear here,
                -- but the output txt can still be read
                if txt_last_q = '1' then
                    gcm_state   <= GCM_CALC_TAG;
                    -- tag_N     = (tag_{N-1} + (lenA & lenC)) * H
                    mult_in     <= mult_out xor std_logic_vector(len_A & len_C);
                    mult_in_val <= '1';
                else
                    -- if not, read more TXT
                    gcm_state <= GCM_READ_P;
                end if;
            end if;

        -- tag_{N+1} = tag_N + E[Y_0]
        elsif gcm_state = GCM_CALC_TAG then
            -- complete the multiplier input handshake
            if mult_in_rdy = '1' and mult_in_val = '1' then
                mult_in_val  <= '0';
                mult_out_rdy <= '1';
            end if;
            -- complete the multiplier output handshake
            if mult_out_val = '1' and mult_out_rdy = '1' then
                mult_out_rdy <= '0';
                tag_q        <= mult_out xor ey0;
                tag_rdy_s    <= '1';
                -- the tag is now ready to be read! go to the final state
                gcm_state    <= GCM_WRITE_TAG;
            end if;

        -- wait for both the full tag and the full TXT out to be read before returning to the IDLE state
        -- and allowing more input
        elsif gcm_state = GCM_WRITE_TAG and tag_o_buff_state = N_D_WORDS and txt_o_buff_state = 0 then
            aes_ct_rdy <= '0';
            tag_rdy_s  <= '0';
            tag_q      <= (others => '0');
            txt_o_q    <= (others => '0');
            txt_last_q <= '0';
            aad_last_q <= '0';
            gcm_state  <= GCM_IDLE;
        end if;
    end if;
end process;

end aes_gcm;
