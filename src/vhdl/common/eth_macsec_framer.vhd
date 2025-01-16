--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Deframer for IEEE 802.1ae MACsec
-- Encrypt and tag outgoing plaintext packets. All interfaces use AXI-streams.
--
-- To use:
--  1) a valid configuration, consisting of a key (either 128 or 256, depending
--     on generic) and a 96-bit SALT/IV, must be loaded via the cfg interface.
--     On reset, cfg_ready will be raised and will fall once the full config-
--     uration is loaded. Then some precomputation occurs. Once the computations
--     complete, either a new configuration can be loaded (cfg_ready rises) or
--     plaintext Ethernet frames can be loaded.
--  2) Ethernet frames are loaded via the frame in interface. Ethernet frames
--     are expected to be correctly formatted, specifically:
--     * Ethernet header: DEST MAC (6 bytes) + SRC MAC (6 bytes) + Ethertype (2 bytes)
--     * Payload (N = 46 to 1500 bytes)
--     ...for a total size of N + 14.
--     Signal in_last is expected to be raised at the end of the payload.
--     Signal in_ready stays raised until 128 bits are received, then the
--     128-bit block is encrypted and held in a small output buffer.
--  3) Encrypted MACsec frames are outputted via the frame_out interface as soon
--     as the data becomes available (prior to authentication completion). The
--     MACsec frames have standard form:
--     * Ethernet header: DEST MAC (6 bytes) + SRC MAC (6 bytes)
--     * SecTag: Ethertype (2 bytes) +  TCI/AN (1 byte) + SL (1 byte) + PN (4 bytes)
--     * Payload (N+2 = 48 to 1502 bytes) consisting of the MACsec ciphertext
--     * ICV authentication tag (16 bytes)
--     ...for a total of N+38 bytes. out_last is raised on the final word of the
--     ICV. If downstream flow control is asserted and the output buffer fills,
--     new inputs will be blocked (in_ready will not be raised) until the output
--     is read.
--  4) Once the final word of the current ICV is read, either a new configuration
--     can be loaded or a new Ethernet frame can loaded.
-- NOTES:
--   1) The MACsec TCI+AN parameters are fixed at 0x0C in this implementation.
--      Specifically, V = 0, ES = 0, SC = 0, E = 1, C = 1, and AN = 0,
--      so both integrity/authentication is provided and the user data is
--      encrypted. Secure Channel Identifier is not expected to match the
--      source address, and SCI is not included in the header. Expanding this
--      implementation to the full scope is a WIP.
--   2) This configuration uses eXtended Packet Numbering (XPN), and the least
--      significant 32 bits are included in the header.  Implementing standard
--      packet number (non-XPN, 32 bits) is a WIP.
--   3) A frame's initialization vector (IV) is determined by the Session IV
--      (SALT - 12 bytes) XOR'd with a Short Secure Channel ID (SSCI - 4 bytes)
--      appended by the 8 byte Packet Number. This implementation takes SSCI =
--      0x0000 and only uses a 4 byte SALT. So a frame's IV is a 4-byte IV
--      followed by a 8-byte Packet Number (i.e. the 96-bit portion of the
--      config). Incorporating the full scope of SSCI and SALT is a WIP.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity eth_macsec_framer is
    generic(
    KEY_WIDTH   : integer   := 256; -- 128 or 256
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
    in_ready     : out std_logic := '0';
    -- frame out (AXI-stream)
    out_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
    out_last    : out std_logic := '0';
    out_valid   : out std_logic := '0';
    out_ready   : in  std_logic;
    --system
    reset_p     : in  std_logic;
    clk         : in  std_logic);
end eth_macsec_framer;

architecture macsec_frame of eth_macsec_framer is

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

signal frame_iv      : std_logic_vector(95 downto 0);
signal do_iv_update  : std_logic := '0';
signal iv_loaded     : std_logic := '0';
signal iv_loaded_q   : std_logic := '0';

signal aad_last_i    : std_logic := '0';

signal loading_cfg       : std_logic := '0';
signal load_frame_done   : std_logic := '0';
signal unload_frame_done : std_logic := '0';

signal hdr_loaded       : std_logic := '0';
signal hdr_unloaded     : std_logic := '0';
signal payload_unloaded : std_logic := '0';
signal aad_loaded       : std_logic := '0';
signal data_count       : integer range 0 to MAX_ETHER_PL + N_ETHER_HDR := 0;
signal num_cfg_bytes    : integer range 0 to (KEY_WIDTH+96)/8        := 0;

