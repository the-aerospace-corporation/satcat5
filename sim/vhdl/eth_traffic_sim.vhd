--------------------------------------------------------------------------
-- Copyright 2020-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic Ethernet traffic generator for simulation and test.
--
-- This block generates randomized Ethernet traffic and calculates required
-- checksums to make valid packets.  In auto-start mode (default), packets are
-- sent continuously.  Otherwise, user must send start strobe for each packet.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_traffic_sim is
    generic (
    CLK_DELAY   : time := 0 ns;             -- Delay clock signal
    INIT_SEED1  : positive := 1234;         -- PRNG seed (part 1)
    INIT_SEED2  : positive := 5678;         -- PRNG seed (part 2)
    AUTO_START  : boolean := true);         -- Continuous mode?
    port (
    clk         : in  std_logic;            -- Global clock
    reset_p     : in  std_logic;            -- Global reset
    pkt_start   : in  std_logic := '0';     -- Manual packet start strobe
    pkt_len     : in  integer := -1;        -- Override packet length (bytes)
    pkt_etype   : in  boolean := false;     -- If specified, use Ethertype
    pkt_vlan    : in  vlan_hdr_t := VHDR_NONE;  -- Enable VLAN tags?
    mac_dst     : in  unsigned(7 downto 0); -- Destination address (repeat 6x)
    mac_src     : in  unsigned(7 downto 0); -- Source address (repeat 6x)
    out_rate    : in  real := 1.0;          -- Average flow-control rate
    out_port    : out port_rx_m2s;          -- Output data (see switch_types)
    out_bcount  : out natural;              -- Remaining bytes (0 = last)
    out_valid   : out std_logic;            -- Alternate flow control mode
    out_ready   : in  std_logic := '1');    -- Alternate flow-control mode
end eth_traffic_sim;

architecture eth_traffic_sim of eth_traffic_sim is

-- Convenience types used throughout this file.
subtype crc_word_t is std_logic_vector(31 downto 0);
subtype crc_byte_t is unsigned(7 downto 0);
constant CRC_POLY : crc_word_t := x"04C11DB7";

-- Bit-at-a-time CRC32 update function (as described directly).
function crc_next1(prev : crc_word_t; data : crc_byte_t) return crc_word_t is
    variable sreg : crc_word_t := prev;
    variable mask : crc_word_t := (others => '0');
begin
    -- Ethernet convention is LSB-first within each byte.
    for n in 0 to 7 loop
        if (sreg(31) = '1') then
            mask := CRC_POLY;
        else
            mask := (others => '0');
        end if;
        sreg := (sreg(30 downto 0) & data(n)) xor mask;
    end loop;
    return sreg;
end function;

-- Bit-at-a-time CRC32 update function, with optimizations.
function crc_next2(prev : crc_word_t; data : crc_byte_t) return crc_word_t is
    variable sreg : crc_word_t := prev;
    variable mask : crc_word_t := (others => '0');
begin
    -- Ethernet convention is LSB-first within each byte.
    for n in 0 to 7 loop
        mask := (others => data(n) xor sreg(31));
        sreg := (sreg(30 downto 0) & '0') xor (mask and CRC_POLY);
    end loop;
    return sreg;
end function;

signal out_data     : std_logic_vector(7 downto 0) := (others => '0');
signal out_valid_i  : std_logic := '0';
signal out_last     : std_logic := '0';
signal out_bcount_i : natural := 0;

begin

-- Drive each output signal.
out_port.clk        <= clk after CLK_DELAY;
out_port.reset_p    <= reset_p;
out_port.rate       <= get_rate_word(1000);
out_port.status     <= (others => '0');
out_port.tsof       <= (others => '0');
out_port.rxerr      <= '0';
out_port.data       <= out_data;
out_port.write      <= out_valid_i and out_ready;
out_port.last       <= out_last;
out_valid           <= out_valid_i;
out_bcount          <= out_bcount_i;

