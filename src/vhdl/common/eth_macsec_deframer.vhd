--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Deframer for IEEE 802.1ae MACsec
-- Decrypt and authenticate incoming cyphertext packets. All interfaces use AXI-streams.
-- To use:
--  1) a valid configuration, consisting of a key (either 128 or 256, depending
--     on generic) and a 96-bit SALT/IV, must be loaded via the cfg interface.
--     On reset, cfg_ready will be raised and will fall once the full config-
--     uration is loaded. Then some precomputation occurs. Once the computations
--     complete, either a new configuration can be loaded (cfg_ready rises) or
--     encrypted MACsec frames can be loaded.
--  2) MACsec frames are loaded via the frame in interface. MACsec frames are
--     expected to be correctly formatted, specifically:
--      * Ethernet header comprised of: DEST MAC (6 bytes) + SRC MAC (6 bytes)
--      * SecTag: Type (2 bytes) +  TCI/AN (1 byte) + SL (1 byte) + PN (4 bytes)
--      * Payload (N = 48 to 1502 bytes) consisting of the MACsec ciphertext
--      * ICV authentication tag (16 bytes)
--      ...for a total size of N + 36.
--     in_last must be raised on the final word of the ICV (e.g. 16th byte)
--     in_ready stays raised until 128 bits are received, then the 128-bit block
--     is decrypted and held in a small output buffer.
--  3) Decrypted Ethernet frames are output via the frame_out interface as soon
--     as the data becomes available (prior to authentication completion). The
--     Ethernet frames have standard form, with a payload of N-2 bytes (N+12
--     bytes). If downstream flow control is asserted and the output buffer
--     fills, new inputs will be blocked (in_ready will not be raised) until
--     the output is read.
--  4) Once a full MACsec frame is loaded, the received ICV is compared to the
--     computed ICV. Regardless of the comparison, the full decrypted frame is
--     output, and out_last is raised on the word AFTER the final word of the
--     frame. If the RX'd ICV = the computed ICV then the frame is authenticated
--     and when out_last = '1', out_data is all ones. If the ICVs do not match,
--     the frame is NOT authenticated and when out_last = '1', out_data is all
--     zeros. A downstream buffer can be inserted to output authenticated frames
--     and discard unauthenticated frames by checking the final word
--     (example implementation in eth_macsec_filter)
--     Once out_last is raised and the final word is read, either a new configuration
--     or a new frame can be loaded.
-- ADDITIONAL NOTES:
--   1) The MACsec TCI+AN parameters are fixed at 0x0C in this implementation.
--      Specifically, V = 0, ES = 0, SC = 0, E = 1, C = 1, and AN = 0,
--      so both integrity/authentication is provided and the user data is
--      encrypted. Secure Channel Identifier is not expected to match the
--      source address, and SCI is not included in the header. Expanding this
--      implementation to the full scope is a WIP.
--   2) This configuration uses eXtended Packet Numbering (XPN), and the least
--      significant 32 bits are included in the header.
--      Implementing standard packet number (non-XPN, 32 bits) is a WIP.
--   3) A frame's initialization vector (IV) is determined by the Session IV
--      (SALT - 12 bytes) XOR'd with a Short Secure Channel ID (SSCI - 4 bytes)
--      appended by the 8 byte Packet Number. This implementation takes SSCI =
--      0x0000 and only uses a 4 byte SALT. So a frame's IV is a 4-byte IV
--      followed by a 8-byte Packet Number (i.e. the 96-bit portion of the
--      config).  Incorporating the full scope of SSCI and SALT is a WIP.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity eth_macsec_deframer is
    generic(
    KEY_WIDTH   : integer   := 256; -- 128 or 256 only
    DATA_WIDTH  : integer   := 8;   -- must divide 160 and 128
    CFG_WIDTH   : integer   := 8);  -- must divide 96 and 128
    port(
    -- config in (AXI-stream)
    cfg_data    : in  std_logic_vector(CFG_WIDTH-1 downto 0);
    cfg_valid   : in  std_logic;
    cfg_ready   : out std_logic := '1';
    -- frame in (AXI-stream)
    in_data     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    in_last     : in  std_logic; -- EOF
    in_valid    : in  std_logic;
    in_ready    : out std_logic := '0';
    -- frame out (AXI-stream)
    out_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    out_last    : out std_logic := '0';
    out_valid   : out std_logic := '0';
    out_ready   : in  std_logic;
    --system
    reset_p     : in  std_logic;
    clk         : in  std_logic);
