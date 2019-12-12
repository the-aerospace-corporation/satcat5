--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Placeholder for the generic scrubbing engine
--
-- This file is a null placeholder for platform-specific cores that provide
-- soft-error detection and scrubbing.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity scrub_generic is
    port (
    clk_raw : in  std_logic;        -- SEM/ICAP clock (See notes above)
    err_out : out std_logic);       -- Strobe on scrub error
end scrub_generic;

architecture placeholder of scrub_generic is

begin

err_out <= '0';

end;