signal hdr_word_gcm  : std_logic_vector(DATA_WIDTH-1 downto 0);
signal hdr_val_gcm   : std_logic := '0';
signal hdr_word_out  : std_logic_vector(DATA_WIDTH-1 downto 0);
signal hdr_val_out   : std_logic := '0';

-- aes-gcm signals
signal gcm_key_rdy       : std_logic;
signal gcm_iv_rdy        : std_logic;
signal gcm_key_iv_in_val : std_logic_vector(1 downto 0);
signal gcm_key_iv_in     : std_logic_vector(CFG_WIDTH-1 downto 0);
-- aad and txt in
signal gcm_aad_rdy          : std_logic;
signal gcm_txt_in_rdy       : std_logic;
signal gcm_aad_txt_in_val   : std_logic_vector(1 downto 0); -- none, 01 aad, 10 txt, 11 auth only
signal gcm_aad_txt_in_last  : std_logic := '0';
signal gcm_aad_txt_in       : std_logic_vector(DATA_WIDTH-1 downto 0);
-- txt out
signal gcm_txt_out_rdy  : std_logic := '0';
signal gcm_txt_out_val  : std_logic;
signal gcm_txt_out_last : std_logic;
signal gcm_txt_out      : std_logic_vector(DATA_WIDTH-1 downto 0);
-- tag out
signal gcm_tag_out_rdy  : std_logic := '0';
signal gcm_tag_out_val  : std_logic;
signal gcm_tag_out      : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

u_gcm : entity work.aes_gcm
    generic map(
    KEY_WIDTH    => KEY_WIDTH,
    IS_ENCRYPT   => true,
    DATA_WIDTH   => DATA_WIDTH,
    CFG_WIDTH    => CFG_WIDTH)
    port map(
    -- key and iv in
    key_iv_in    => gcm_key_iv_in,
    key_iv_val   => gcm_key_iv_in_val,
    key_rdy      => gcm_key_rdy,
    iv_rdy       => gcm_iv_rdy,
    -- aad and txt in
    aad_txt_in   => gcm_aad_txt_in,
    aad_txt_last => gcm_aad_txt_in_last,
    aad_txt_val  => gcm_aad_txt_in_val,
    aad_rdy      => gcm_aad_rdy,
    txt_in_rdy   => gcm_txt_in_rdy,
    -- txt out
    txt_data     => gcm_txt_out,
    txt_last     => gcm_txt_out_last,
    txt_valid    => gcm_txt_out_val,
    txt_ready    => gcm_txt_out_rdy,
    -- tag out
    tag_data     => gcm_tag_out,
    tag_valid    => gcm_tag_out_val,
    tag_ready    => gcm_tag_out_rdy,
    --system
    reset_p      => reset_p,
    clk          => clk);

-- allow loading a config (either key+iv or iv)
-- when the gcm module is able to accept a key or IV
cfg_ready     <= gcm_key_rdy or (gcm_iv_rdy and loading_cfg);
-- key+iv are external input, but we also internally update the IV
gcm_key_iv_in <= cfg_data when (gcm_key_iv_in_val = "01" or gcm_key_iv_in_val = "10") and cfg_valid = '1' else
                 frame_iv(95 downto 96 - CFG_WIDTH) when (gcm_key_iv_in_val = "10") else
                 (others => '0');
-- when loading an external config, the first 256 (128) bits are the key and the last 96 bits are the IV
-- when internally updating the IV, the 'do_iv_update' signal is set
gcm_key_iv_in_val <= "10" when (cfg_valid = '1' and num_cfg_bytes >= KEY_WIDTH/8) or do_iv_update = '1' else
                     "01" when  cfg_valid = '1' and num_cfg_bytes < KEY_WIDTH/8 else
                     "00";