end eth_macsec_deframer;

architecture macsec_deframe of eth_macsec_deframer is

constant MACSEC_ETHERTYPE : std_logic_vector(15 downto 0) := x"88E5";
constant TCI_AN           : std_logic_vector(7 downto 0)  := x"0C";
constant N_ADDR       : integer := 6;
constant N_TYPE       : integer := 2;
constant N_ETHER_HDR  : integer := 2*N_ADDR + N_TYPE; -- 14 bytes
constant N_TCIAN      : integer := 1;
constant N_SL         : integer := 1;
constant N_PN         : integer := 4;
constant N_MACSEC_HDR : integer := N_ETHER_HDR + N_TCIAN + N_SL + N_PN; -- 20 bytes
constant MAX_ETHER_PL : integer := 1500;

signal macsec_hdr : std_logic_vector(8*N_MACSEC_HDR-1 downto 0) :=
    x"000000000000" & x"000000000000" &  MACSEC_ETHERTYPE & TCI_AN & x"00" & x"00000000";
-- Secure Channel Identifier currently unused

-- store the frame_iv. it is updated by the RX'd macsec frame
-- to incorporate the frame's packet number
signal frame_iv      : std_logic_vector(95 downto 0);
-- store the ICV from the RX'd macsec frame
-- to compare to the calculated tag
signal got_tag       : std_logic_vector(127 downto 0);
signal tags_disagree : std_logic := '0';

-- delayer signals
signal data_in_rdy_dl  : std_logic := '0';
signal data_in_rdy_df  : std_logic := '0';
signal data_in_val_df  : std_logic := '0';
signal data_in_last_df : std_logic := '0';
signal in_count_dl     : integer range 0 to 2047 := 0;
signal tag_in_count_dl : integer range 0 to 31 := 0;
signal in_buffer_dl    : std_logic_vector(128+data_width-1 downto 0);

-- internal signals used to represent state between processes
signal do_iv_update      : std_logic := '0';
signal iv_loaded         : std_logic := '0';
signal cfg_loaded        : std_logic := '0';
signal loading_cfg       : std_logic := '0';
signal load_frame_done   : std_logic := '0';
signal load_tag_done     : std_logic := '0';
signal calc_tag_done     : std_logic := '0';
signal unload_frame_done : std_logic := '0';
signal hdr_loaded        : std_logic := '0';
signal hdr_unloaded      : std_logic := '0';
signal payload_unloaded  : std_logic := '0';
signal aad_loaded        : std_logic := '0';

-- counts the number of bytes from in_data and cfg_data
signal data_count    : integer range 0 to MAX_ETHER_PL + N_ETHER_HDR := 0;
signal num_cfg_bytes : integer range 0 to (KEY_WIDTH + 96)/8 := 0;

-- internal signals for passing the macsec header
-- to the aes_gcm module and to the output
signal aad_last_i    : std_logic := '0';
signal hdr_word_gcm  : std_logic_vector(DATA_WIDTH-1 downto 0);
signal hdr_val_gcm   : std_logic := '0';
signal hdr_word_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
signal hdr_val_out   : std_logic := '0';

-- aes-gcm signals
signal gcm_req_key       : std_logic;
signal gcm_req_iv        : std_logic;
signal gcm_key_iv_in_val : std_logic_vector(1 downto 0);
signal gcm_key_iv_in     : std_logic_vector(CFG_WIDTH-1 downto 0);
-- aad and txt in
signal gcm_req_aad          : std_logic;
signal gcm_req_txt_in       : std_logic;
signal gcm_aad_txt_in_val   : std_logic_vector(1 downto 0); -- none, 01 aad, 10 txt, 11 auth only
signal gcm_aad_txt_in_last  : std_logic := '0';
signal gcm_aad_txt_in       : std_logic_vector(DATA_WIDTH-1 downto 0);
-- txt out
signal gcm_req_txt_out  : std_logic := '0';
signal gcm_txt_out_val  : std_logic;
signal gcm_txt_out_last : std_logic;
signal gcm_txt_out      : std_logic_vector(DATA_WIDTH-1 downto 0);
-- tag out
signal gcm_req_tag_out  : std_logic := '0';
signal gcm_tag_out_val  : std_logic;
signal gcm_tag_out      : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