-- Self-test of CRC algorithm using fixed reference packets.
p_self_test : process
    function flip_bytes(x : crc_word_t) return crc_word_t is
        variable result : crc_word_t;
    begin
        for n in 0 to 3 loop
            for b in 0 to 7 loop
                result(8*n + b) := x(8*n + 7-b);
            end loop;
        end loop;
        return result;
    end function;

    -- Follow the literal definition from IEEE 802.3 standard.
    function crc_literal(pkt : std_logic_vector) return crc_word_t is
        constant NBYTES : natural := pkt'length / 8;
        variable tmp : crc_byte_t;
        variable crc : crc_word_t := (others => '0');
    begin
        -- Update CRC for each byte in the packet.
        for n in NBYTES-1 downto 0 loop
            tmp := unsigned(pkt(8*n+7 downto 8*n));
            if (n >= NBYTES-4) then
                crc := crc_next1(crc, not tmp); -- First four bytes inverted
            else
                crc := crc_next1(crc, tmp);     -- Normal update
            end if;
        end loop;
        -- Flush with zeros = multiply by 2^32.
        for n in 0 to 3 loop
            crc := crc_next1(crc, x"00");
        end loop;
        -- Invert, and flip bit-order within each output byte.
        -- (So the big-endian, LSB-first transmit order is x31, x30, ...)
        return flip_bytes(not crc);
    end function;

    -- Simpler CRC calculation method.
    function crc_simpler(pkt : std_logic_vector) return crc_word_t is
        constant NBYTES : natural := pkt'length / 8;
        variable tmp : crc_byte_t;
        variable crc : crc_word_t := (others => '1');
    begin
        -- Update CRC for each byte in the packet.
        for n in NBYTES-1 downto 0 loop
            tmp := unsigned(pkt(8*n+7 downto 8*n));
            crc := crc_next2(crc, tmp);
        end loop;
        -- Invert, and flip bit-order within each output byte.
        return flip_bytes(not crc);
    end function;

    -- Convert CRC value to hex string.
    function crc_str(crc : crc_word_t) return string is
        variable tmp : natural range 0 to 15;
        variable result : string(1 to 8);
    begin
        for n in 7 downto 0 loop
            tmp := to_integer(unsigned(crc(4*n+3 downto 4*n)));
            case tmp is
                when      0 => result(8-n) := '0';
                when      1 => result(8-n) := '1';
                when      2 => result(8-n) := '2';
                when      3 => result(8-n) := '3';
                when      4 => result(8-n) := '4';
                when      5 => result(8-n) := '5';
                when      6 => result(8-n) := '6';
                when      7 => result(8-n) := '7';
                when      8 => result(8-n) := '8';
                when      9 => result(8-n) := '9';
                when     10 => result(8-n) := 'A';
                when     11 => result(8-n) := 'B';
                when     12 => result(8-n) := 'C';
                when     13 => result(8-n) := 'D';
                when     14 => result(8-n) := 'E';
                when     15 => result(8-n) := 'F';
                when others => result(8-n) := 'X';
            end case;
        end loop;
        return result;
    end function;

    -- Check calculated FCS against expected value.
    -- (Use both methods, to demonstrate they produce the same result.)
    variable test_num : natural := 0;

    procedure ref_check(pkt : std_logic_vector; ref : crc_word_t) is
        variable uut1 : crc_word_t := crc_literal(pkt);
        variable uut2 : crc_word_t := crc_simpler(pkt);
    begin
        test_num := test_num + 1;
        assert (uut1 = ref)
            report "CRC Self-test error (literal) #" & integer'image(test_num)
                & ": Got " & crc_str(uut1) & " expected " & crc_str(ref)
            severity error;
        assert (uut2 = ref)
            report "CRC Self-test error (simpler) #" & integer'image(test_num)
                & ": Got " & crc_str(uut2) & " expected " & crc_str(ref)
            severity error;
    end procedure;

    -- Define each reference packet:
    -- https://www.cl.cam.ac.uk/research/srg/han/ACS-P35/ethercrc/
    constant PKT1 : std_logic_vector(479 downto 0) :=
        x"FFFFFFFFFFFF0020AFB780B8080600010800060400010020" &
        x"AFB780B880E80F9400000000000080E80FDEDEDEDEDEDEDE" &
        x"DEDEDEDEDEDEDEDEDEDEDEDE";
    constant REF1 : crc_word_t := x"9ED2C2AF";

    -- https://electronics.stackexchange.com/questions/170612/fcs-verification-of-ethernet-frame
    constant PKT2 : std_logic_vector(479 downto 0) :=
        x"FFFFFFFFFFFF00000004141308004500002E000000004011" &
        x"7AC000000000FFFFFFFF000050DA00120000424242424242" &
        x"424242424242424242424242";
    constant REF2 : crc_word_t := x"9BF6D0FD";
begin
    -- Check each example packet:
    ref_check(PKT1, REF1);
    ref_check(PKT2, REF2);
    wait;
end process;

