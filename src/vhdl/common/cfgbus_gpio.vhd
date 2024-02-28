--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled general-purpose inputs and outputs
--
-- This block implements GPI, GPO, and GPIO arrays that are controlled
-- by ConfigBus registers.  I/O width is adjustable from 1-32 bits.
--
-- Inputs are assumed to be asynchronous and buffered accordingly.
--
-- cfgbus_gpi: Single register (read-only):
--      Bits 31-00: Read current input value.
--
-- cfgbus_gpo: Single register (read-write):
--      Bits 31-00: Read or set the output value.
--
-- cfgbus_gpio: Three configuration registers:
--      Reg0 = Mode register (read-write)
--          Bits 31-00: Output-enable (0 = In, 1 = Out).
--      Reg1 = Output register (read-write)
--          Bits 31-00: Read or set the output value.
--      Reg2 = Input register (read-only)
--          Bits 31-00: Read current input value.
--
-- Note: THIS FILE DEFINES THREE ENTITIES:
--  cfgbus_gpi, cfgbus_gpo, cfgbus_gpio
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;

entity cfgbus_gpi is
    generic (
    DEVADDR     : integer;
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    GPI_WIDTH   : integer range 1 to CFGBUS_WORD_SIZE := CFGBUS_WORD_SIZE);
    port (
    -- Local interface
    gpi_in      : in  std_logic_vector(GPI_WIDTH-1 downto 0);
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_gpi;

architecture cfgbus_gpi of cfgbus_gpi is

signal gpi_sync : cfgbus_word := (others => '0');

begin

-- Buffer asynchronous inputs.
u_sync : sync_buffer_slv
    generic map(IO_WIDTH => GPI_WIDTH)
    port map(
    in_flag     => gpi_in,
    out_flag    => gpi_sync(GPI_WIDTH-1 downto 0),
    out_clk     => cfg_cmd.clk);

-- Read-only ConfigBus register.
u_reg : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => gpi_sync);

end cfgbus_gpi;

-----------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;

entity cfgbus_gpo is
    generic (
    DEVADDR     : integer;
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    GPO_WIDTH   : integer range 1 to CFGBUS_WORD_SIZE := CFGBUS_WORD_SIZE;
    WR_ATOMIC   : boolean := false);
    port (
    -- Local interface
    gpo_out     : out std_logic_vector(GPO_WIDTH-1 downto 0);
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_gpo;

architecture cfgbus_gpo of cfgbus_gpo is

signal gpo_reg : cfgbus_word;

begin

-- ConfigBus register.
u_reg : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => WR_ATOMIC,
    WR_MASK     => cfgbus_mask_lsb(GPO_WIDTH))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => gpo_reg);

-- Word-size conversion.
gpo_out <= gpo_reg(GPO_WIDTH-1 downto 0);

end cfgbus_gpo;

-----------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;

entity cfgbus_gpio is
    generic (
    DEVADDR     : integer;
    GPIO_WIDTH  : integer range 1 to CFGBUS_WORD_SIZE := CFGBUS_WORD_SIZE;
    WR_ATOMIC   : boolean := false);
    port (
    -- Local interface
    gpio_pads   : inout std_logic_vector(GPIO_WIDTH-1 downto 0);
    -- ConfigBus interface
    cfg_cmd     : in    cfgbus_cmd;
    cfg_ack     : out   cfgbus_ack);
end cfgbus_gpio;

architecture cfgbus_gpio of cfgbus_gpio is

constant REG_MODE   : integer := 0;
constant REG_OUTPUT : integer := 1;
constant REG_INPUT  : integer := 2;

signal gpio_in  : std_logic_vector(GPIO_WIDTH-1 downto 0);
signal gpio_out : cfgbus_word;  -- Output value
signal gpio_oeb : cfgbus_word;  -- Output enable bar

signal gpo_mode : cfgbus_word;  -- Output enable
signal gpi_sync : cfgbus_word := (others => '0');
signal cfg_acks : cfgbus_ack_array(0 to 2);

begin

-- Instantiate each top-level I/O pad and buffer async inputs.
gen_io : for n in 0 to GPIO_WIDTH-1 generate
    u_gpio : bidir_io
        port map(
        io_pin      => gpio_pads(n),
        d_in        => gpio_in(n),
        d_out       => gpio_out(n),
        t_en        => gpio_oeb(n));

    u_sync : sync_buffer
        port map(
        in_flag     => gpio_in(n),
        out_flag    => gpi_sync(n),
        out_clk     => cfg_cmd.clk);
end generate;

-- Set polarity of the output-enable flags.
gpio_oeb <= not gpo_mode;

-- The mode, output, and input registers.
u_reg_mode : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REG_MODE,
    WR_ATOMIC   => WR_ATOMIC,
    WR_MASK     => cfgbus_mask_lsb(GPIO_WIDTH))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(REG_MODE),
    reg_val     => gpo_mode);

u_reg_output : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REG_MODE,
    WR_ATOMIC   => WR_ATOMIC,
    WR_MASK     => cfgbus_mask_lsb(GPIO_WIDTH))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(REG_OUTPUT),
    reg_val     => gpio_out);

u_reg_input : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REG_INPUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(REG_INPUT),
    reg_val     => gpi_sync);

cfg_ack <= cfgbus_merge(cfg_acks);

end cfgbus_gpio;