u_gcm : entity work.aes_gcm
    generic map(
    KEY_WIDTH    => KEY_WIDTH,
    IS_ENCRYPT   => false,
    DATA_WIDTH   => DATA_WIDTH,
    CFG_WIDTH    => CFG_WIDTH)
    port map(
    -- key and iv in
    key_rdy      => gcm_req_key,
    iv_rdy       => gcm_req_iv,
    key_iv_val   => gcm_key_iv_in_val,
    key_iv_in    => gcm_key_iv_in,
    -- aad and txt in
    aad_rdy      => gcm_req_aad,
    txt_in_rdy   => gcm_req_txt_in,
    aad_txt_val  => gcm_aad_txt_in_val,
    aad_txt_last => gcm_aad_txt_in_last,
    aad_txt_in   => gcm_aad_txt_in,
    -- txt out
    txt_data     => gcm_txt_out,
    txt_last     => gcm_txt_out_last,
    txt_valid    => gcm_txt_out_val,
    txt_ready    => gcm_req_txt_out,
    -- tag out
    tag_data     => gcm_tag_out,
    tag_valid    => gcm_tag_out_val,
    tag_ready    => gcm_req_tag_out,
    --system
    reset_p      => reset_p,
    clk          => clk);

--
-- configuration (key and IV) I/O and state management
--

-- allow loading a config (either key+iv or iv)
-- when the gcm module is able to accept a key
-- and keep it set until the CFG is loaded
cfg_ready     <= gcm_req_key or (gcm_req_iv and loading_cfg);
-- key is an external input, but the IV is an internal signal
gcm_key_iv_in <= cfg_data when (gcm_key_iv_in_val = "01" or gcm_key_iv_in_val = "10") and cfg_valid = '1' else
                 frame_iv(95 downto 96 - CFG_WIDTH) when gcm_key_iv_in_val = "10" else
                 (others => '0');
-- when loading an external config, the first 256 (128) bits are the key
-- when updating the IV, the 'do_iv_update' signal is set within the cfg_control process
gcm_key_iv_in_val <= "01" when  cfg_valid = '1' and num_cfg_bytes <  KEY_WIDTH/8 else
                     "10" when (cfg_valid = '1' and num_cfg_bytes >= KEY_WIDTH/8) or
                               (do_iv_update = '1' and iv_loaded = '0') else
                     "00";
-- manages the state and i/o related to the key and IV
config_control : process(clk)
    variable tmp_iv : std_logic_vector(31 downto 0);
begin
    if rising_edge(clk) then
        if reset_p = '1' then
            -- all signals and variables controlled by this process
            num_cfg_bytes <= 0;
            loading_cfg   <= '0';
            cfg_loaded    <= '0';
            frame_iv      <= (others => '0');
            do_iv_update  <= '0';
            iv_loaded     <= '0';
        -- when loading an external config, the first 256 (128) bits are the key and the last 96 bits are the IV
        elsif gcm_req_key = '1' and gcm_key_iv_in_val = "01" and cfg_valid = '1' then
            num_cfg_bytes <= num_cfg_bytes + CFG_WIDTH/8;
            loading_cfg   <= '1';
            cfg_loaded    <= '0';
        -- we store the loaded IV, since we updated it with each new frame's packet number
        elsif gcm_req_iv = '1' and loading_cfg = '1' and cfg_valid = '1' then
            num_cfg_bytes <= num_cfg_bytes+CFG_WIDTH/8 ;
            frame_iv      <= frame_iv(95-CFG_WIDTH downto 0) & cfg_data;
            if num_cfg_bytes = (KEY_WIDTH+96-CFG_WIDTH)/8 then
                num_cfg_bytes <= 0;
                loading_cfg   <= '0';
                cfg_loaded    <= '1';
            end if;
        -- we update the frame IV when a new macsec header is received
        -- we enter this state from the load_gcm process
        elsif hdr_loaded = '1' and do_iv_update = '0' then
            -- if the RX'd packet number is smaller than the expected PN
            -- then a 32-bit rollover has occurred.
            -- normally, the macsec_hdr PN = prev PN + X
            -- where X \ge 1 (normally 1, but > 1 if frames are lost)
            if unsigned(frame_iv(31 downto 0)) > unsigned(macsec_hdr(31 downto 0)) then
                tmp_iv := frame_iv(63 downto 32);
                frame_iv(63 downto 32) <= std_logic_vector(unsigned(tmp_iv) + 1);
            end if;
            frame_iv(31 downto 0) <= macsec_hdr(31 downto 0);
            do_iv_update          <= '1';
        -- once the frame IV is updated,
        -- load the new IV into the AES GCM module.
        -- when it's done, signal to the load_gcm process
        elsif iv_loaded = '0' and  do_iv_update = '1' and gcm_req_iv = '1' then
            num_cfg_bytes <= num_cfg_bytes + CFG_WIDTH/8;
            frame_iv      <= frame_iv(95-CFG_WIDTH downto 0) & frame_iv(95 downto 96-CFG_WIDTH);
            if num_cfg_bytes = (96 - CFG_WIDTH)/8 then
                iv_loaded <= '1';
            end if;
        -- when the offload process signals that the current frame is done,
        -- prepare for the next frame ("soft" reset that maintains the CFG)
        elsif unload_frame_done = '1' then
            do_iv_update  <= '0';
            iv_loaded     <= '0';
            num_cfg_bytes <= 0;
        end if;
    end if;