config_control : process(clk)
begin
    if rising_edge(clk) then
        iv_loaded     <= '0';
        if reset_p = '1' then
            loading_cfg   <= '0';
            num_cfg_bytes <=  0;
            do_iv_update  <= '0';
        -- when loading an external config, the first 256 (128) bits are the key and the last 96 bits are the IV
        elsif gcm_key_rdy = '1' and gcm_key_iv_in_val = "01" and cfg_valid = '1' then
            num_cfg_bytes <= num_cfg_bytes + CFG_WIDTH/8;
            loading_cfg   <= '1';
        -- we store the loaded IV, since we increment it with each new frame
        elsif gcm_iv_rdy = '1' and gcm_key_iv_in_val = "10" and cfg_valid = '1' then
            num_cfg_bytes <= num_cfg_bytes+CFG_WIDTH/8 ;
            frame_iv      <= frame_iv(95-CFG_WIDTH downto 0) & cfg_data;
            if num_cfg_bytes = (KEY_WIDTH+96-CFG_WIDTH)/8 then
                iv_loaded     <= '1';
                num_cfg_bytes <=  0;
                loading_cfg   <= '0';
            end if;
        -- we increment the frame IV before we begin processing a new frame
        elsif unload_frame_done = '1' and do_iv_update = '0' then
            frame_iv      <= std_logic_vector(unsigned(frame_iv) + 1);
            do_iv_update  <= '1';
        elsif do_iv_update = '1' and gcm_iv_rdy = '1' and gcm_key_iv_in_val = "10" then
            num_cfg_bytes <= num_cfg_bytes + CFG_WIDTH/8;
            frame_iv      <= frame_iv(95-CFG_WIDTH downto 0) & frame_iv(95 downto 96-CFG_WIDTH);
            if num_cfg_bytes = (96 - CFG_WIDTH)/8 then
                num_cfg_bytes <=  0;
                do_iv_update  <= '0';
                iv_loaded     <= '1';
            end if;
        end if;
    end if;
end process;


in_ready            <= '1'            when (hdr_loaded = '0' and (iv_loaded_q = '1' or iv_loaded = '1')) else
                       gcm_txt_in_rdy when (aad_loaded = '1' and load_frame_done = '0')       else
                       '0';
gcm_aad_txt_in_val  <= ('0' & hdr_val_gcm) when hdr_loaded = '1' and aad_loaded = '0'      else
                       (in_valid & '0')    when aad_loaded = '1' and load_frame_done = '0' else
                       "00";
gcm_aad_txt_in      <= hdr_word_gcm when hdr_loaded = '1' and aad_loaded = '0'      else
                       in_data      when aad_loaded = '1' and load_frame_done = '0' else
                       (others => '0');
gcm_aad_txt_in_last <= aad_last_i   when hdr_loaded = '1' and aad_loaded = '0'      else
                       in_last      when aad_loaded = '1' and load_frame_done = '0' else
                       '0';

load_gcm : process(clk)
    variable idx       : integer range 0 to 8*N_MACSEC_HDR := 0;
    variable aad_count : integer range 0 to N_MACSEC_HDR   := 0;
begin
    if rising_edge(clk) then
        if reset_p = '1' then
            iv_loaded_q     <= '0';
            data_count      <=  0;
            hdr_loaded      <= '0';
            aad_count       :=  0;
            aad_last_i      <= '0';
            aad_loaded      <= '0';
            hdr_val_gcm     <= '0';
            macsec_hdr      <= (others => '0');
            load_frame_done <= '0';
        -- once the IV has been loaded by the cfg process,
        -- get the DEST and SRC addresses from the incoming data stream
        -- and populate the macsec header with the address and packet number (the rest are constant)
        elsif hdr_loaded = '0' and (iv_loaded_q = '1' or iv_loaded = '1') then
            iv_loaded_q <= '1';
            -- wait for rdy=val=1
            if in_valid = '1' then
                idx        := 8*(N_MACSEC_HDR - data_count);
                data_count <= data_count + DATA_WIDTH/8;

                macsec_hdr(idx-1 downto idx-DATA_WIDTH) <= in_data;
                -- once both addresses are loaded, prepare the header
                -- and move to the next state
                if data_count = N_ADDR*2-DATA_WIDTH/8 then
                    idx := 8*(N_MACSEC_HDR-N_ADDR*2);
                    macsec_hdr(idx-1 downto idx-8*N_TYPE-8*N_TCIAN-8*N_SL)
                        <= MACSEC_ETHERTYPE & TCI_AN & x"00";
                    macsec_hdr(N_PN*8-1 downto 0) <= frame_iv(31 downto 0);
                    iv_loaded_q <= '0';
                    hdr_loaded  <= '1';
                end if;
            end if;
        -- load the buffered header as AAD into the AES-GCM module
        elsif hdr_loaded = '1' and aad_loaded = '0' then
            if gcm_aad_txt_in_val = "01" and gcm_aad_rdy = '1' then
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
        elsif aad_loaded = '1' and load_frame_done = '0' then
            if gcm_txt_in_rdy = '1' and gcm_aad_txt_in_val = "10" then
                data_count          <= data_count + DATA_WIDTH/8;
                load_frame_done     <= in_last;
                -- break the word after in_last = '1'
            end if;
        -- once the full frame is loaded, wait for the output to be fully read
        -- before allowing new input.
        elsif load_frame_done = '1' and unload_frame_done = '1' then
            load_frame_done <= '0';
            data_count <= 0;
            aad_count  := 0;
            aad_last_i <= '0';
            aad_loaded <= '0';
            hdr_loaded <= '0';
            hdr_val_gcm <= '0';
            macsec_hdr <= (others => '0');
        end if;
    end if;
