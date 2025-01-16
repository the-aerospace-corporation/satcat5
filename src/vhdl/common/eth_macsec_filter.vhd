--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This core filters frames that do not pass the MACSec authenticaiton check.
-- The macsec deframer adds an all ones or zeros word at the end of a frame,
-- depending on whether the frame is authenticated or not.
-- this buffers, checks the last byte then outputs a frame if it passes
-- and discards frames that do not pass.
-- Since an entire frame must be loaded and buffered prior to knowing whether
-- it has passed authentication or not, multiple frames can be buffered,
-- which minimizes flow control disruptions.
--
-- Input is Ethernet frames followed by a one word flag of all ones or all zeros
-- indicating whether the frame passed or failed authentication.
--
-- Output is Ethernet frames that have passed authentication.
-- If a frame passes authentication:
--    out_first is raised the clock cycle before the first word of a frame
--    (a clock cycle before out_ready is raised) and out_frame_length is
--    updated.  out_last is raised on the final byte of the frame.
-- If a frame fails authentication:
--    out_auth_fail is raised for 1 clock cycle
--------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity eth_macsec_filter is
    generic (
        DATA_WIDTH_BYTES      : integer   := 1;
        MAX_FRAME_SIZE_BYTES  : integer   := 1514;
        MAX_FRAME_DEPTH       : integer   := 2);
    port (
        -- frame in (AXI-stream)
        in_ready    : out   std_logic;
        in_valid    : in    std_logic;
        in_last     : in    std_logic; -- EOF
        in_data     : in    std_logic_vector(DATA_WIDTH_BYTES*8-1 downto 0);
        -- frame out (AXI-stream)
        out_ready   : in    std_logic;
        out_valid   : out   std_logic;
        out_first   : out   std_logic; -- SOF
        out_last    : out   std_logic; -- EOF
        out_data    : out   std_logic_vector(DATA_WIDTH_BYTES*8-1 downto 0);
        -- additional frame out meta-data
        out_frame_length : out   unsigned(10 downto 0);
        out_auth_fail    : out   std_logic;
        --system
        reset_p          : in    std_logic;
        clk              : in    std_logic);
end eth_macsec_filter;

architecture filter of eth_macsec_filter is

    constant FIFO_DEPTH : natural := MAX_FRAME_SIZE_BYTES * MAX_FRAME_DEPTH;
    signal w_addr       : integer range 0 to FIFO_DEPTH-1;
    signal r_addr       : integer range 0 to FIFO_DEPTH-1;

    type mem_type is array (FIFO_DEPTH-1 downto 0) of std_logic_vector(DATA_WIDTH_BYTES*8-1 downto 0);
    signal mem : mem_type;

    type sof_addrs_t    is array (MAX_FRAME_DEPTH-1 downto 0) of integer range 0 to FIFO_DEPTH-1;
    type frame_length_t is array (MAX_FRAME_DEPTH-1 downto 0) of integer range 0 to MAX_FRAME_SIZE_BYTES;

    signal w_idx : integer range 0 to MAX_FRAME_DEPTH := 0;
    signal r_idx : integer range 0 to MAX_FRAME_DEPTH := 0;

    signal sof_addrs      : sof_addrs_t;
    signal eof_addrs      : sof_addrs_t;
    signal frame_length   : frame_length_t;
    signal frame_loaded   : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => '0');
    signal frame_auth     : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => 'U');
    signal frame_unloaded : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => '1');
    signal frame_ready    : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => '0');

    signal out_valid_i    : std_logic := '0';
    signal in_ready_i     : std_logic := '1';