end process;

-- the deframer requires that the last flag be raised at the end of the data payload,
-- to denote the start of the tag. it is more natural for an upstream core to raise
-- the EOF flag at the end of the tag, rather than end of the payload.
-- this process delays the input by 128/data_width in order to
-- catch the last flag and delineate the payload and tag.
in_ready       <= data_in_rdy_dl;
data_in_rdy_dl <= '1'            when in_count_dl < 128/data_width+1 -- initial filling of buffer
             else data_in_rdy_df when tag_in_count_dl = 0            -- allow input when buffer not full
             else '0';                                               -- wait for unload_frame_done before allowing more input
data_in_val_df <= '1'      when tag_in_count_dl > 1
             else in_valid when in_count_dl > 128/data_width and tag_in_count_dl = 0
             else '0';

load_deframer : process(clk)
begin
    if rising_edge(clk) then
        -- on reset or
        -- once the current frame has been processed by the deframer
        -- (either good or bad), prepare for a new one
        if reset_p = '1' or unload_frame_done = '1' then
            in_count_dl     <= 0;
            tag_in_count_dl <= 0;
            data_in_last_df <= '0';
        else
            -- send the buffer input to the deframer
            if data_in_rdy_df = '1' and data_in_val_df ='1' then
                data_in_last_df <= '0';
                -- the full tag has been loaded into the buffer (no more input till next frame)
                -- so the in_buffer_dl circular shift is safe
                if tag_in_count_dl > 1 then
                    in_buffer_dl(127+data_width downto data_width) <= in_buffer_dl(127 downto 0);
                    tag_in_count_dl <= tag_in_count_dl - 1;
                end if;
            end if;
            -- fill the buffer from the input
            if data_in_rdy_dl = '1' and in_valid ='1' then
                in_count_dl <= in_count_dl + 1;
                in_buffer_dl(127+data_width downto 0) <= in_buffer_dl(127 downto 0) & in_data;
                -- last byte of the tag
                if in_last = '1' then
                    tag_in_count_dl <= 128/data_width + 2;
                    data_in_last_df <= '1';
                end if;
            end if;
        end if;
    end if;
end process;

--
-- AES-GCM I/O and state management
-- and Input management
--

-- the module input is a macsec ethernet frame consisting of header + payload + tag
-- the header and tag are stored as internal signals
-- the payload is passed directly to the AES-GCM module as TXT input
data_in_rdy_df      <= '1'             when cfg_loaded = '1'      and hdr_loaded = '0'      else
                       gcm_req_txt_in  when aad_loaded = '1'      and load_frame_done = '0' else
                       '1'             when load_frame_done = '1' and load_tag_done = '0'   else
                       '0';
gcm_aad_txt_in_val  <= ('0' & hdr_val_gcm)    when iv_loaded = '1'  and aad_loaded = '0' else
                       (data_in_val_df & '0') when aad_loaded = '1' and load_frame_done = '0' else
                       "00";