-- Data generation.
p_src : process(clk)
    -- Valid range for Ethernet frame length (includes header and CRC).
    constant MIN_FRAME_BYTES : natural := 64;
    constant MAX_FRAME_BYTES : natural := 1522;

    -- Separate PRNG state for data and flow control.
    -- This ensures two units with the same seed generate the same
    -- underlying data sequence even if flow-rate is changed.
    variable dseed1     : positive := INIT_SEED1;
    variable dseed2     : positive := INIT_SEED2;
    variable fseed1     : positive := INIT_SEED1;
    variable fseed2     : positive := INIT_SEED2;
    variable rand       : real := 0.0;

    -- Packet generator state.
    variable pkt_rem    : integer := 0;     -- Remaining bytes
    variable pkt_usr    : integer := 0;     -- User bytes in this packet
    variable pkt_bidx   : integer := 0;     -- Current byte index
    variable pkt_crc    : crc_word_t := (others => '1');
    variable pkt_next   : crc_byte_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Should we begin generating a new packet?
        if (reset_p = '1') then
            pkt_bidx := 0;
            pkt_rem  := 0;
        elsif (pkt_rem = 0 and (AUTO_START or pkt_start = '1')) then
            pkt_bidx := 0;
            pkt_crc  := (others => '1');
            if (pkt_len <= 0) then
                -- Randomize length within valid range.
                uniform(dseed1, dseed2, rand);
                pkt_rem := MIN_FRAME_BYTES + integer(floor(
                    rand * real(MAX_FRAME_BYTES - MIN_FRAME_BYTES)));
            else
                -- Use user-specified length.
                -- (Note: This applies to the inner frame, if VLAN enabled.)
                pkt_rem := pkt_len;
            end if;
            -- Header is 18 bytes --> calculate payload/user field size.
            pkt_usr := pkt_rem - 18;
            -- Add room for VLAN tags?
            if (pkt_vlan /= VHDR_NONE) then
                pkt_rem := pkt_rem + 4;
            end if;
        end if;

        -- Generate new data this clock cycle?
        uniform(fseed1, fseed2, rand);
        if ((pkt_rem > 0) and (rand < out_rate) and
            (out_valid_i = '0' or out_ready = '1')) then
            -- Determine the next output byte.
            if (pkt_bidx < 6) then
                -- Destination MAC address (repeat 6x).
                pkt_next := mac_dst;
            elsif (pkt_bidx < 12) then
                -- Source MAC address (repeat 6x).
                pkt_next := mac_src;
            elsif (pkt_vlan = VHDR_NONE and pkt_bidx < 14) then
                -- Normal packet without 802.1Q tag.
                if (pkt_bidx = 12 and pkt_etype) then
                    -- MSB of Ethertype.
                    pkt_next := x"EE";
                elsif (pkt_bidx = 12) then
                    -- MSB of length.
                    pkt_next := to_unsigned(pkt_usr / 256, 8);
                else
                    -- LSB of length / EtherType
                    pkt_next := to_unsigned(pkt_usr mod 256, 8);
                end if;
            elsif (pkt_vlan /= VHDR_NONE and pkt_bidx < 18) then
                -- Extended header for 802.1Q tag:
                --  * Outer EtherType (aka VID, 2 bytes)
                --  * Tag header (aka TCI, 2 bytes)
                --  * Inner EtherType or Length (2 bytes)
                if (pkt_bidx = 12) then
                    pkt_next := x"81";
                elsif (pkt_bidx = 13) then
                    pkt_next := x"00";
                elsif (pkt_bidx = 14) then
                    pkt_next := unsigned(pkt_vlan(15 downto 8));
                elsif (pkt_bidx = 15) then
                    pkt_next := unsigned(pkt_vlan(7 downto 0));
                elsif (pkt_bidx = 16 and pkt_etype) then
                    pkt_next := x"EE";  -- Should match logic above
                elsif (pkt_bidx = 16) then
                    pkt_next := to_unsigned(pkt_usr / 256, 8);
                else
                    pkt_next := to_unsigned(pkt_usr mod 256, 8);
                end if;
            elsif (pkt_rem <= 4) then
                -- Send the frame-check, most significant byte first.
                -- Note: Each byte is LSB-first, so need to reverse the order.
                for n in 0 to 7 loop
                    pkt_next(n) := not pkt_crc(8*pkt_rem-n-1);
                end loop;
            else
                -- All other fields are random.
                uniform(dseed1, dseed2, rand);
                pkt_next := to_unsigned(integer(floor(rand * 256.0)), 8);
            end if;

            -- Update CRC calculation and byte counters (simpler method).
            if (pkt_rem > 4) then
                -- Regular update after each byte except CRC.
                pkt_crc := crc_next2(pkt_crc, pkt_next);
            end if;
            pkt_bidx := pkt_bidx + 1;
            pkt_rem  := pkt_rem - 1;

            -- Drive all signals in input stream.
            out_data    <= std_logic_vector(pkt_next);
            out_valid_i <= '1';
            out_last    <= bool2bit(pkt_rem = 0);
        elsif (out_ready = '1') then
            out_data    <= (others => '0');
            out_valid_i <= '0';
            out_last    <= '0';
        end if;

        -- External copy of remaining bytes counter.
        out_bcount_i <= pkt_rem;
    end if;
end process;

end eth_traffic_sim;
