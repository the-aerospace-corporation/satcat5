--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- This unit test takes less than 10 microseconds to complete.

library IEEE;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_1164.ALL;

entity aes_gcm_gf_mult_tb is
    -- Testbench top level has no I/O ports.
end aes_gcm_gf_mult_tb;

architecture tb of aes_gcm_gf_mult_tb is

constant clk_period : time := 10 ns;

signal a_128, a_4 : std_logic_vector(127 downto 0)  := x"dc95c078a2408989ad48a21492842087";
signal b_128, b_4 : std_logic_vector(127 downto 0)  := x"cea7403d4d606b6e074ec5d3baf39d18";
signal ab_128, ab_4 : std_logic_vector(127 downto 0);
signal in_val_128, in_val_4 : std_logic := '1';
signal in_rdy_128, in_rdy_4 : std_logic;
signal out_rdy_128, out_rdy_4 : std_logic := '1';
signal out_val_128, out_val_4  : std_logic;
signal in_count_128,  in_count_4  : integer := 0;
signal out_count_128, out_count_4 : integer := 0;
signal err_128, err_4 : std_logic := '0';
signal reset : std_logic := '0';
signal clk   : std_logic := '0';

begin

gf128_instance_128 : entity work.aes_gcm_gf_mult
    generic map(128, true, true, true)
    port map(
    -- in data
    in_data_a   => a_128,
    in_data_b   => b_128,
    in_valid    => in_val_128,
    in_ready    => in_rdy_128,
    -- out data
    out_data_ab => ab_128,
    out_valid   => out_val_128,
    out_ready   => out_rdy_128,
    --system
    reset_p => reset,
    clk     => clk);

gf128_instance_4 : entity work.aes_gcm_gf_mult
    generic map(4, true, true, true)
    port map(
    -- in data
    in_data_a   => a_4,
    in_data_b   => b_4,
    in_valid    => in_val_4,
    in_ready    => in_rdy_4,
    -- out data
    out_data_ab => ab_4,
    out_valid   => out_val_4,
    out_ready   => out_rdy_4,
    --system
    reset_p     => reset,
    clk         => clk);

clk <= not clk after clk_period/2;
out_rdy_128 <= '1';

test_128 : process(clk) is
begin
    if rising_edge(clk) then
        if in_rdy_128 = '1' and in_val_128 = '1' then
            in_count_128 <= in_count_128 + 1;
            in_val_128  <= '1';
            if in_count_128 = 0 then
                a_128 <= x"522dc1f099567d07f47f37a32a84427d";
                b_128 <= x"acbef20579b4b8ebce889bac8732dad7";
            elsif in_count_128 = 1 then
                a_128 <= x"66e94bd4ef8a2c3b884cfa59ca342b2e";
                b_128 <= x"0388dace60b6a392f328c2b971b2fe78";
            elsif in_count_128 = 2 then
                a_128 <= x"ba471e049da20e40495e28e58ca8c555";
                b_128 <= x"b83b533708bf535d0aa6e52980d53b78";
            elsif in_count_128 = 3 then
                b_128 <= x"522dc1f099567d07f47f37a32a84427d";
                a_128 <= x"acbef20579b4b8ebce889bac8732dad7";
            elsif in_count_128 = 4 then
                b_128 <= x"66e94bd4ef8a2c3b884cfa59ca342b2e";
                a_128 <= x"0388dace60b6a392f328c2b971b2fe78";
            elsif in_count_128 = 5 then
                b_128 <= x"ba471e049da20e40495e28e58ca8c555";
                a_128 <= x"b83b533708bf535d0aa6e52980d53b78";
            else
                in_val_128 <= '0';
            end if;
        end if;
        if out_rdy_128 = '1' and out_val_128 = '1' then
            out_count_128 <= out_count_128 + 1;
            if out_count_128 = 0 and ab_128 /= x"fd6ab7586e556dba06d69cfe6223b262" then
                err_128 <= '1';
            elsif (out_count_128 = 1 or out_count_128 = 4) and ab_128 /= x"fcbefb78635d598eddaf982310670f35" then
                err_128 <= '1';
            elsif (out_count_128 = 2 or out_count_128 = 5) and ab_128 /= x"5e2ec746917062882c85b0685353deb7" then
                err_128 <= '1';
            elsif (out_count_128 = 3 or out_count_128 = 6) and ab_128 /= x"b714c9048389afd9f9bc5c1d4378e052" then
                err_128 <= '1';
            end if;
        end if;
        if out_count_128 = 7 then
            out_count_128 <= 0;
            if err_128 = '1' then
                report "Multiplier mismatch with digit size = 128." severity error;
            end if;
            report "GF(2^128) with digit size = 128 is done!";
        end if;
    end if;
end process;

out_rdy_4 <= '1';

test_4 : process(clk) is
begin
    if rising_edge(clk) then
        if in_rdy_4 = '1' and in_val_4 = '1' then
            in_count_4 <= in_count_4 + 1;
            in_val_4  <= '1';
            if in_count_4 = 0 then
                a_4 <= x"522dc1f099567d07f47f37a32a84427d";
                b_4 <= x"acbef20579b4b8ebce889bac8732dad7";
            elsif in_count_4 = 1 then
                a_4 <= x"66e94bd4ef8a2c3b884cfa59ca342b2e";
                b_4 <= x"0388dace60b6a392f328c2b971b2fe78";
            elsif in_count_4 = 2 then
                a_4 <= x"ba471e049da20e40495e28e58ca8c555";
                b_4 <= x"b83b533708bf535d0aa6e52980d53b78";
            elsif in_count_4 = 3 then
                b_4 <= x"522dc1f099567d07f47f37a32a84427d";
                a_4 <= x"acbef20579b4b8ebce889bac8732dad7";
            elsif in_count_4 = 4 then
                b_4 <= x"66e94bd4ef8a2c3b884cfa59ca342b2e";
                a_4 <= x"0388dace60b6a392f328c2b971b2fe78";
            elsif in_count_4 = 5 then
                b_4 <= x"ba471e049da20e40495e28e58ca8c555";
                a_4 <= x"b83b533708bf535d0aa6e52980d53b78";
            else
                in_val_4 <= '0';
            end if;
        end if;
        if out_rdy_4 = '1' and out_val_4 = '1' then
            out_count_4 <= out_count_4 + 1;
            if out_count_4 = 0 and ab_4 /= x"fd6ab7586e556dba06d69cfe6223b262" then
                err_4 <= '1';
            elsif (out_count_4 = 1 or out_count_4 = 4) and ab_4 /= x"fcbefb78635d598eddaf982310670f35" then
                err_128 <= '1';
            elsif (out_count_4 = 2 or out_count_4 = 5) and ab_4 /= x"5e2ec746917062882c85b0685353deb7" then
                err_128 <= '1';
            elsif (out_count_4 = 3 or out_count_4 = 6) and ab_4 /= x"b714c9048389afd9f9bc5c1d4378e052" then
                err_128 <= '1';
            end if;
        end if;
        if out_count_4 = 7 then
            out_count_4 <= 0;
            if err_4 = '1' then
                report "Multiplier mismatch with digit size = 4." severity error;
            end if;
            report "GF(2^128) with digit size = 4 is done!";
        end if;
    end if;
end process;

end tb;