gcm_aad_txt_in      <= hdr_word_gcm                             when iv_loaded = '1'  and aad_loaded = '0' else
                       in_buffer_dl(127+data_width downto 128)  when aad_loaded = '1' and load_frame_done = '0'
                       else (others => '0');
gcm_aad_txt_in_last <= aad_last_i      when iv_loaded = '1'  and aad_loaded = '0'     else
                       data_in_last_df when aad_loaded = '1' and load_frame_done = '0' else
                       '0';

load_gcm : process(clk)
    variable idx       : integer range 0 to 8*N_MACSEC_HDR := 0;
    variable aad_count : integer range 0 to N_MACSEC_HDR   := 0;
    variable tag_count : integer range 0 to 16             := 0;
begin
    if rising_edge(clk) then
        if reset_p = '1' then
            -- all signals and variables controlled by this process
            aad_count       := 0;
            tag_count       := 0;
            load_frame_done <= '0';
            load_tag_done   <= '0';
            data_count      <= 0;
            aad_last_i      <= '0';
            aad_loaded      <= '0';
            hdr_loaded      <= '0';
            hdr_val_gcm     <= '0';
            hdr_word_gcm    <= (others => '0');
            got_tag         <= (others => '0');
        -- once the key+IV has been loaded by the cfg process,
        -- get the macsec header with the address and packet number
        elsif cfg_loaded = '1' and hdr_loaded = '0'
          and data_in_val_df = '1' then
            -- wait for rdy=val=1
            idx        := 8*(N_MACSEC_HDR -data_count);
            macsec_hdr(idx-1 downto idx-DATA_WIDTH)<= in_buffer_dl(127+data_width downto 128) ;
            data_count <= data_count + DATA_WIDTH/8;
            -- once full macsec is loaded update the frame IV
            if data_count = N_MACSEC_HDR-DATA_WIDTH/8 then
                hdr_loaded <= '1';
            end if;
        -- wait for the frame IV update to complete in cfg process
        -- then load the MACSEC header into AES GCM as AAD
        elsif iv_loaded = '1' and aad_loaded = '0' then
            -- rdy=val=1
            if gcm_aad_txt_in_val = "01" and gcm_req_aad = '1' then
                aad_count := aad_count + DATA_WIDTH/8;
                if aad_count = N_MACSEC_HDR - DATA_WIDTH/8 then
                    aad_last_i <= '1';
                end if;
            end if;
            if aad_count = N_MACSEC_HDR then
                aad_loaded  <= '1';
                hdr_val_gcm <= '0';
                aad_last_i  <= '0';
            else
                idx := 8*(N_MACSEC_HDR - aad_count);
                hdr_word_gcm <= macsec_hdr(idx-1 downto idx-DATA_WIDTH);
                hdr_val_gcm  <= '1';
            end if;
        -- once the AAD is loaded, continue reading the input
        -- and directly load it as TXT into the AES-GCM module
        -- the 'last' flag is sent at the end of the data payload,
        -- then the next 16 input bytes are the ICV tag
        elsif aad_loaded = '1' and load_frame_done = '0'
          and gcm_req_txt_in = '1' and gcm_aad_txt_in_val = "10" then
            data_count          <= data_count + DATA_WIDTH/8;
            load_frame_done     <= data_in_last_df;
            -- break the word after data_in_last = '1'
        -- once the full payload is loaded into AES-GCM, load the tag
        -- and signal to offload_frame process that the tag is ready
        elsif load_frame_done = '1' and load_tag_done = '0'
          and data_in_val_df = '1' then
            idx := 8*(16-tag_count);
            got_tag(idx-1 downto idx-DATA_WIDTH) <= in_buffer_dl(127+data_width downto 128) ;
            tag_count := tag_count + DATA_WIDTH/8;
            if tag_count = 16 then
                load_tag_done <= '1';
            end if;
        -- once the full frame is loaded, wait for the output to be fully read
        -- before allowing new input.
        elsif unload_frame_done = '1' then
            load_frame_done <= '0';
            load_tag_done   <= '0';
            data_count      <= 0;
            aad_count       := 0;
            tag_count       := 0;
            aad_last_i      <= '0';
            aad_loaded      <= '0';
            hdr_loaded      <= '0';
        end if;
    end if;
end process;

--
-- Output management and state updating
--