end process;

out_valid       <= hdr_val_out     when hdr_loaded = '1'       and hdr_unloaded = '0'      else
                   gcm_txt_out_val when hdr_unloaded = '1'     and payload_unloaded = '0'  else
                   gcm_tag_out_val when payload_unloaded = '1' and unload_frame_done = '0' else
                   '0';
gcm_txt_out_rdy <= out_ready and hdr_unloaded and not payload_unloaded;
gcm_tag_out_rdy <= out_ready and payload_unloaded and not unload_frame_done;
out_data        <= hdr_word_out when hdr_loaded = '1'          and hdr_unloaded = '0'      else
                   gcm_txt_out  when hdr_unloaded = '1'        and payload_unloaded = '0'  else
                   gcm_tag_out  when payload_unloaded = '1'    and unload_frame_done = '0' else
                   (others => '0');

offload_frame : process(clk)
    variable header_count : integer range 0 to N_MACSEC_HDR := 0;
    variable pay_count    : integer range 0 to MAX_ETHER_PL + 2 := 0;
    variable tag_count    : integer range 0 to 16;
    variable idx          : integer range 0 to 255 := 0;
begin
    if rising_edge(clk) then
        out_last          <= '0';
        unload_frame_done <= '0';
        if reset_p = '1' then
            hdr_unloaded      <= '0';
            payload_unloaded  <= '0';
            hdr_val_out       <= '0';
            header_count      := 0;
            pay_count         := 0;
            tag_count         := 0;
        -- once the ether header is loaded by gcm_load process,
        -- output the macsec header
        elsif hdr_loaded = '1' and hdr_unloaded = '0' and unload_frame_done = '0' then
            if out_ready = '1' and hdr_val_out = '1' then
                header_count := header_count + DATA_WIDTH/8;
            end if;
            if header_count = N_MACSEC_HDR then
                hdr_unloaded <= '1';
                hdr_val_out  <= '0';
            else
                idx := 8*(N_MACSEC_HDR - header_count);
                hdr_word_out <= macsec_hdr(idx-1 downto idx-DATA_WIDTH);
                hdr_val_out  <= '1';
            end if;
        -- after the header is outputted, output the macsec payload
        elsif hdr_unloaded = '1' and payload_unloaded = '0' then
            if out_ready = '1' and gcm_txt_out_val = '1' then
                pay_count := pay_count + DATA_WIDTH/8;
            end if;
            if load_frame_done = '1' and pay_count >= data_count - 2*N_ADDR and gcm_txt_out_last = '1' then
                payload_unloaded <= '1';
            end if;
        -- after the payload, output the ICV
        elsif payload_unloaded = '1' and unload_frame_done = '0' then
            if out_ready = '1' and gcm_tag_out_val = '1' then
                tag_count := tag_count + DATA_WIDTH/8;
            end if;
            -- when the full ICV has been offloaded,
            -- reset the output counts
            -- and signal to the other processes that the frame is offloaded
            if tag_count = 16 then
                unload_frame_done <= '1';
                payload_unloaded  <= '0';
                hdr_unloaded      <= '0';
                hdr_val_out       <= '0';
                tag_count         :=  0;
                pay_count         :=  0;
                header_count      :=  0;
            elsif tag_count = 16 - DATA_WIDTH/8 then
                out_last          <= '1';
            end if;
        end if;
    end if;
end process;

end macsec_frame;
