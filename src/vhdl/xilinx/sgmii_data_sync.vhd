--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Oversampled data synchronization
--
-- This block accepts a 4x oversampled stream of parallel data. (Four
-- samples per bit, 32 samples per clock.)  It looks for transitions
-- in the data to lock onto the bit timing, then emits exactly eight
-- synchronized data bits per output clock.
--
-- The sampling point is shifted forward or backward by accumulating
-- bit-transition statistics over a fixed-size window.  Jitter may
-- spread transitions across multiple offsets, approaching a 50/50
-- split if the sampling point is aligned with a transition window.
-- Various offsets from to the sample point are illustrated below:
--
-- Legend: | Sampling point (sample A)
--         X Frequent bit transitions (quasi-histogram)
--         = No bit transitions (quasi-histogram)
--
--   A B C D A B C D A B C D A B C D A
--  X|X = = X|X = = X|X = = X|X = = X|X     Very late
--  =|X = = =|X = = =|X = = =|X = = =|X
--  =|X X = =|X X = =|X X = =|X X = =|X     Late
--  =|= X = =|= X = =|= X = =|= X = =|=
--  =|= X X =|= X X =|= X X =|= X X =|=     Optimal
--  =|= = X =|= = X =|= = X =|= = X =|=
--  X|= = X X|= = X X|= = X X|= = X X|=     Early
--  X|= = = X|= = = X|= = = X|= = = X|=
--  X|X = = X|X = = X|X = = X|X = = X|X     Very early
--
-- With the default window size, the tracking loop can tolerate
-- moderate jitter and a reference clock offset up to +/- 80 ppm.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity sgmii_data_sync is
    generic (
    LANE_COUNT      : integer;          -- I/O width (each lane four samples)
    DLY_STEP        : tstamp_t;         -- Sample period for delay compensation
    ENABLE_VOTING   : boolean := true;  -- Enable quasi-majority-vote
    LOCK_THRESH     : integer := 1023;  -- Lock/unlock threshold
    TRACK_LEAKAGE   : integer := 8;     -- Leaky integrator factor (-1 to disable)
    TRACK_SHIFTBIAS : integer := 8;     -- Tracking bias after shift
    TRACK_THRESH    : integer := 24);   -- Tracking-shift threshold
    port (
    -- Input stream (MSB first, N lanes each four samples per bit)
    in_data         : in  std_logic_vector(4*LANE_COUNT-1 downto 0);
    in_next         : in  std_logic;    -- Clock enable
    in_tsof         : in  tstamp_t;     -- Timestamp

    -- Intermediate output, for diagnostic and test only.
    aux_data        : out std_logic_vector(4*LANE_COUNT-1 downto 0);
    aux_next        : out std_logic;
    aux_tsof        : out tstamp_t;

    -- Output stream (MSB first, N bits per clock)
    out_data        : out std_logic_vector(LANE_COUNT-1 downto 0);
    out_next        : out std_logic;
    out_tsof        : out tstamp_t;
    out_locked      : out std_logic;

    -- Clock and reset
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end sgmii_data_sync;

architecture sgmii_data_sync of sgmii_data_sync is

subtype shift_word is std_logic_vector(4*LANE_COUNT-1 downto 0);
subtype output_word is std_logic_vector(LANE_COUNT-1 downto 0);

-- Realigned data stream.
signal in_data_d    : shift_word := (others => '0');
signal in_next_d    : std_logic := '0';
signal in_tsof_d    : tstamp_t := (others => '0');
signal slip_data    : shift_word;
signal slip_next    : std_logic;
signal slip_tsof    : tstamp_t;

-- Detect early/locked/late transition signatures.
subtype DET_SCORE is integer range 0 to LANE_COUNT;
signal det_early2   : DET_SCORE := 0;
signal det_early1   : DET_SCORE := 0;
signal det_ontime   : DET_SCORE := 0;
signal det_late1    : DET_SCORE := 0;
signal det_late2    : DET_SCORE := 0;
signal det_next     : std_logic := '0';

-- Lock / unlock and tracking state machine.
constant TRACK_MAX  : integer := TRACK_THRESH + 4*LANE_COUNT;
signal bias_reg     : std_logic := '0';
signal bias_early   : std_logic := '0';
signal bias_late    : std_logic := '0';
signal trk_locked   : std_logic := '0';
signal trk_early    : std_logic := '0';
signal trk_late     : std_logic := '0';
signal trk_ready    : std_logic;
signal score_track  : integer range -TRACK_MAX to TRACK_MAX := 0;

begin

-- Simple delay register helps with routing and timing.
p_inbuf : process(clk)
begin
    if rising_edge(clk) then
        in_data_d   <= in_data;
        in_next_d   <= in_next;
        in_tsof_d   <= in_tsof;
    end if;
end process;

-- Repeat or drop samples to keep data window aligned as desired.
u_slip : entity work.sgmii_data_slip
    generic map(
    IN_WIDTH    => 4*LANE_COUNT,
    OUT_WIDTH   => 4*LANE_COUNT,
    DLY_STEP    => DLY_STEP)
    port map(
    in_data     => in_data_d,
    in_next     => in_next_d,
    in_tsof     => in_tsof_d,
    out_data    => slip_data,
    out_next    => slip_next,
    out_tsof    => slip_tsof,
    slip_early  => trk_late,    -- Note polarity swap!
    slip_late   => trk_early,   -- Note polarity swap!
    slip_ready  => trk_ready,
    clk         => clk,
    reset_p     => reset_p);

aux_data <= slip_data;  -- Debugging output
aux_next <= slip_next;
aux_tsof <= slip_tsof;

-- Combinational logic needed to keep bias_early flag sync'd to output changes.
bias_early <= bias_reg xnor trk_ready;
bias_late  <= bias_reg xor trk_ready;

-- Select output mode:
gen_voting : if ENABLE_VOTING generate
    -- "Voting" logic makes a decision based on the entire symbol.
    -- This table is largely subjective, but is selected to provide some
    -- tolerance of "runt" pulses caused by pattern-dependent bias.
    -- Certain ambiguous cases incorporate hints from tracking loop, to
    -- effectively gain an extra 1/2-cycle sample-time resolution.
    p_vote : process(clk)
        variable lane_temp : std_logic_vector(3 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            -- Pulse-type lookup table, one for each lane:
            for n in out_data'range loop
                lane_temp := slip_data(4*n+3 downto 4*n);
                case lane_temp is
                    when "0000" => out_data(n) <= '0';  -- Clear '0'
                    when "0001" => out_data(n) <= '0';  -- Clear '0'
                    when "0010" => out_data(n) <= '1';  -- Runt pulse
                    when "0011" => out_data(n) <= bias_early;
                    when "0100" => out_data(n) <= '1';  -- Runt pulse
                    when "0101" => out_data(n) <= bias_late;
                    when "0110" => out_data(n) <= '1';  -- Runt pulse
                    when "0111" => out_data(n) <= '1';  -- Clear '1'
                    when "1000" => out_data(n) <= '0';  -- Clear '0'
                    when "1001" => out_data(n) <= '0';  -- Runt pulse
                    when "1010" => out_data(n) <= bias_early;
                    when "1011" => out_data(n) <= '0';  -- Runt pulse
                    when "1100" => out_data(n) <= bias_late;
                    when "1101" => out_data(n) <= '0';  -- Runt pulse
                    when "1110" => out_data(n) <= '1';  -- Clear '1'
                    when "1111" => out_data(n) <= '1';  -- Clear '1'
                    when others => out_data(n) <= 'X';  -- Simulation only
                end case;
            end loop;
            out_next    <= slip_next;
            out_tsof    <= slip_tsof;
            out_locked  <= trk_locked;
        end if;
    end process;
end generate;

gen_simple : if not ENABLE_VOTING generate
    -- Simple output simply forwards every 4th bit from the realigned stream.
    -- (Combinational logic, no need to spend resources for buffering.)
    gen_lane : for n in out_data'range generate
        out_data(n) <= slip_data(4*n+2);
    end generate;
    out_next    <= slip_next;
    out_tsof    <= slip_tsof;
    out_locked  <= trk_locked;
end generate;

-- Detect transition signatures.
p_detect : process(clk)
    function slv_sum(x : std_logic_vector) return DET_SCORE is
        variable accum : DET_SCORE := 0;
    begin
        for n in x'range loop
            if (x(n) = '1') then
                accum := accum + 1;
            end if;
        end loop;
        return accum;
    end function;

    variable lane_temp   : std_logic_vector(3 downto 0) := (others => '0');
    variable lane_early2 : output_word := (others => '0');
    variable lane_early1 : output_word := (others => '0');
    variable lane_ontime : output_word := (others => '0');
    variable lane_late1  : output_word := (others => '0');
    variable lane_late2  : output_word := (others => '0');
    variable lane_next   : std_logic := '0';
    variable raw_diff    : shift_word := (others => '0');
    variable raw_next, raw_early, raw_late : std_logic := '0';
    variable slip_prev   : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Matched delay for ready signals.
        if (trk_ready = '0' or trk_early = '1' or trk_late = '1') then
            det_next    <= '0';
            lane_next   := '0';
            raw_next    := '0';
        else
            det_next    <= lane_next;
            lane_next   := raw_next;
            raw_next    := slip_next;
        end if;

        -- For each term, calculate sum across all lanes.
        det_early2 <= slv_sum(lane_early2);
        det_early1 <= slv_sum(lane_early1);
        det_ontime <= slv_sum(lane_ontime);
        det_late1  <= slv_sum(lane_late1);
        det_late2  <= slv_sum(lane_late2);

        -- Signature matching for each lane.
        -- In voting mode, goal output is AAAABBBBCCCC --> Change before 0, 4, 8, ...
        -- In sample mode, goal output is xAAAxBBBxCCC --> Change before 0/1, 4/5, ...
        for n in lane_early2'range loop
            lane_temp := raw_diff(4*n+3 downto 4*n);
            if ENABLE_VOTING then
                lane_early2(n) := bool2bit(lane_temp = "0010") and raw_early;  -- 2.0 samps early
                lane_early1(n) := bool2bit(lane_temp = "0100");                 -- 1.0 samps early
                lane_ontime(n) := bool2bit(lane_temp = "1000")
                              or (bool2bit(lane_temp = "0100") and raw_early)
                              or (bool2bit(lane_temp = "0001") and raw_late);
                lane_late1(n)  := bool2bit(lane_temp = "0001");                 -- 1.0 samps late
                lane_late2(n)  := bool2bit(lane_temp = "0010") and raw_late;   -- 2.0 samps late
            else
                lane_early2(n) := bool2bit(lane_temp = "0001");  -- 1.5 samps early
                lane_early1(n) := bool2bit(lane_temp = "1000");  -- 0.5 samps early
                lane_ontime(n) := bool2bit(lane_temp = "1000" or lane_temp = "0100");
                lane_late1(n)  := bool2bit(lane_temp = "0100");  -- 0.5 samps late
                lane_late2(n)  := bool2bit(lane_temp = "0010");  -- 1.5 samps late
            end if;
        end loop;

        -- Compare adjacent samples to detect changes.
        -- (Setting bit N = Change just before that bit in slip_data.)
        for n in raw_diff'range loop
            if (n = slip_data'left) then
                raw_diff(n) := slip_data(n) xor slip_prev;
            else
                raw_diff(n) := slip_data(n) xor slip_data(n+1);
            end if;
        end loop;
        raw_early   := bias_early;
        raw_late    := bias_late;
        slip_prev   := slip_data(0);
    end if;
end process;

-- Lock / unlock and tracking state machine.
p_track : process(clk)
    function LEAK_MAX return integer is
    begin
        if (TRACK_LEAKAGE > 0) then
            return TRACK_MAX / TRACK_LEAKAGE;
        else
            return 0;
        end if;
    end function;
    variable lock_next   : integer range -LANE_COUNT to 4*LANE_COUNT := 0;
    variable track_next  : integer range -2*LANE_COUNT to 2*LANE_COUNT := 0;
    variable track_leak  : integer range -LEAK_MAX to LEAK_MAX := 0;
    variable score_lock  : integer range 0 to LOCK_THRESH := 0;
begin
    if rising_edge(clk) then
        -- Update the lock/unlock state machine.
        if (reset_p = '1') then
            trk_locked <= '0';
            score_lock := 0;
        elsif (score_lock + lock_next < 0) then
            trk_locked <= '0';
            score_lock := 0;
        elsif (score_lock + lock_next > LOCK_THRESH) then
            trk_locked <= '1';
            score_lock := LOCK_THRESH;
        else
            score_lock := score_lock + lock_next;
        end if;

        -- Give a "hint" to voting algorithm if we're trending early or late,
        -- staying synchronized to the actual shift using trk_ready.
        -- (This helps disambiguate certain edge cases.)
        if (trk_early = '1') then
            bias_reg <= '0';
        elsif (trk_late = '1') then
            bias_reg <= '1';
        elsif (trk_ready = '1') then
            bias_reg <= bool2bit(score_track >= 0);
        end if;

        -- Fire the track-early and track-late command strobes.
        if (det_next = '1' and trk_ready = '1' and trk_early = '0' and trk_late = '0') then
            trk_early   <= bool2bit(score_track >  TRACK_THRESH);
            trk_late    <= bool2bit(score_track < -TRACK_THRESH);
        else
            trk_early   <= '0';
            trk_late    <= '0';
        end if;

        -- Accumulate and dump for early/late tracking.
        -- After a shift, give a gentle bias in the opposite direction.
        if (reset_p = '1') then
            score_track <= 0;
        elsif (trk_early = '1') then
            score_track <= -TRACK_SHIFTBIAS;
        elsif (trk_late = '1') then
            score_track <=  TRACK_SHIFTBIAS;
        else
            score_track <= score_track + track_next - track_leak;
        end if;

        -- Figure-of-merit for each accumulator type.
        if (det_next = '1' and trk_early = '0' and trk_late = '0') then
            lock_next := 4*det_ontime - LANE_COUNT;
        else
            lock_next := 0;
        end if;

        if (det_next = '1' and trk_early = '0' and trk_late = '0') then
            track_next := 2*det_early2 + det_early1 - det_late1 - 2*det_late2;
        else
            track_next := 0;
        end if;

        -- Leaky accumulator prevents small bias from causing phase shift.
        -- (Note: Round toward zero, per VHDL integer division spec.)
        if (TRACK_LEAKAGE > 0) then
            track_leak := score_track / TRACK_LEAKAGE;
        else
            track_leak := 0;    -- Disabled
        end if;
    end if;
end process;

end sgmii_data_sync;