-- the output is an ethernet frame (header + payload) followed by an all one's or all zero's word
-- denoting whether the RX'd and calculated ICV tags agree
-- first output the addresses from the macsec header
-- then output the TXT output from the AES-GCM
out_valid       <= hdr_val_out     when hdr_loaded = '1'       and hdr_unloaded = '0'      else
                   gcm_txt_out_val when hdr_unloaded = '1'     and payload_unloaded = '0'  else
                   '1'             when calc_tag_done = '1'    and unload_frame_done = '0' else
                   '0';
gcm_req_txt_out <= out_ready and hdr_unloaded and not payload_unloaded;
out_data        <= hdr_word_out                  when hdr_loaded = '1'    and hdr_unloaded = '0' else
                   gcm_txt_out                   when hdr_unloaded = '1'  and payload_unloaded = '0' else
                   (others => not tags_disagree) when calc_tag_done = '1' and unload_frame_done = '0' else
                   (others => '0');
out_last        <= calc_tag_done and not unload_frame_done;

offload_frame : process(clk)
    variable header_count : integer range 0 to N_ADDR*2         := 0;
    variable pay_count    : integer range 0 to MAX_ETHER_PL + 2 := 0;
    variable tag_count    : integer range 0 to 16               := 0;
    variable idx          : integer range 0 to 255;
begin
    if rising_edge(clk) then
        if reset_p = '1' then
            -- all signals and variables controlled by this process
            header_count := 0;
            pay_count    := 0;
            tag_count    := 0;
            hdr_unloaded <= '0';
            hdr_val_out  <= '0';
            hdr_word_out <= (others => '0');
            payload_unloaded  <= '0';
            gcm_req_tag_out   <= '0';
            tags_disagree     <= '0';
            calc_tag_done     <= '0';
            unload_frame_done <= '0';
        -- once the macsec header is loaded by gcm_load process,
        -- output the ether header (only the addresses)
        -- the ethertype is contained in the macsec payload
        elsif hdr_loaded = '1' and hdr_unloaded = '0' and unload_frame_done = '0'  then
            if out_ready = '1' and hdr_val_out = '1' then
                header_count := header_count + DATA_WIDTH/8;
            end if;
            if header_count = N_ADDR*2 then
                hdr_unloaded <= '1';
                hdr_val_out  <= '0';
            else
                -- unload only the address bytes from the macsec header
                idx := 8*(N_MACSEC_HDR - header_count);
                hdr_word_out <= macsec_hdr(idx-1 downto idx-DATA_WIDTH);
                hdr_val_out  <= '1';
            end if;
        -- after the header is outputted, output the macsec payload
        elsif hdr_unloaded = '1' and payload_unloaded = '0' then
            if out_ready = '1' and gcm_txt_out_val = '1' then
                pay_count := pay_count + DATA_WIDTH/8;
            end if;
            if load_frame_done = '1' and pay_count = data_count - N_MACSEC_HDR then
                payload_unloaded <= '1';
            end if;
        -- after the payload, get the ICV from AES-GCM and compare it to the RX'd tag
        elsif payload_unloaded = '1' and load_tag_done = '1' and calc_tag_done = '0' then
            gcm_req_tag_out <= '1';
            if gcm_req_tag_out = '1' and gcm_tag_out_val = '1' then
                idx := 8*(16-tag_count);
                if gcm_tag_out /= got_tag(idx-1 downto idx-DATA_WIDTH) then
                    tags_disagree <= '1';
                end if;
                tag_count := tag_count + DATA_WIDTH/8;
            end if;
            if tag_count = 16 then
                calc_tag_done   <= '1';
                gcm_req_tag_out <= '0';
            end if;
        -- when the full ICV has been checked,
        -- output an all 1's word if the tags agree
        -- and all 0's word if the tags disagree
        elsif calc_tag_done = '1' and unload_frame_done = '0'
          and out_ready = '1' then
            unload_frame_done <= '1';
        -- reset the output counts
        -- and signal to the other processes that the frame is offloaded
        elsif unload_frame_done = '1' then
            calc_tag_done     <= '0';
            tags_disagree     <= '0';
            unload_frame_done <= '0';
            payload_unloaded  <= '0';
            hdr_unloaded      <= '0';
            tag_count         :=  0;
            pay_count         :=  0;
            header_count      :=  0;
        end if;
    end if;
end process;

end macsec_deframe;