begin

    in_ready   <= in_ready_i;
    in_ready_i <= not frame_ready(w_idx);

    -- loads incoming frames into the buffer
    load_frm_buffer : process(clk, reset_p)
        variable curr_frame_bytes : integer range 0 to MAX_FRAME_SIZE_BYTES;
    begin
        if rising_edge(clk) then
            if reset_p = '1' then
                frame_loaded     <= (others => '0');
                frame_auth       <= (others => 'U');
                w_idx            <= 0;
                curr_frame_bytes := 0;
                w_addr           <= 0;
            elsif in_valid = '1' and in_ready_i = '1' and in_last = '1' then
                frame_length(w_idx) <= curr_frame_bytes;
                frame_loaded(w_idx) <= '1';
                frame_auth(w_idx)   <= in_data(0);
                w_idx               <= (w_idx + 1) mod MAX_FRAME_DEPTH;
                curr_frame_bytes    := 0;
            elsif in_valid = '1' and in_ready_i ='1' and in_last ='0' then
                if curr_frame_bytes = 0 then
                    frame_loaded(w_idx) <= '0';
                    frame_auth(w_idx)   <= 'U'; -- we don't yet know whether this frame is authenticated
                    sof_addrs(w_idx)    <= w_addr;
                end if;
                mem(w_addr)      <= in_data;
                w_addr           <= (w_addr + 1) mod FIFO_DEPTH;
                curr_frame_bytes := curr_frame_bytes + DATA_WIDTH_BYTES;
                eof_addrs(w_idx) <= w_addr;
            end if;
        end if;
    end process;

    -- checks whether frames have been loaded and unloaded into the buffer.
    -- a frame is 'ready' if it has been loaded and not yet been unloaded,
    -- so catching the rising edge of frame_loaded and frame_unloaded,
    -- i.e. ready changes as a frame is (un)loaded (0 to 1)
    update_ready_frame : process(clk, reset_p)
        variable frame_loaded_q   : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => '0');
        variable frame_unloaded_q : std_logic_vector(MAX_FRAME_DEPTH - 1 downto 0) := (others => '1');
    begin
        if rising_edge(clk) then
            if reset_p = '1' then
                frame_ready      <= (others => '0');
                frame_loaded_q   := (others => '0');
                frame_unloaded_q := (others => '1');
            else
                for frame in 0 to MAX_FRAME_DEPTH-1 loop
                    if frame_loaded_q(frame) = '0' and frame_loaded(frame) = '1' then
                        frame_ready(frame)  <= '1';
                    elsif (frame_unloaded_q(frame) = '0' and frame_unloaded(frame) = '1') then
                        frame_ready(frame)  <= '0';
                    end if;
                    frame_loaded_q(frame)   := frame_loaded(frame);
                    frame_unloaded_q(frame) := frame_unloaded(frame);
                end loop;
            end if;
        end if;
    end process;

    out_valid     <= out_valid_i;
    -- pulse frame length at SOF for authenticated frames
    out_frame_length <= to_unsigned(frame_length(r_idx), out_frame_length'length)
                        when frame_ready(r_idx) = '1'
                        else (others => '0');
    -- pulse a '1' when a frame fails authentication (1 clock cycle)
    out_auth_fail    <= '1' when frame_auth(r_idx) = '0'
                        and  frame_unloaded(r_idx) = '0'
                        and  frame_ready(r_idx)    = '1' else
                        '0';
    -- raise when at the current EOF
    out_last         <= '1' when r_addr = eof_addrs(r_idx) else '0';
    out_data         <= mem(r_addr);
    -- unloads frames that pass the authentication check
    unload_frm_buffer : process(clk)
        variable is_sof : std_logic := '1';
    begin
        if rising_edge(clk) then
            if reset_p = '1' then
                is_sof := '1';
                out_valid_i      <= '0';
                frame_unloaded   <= (others => '1');
                r_idx            <= 0;
                out_first        <= '0';
                r_addr           <= 0;
            -- frame at index r_idx has been loaded and not yet unloaded
            elsif frame_ready(r_idx) = '1' then
                -- frame failed authentication
                if frame_auth(r_idx) = '0' then
                    -- need to force the frame_unloaded rising edge
                    -- to reset frame_ready and move to next frame index
                    frame_unloaded(r_idx) <= '0';
                    if frame_unloaded(r_idx) = '0' then
                        r_idx                 <= (r_idx + 1) mod MAX_FRAME_DEPTH;
                        frame_unloaded(r_idx) <= '1';
                        is_sof                := '1';
                    end if;
                -- frame passed authentication
                else
                    -- raise out_first for 1 clock cycle at SOF
                    -- and prepare to output a new frame
                    if is_sof = '1' then
                        out_first             <= '1';
                        frame_unloaded(r_idx) <= '0';
                        is_sof                := '0';
                        -- ensure we start at this frames SOF address
                        r_addr                <= sof_addrs(r_idx);
                    else
                        --
                        out_first   <= '0';
                        out_valid_i <= '1';
                        if out_valid_i = '1' and out_ready = '1' then
                            r_addr  <= (r_addr + 1) mod FIFO_DEPTH;
                            -- stop sending data once we pass this frames EOF address
                            if r_addr = eof_addrs(r_idx) then
                                r_idx                 <= (r_idx + 1) mod MAX_FRAME_DEPTH;
                                frame_unloaded(r_idx) <= '1';
                                out_valid_i           <= '0';
                                is_sof                := '1';
                            end if;
                        end if;
                        end if;
                end if;
            end if;
        end if;
    end process;

end filter;
