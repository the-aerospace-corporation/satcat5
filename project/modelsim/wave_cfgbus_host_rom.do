# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /cfgbus_host_rom_tb/cfg_rdcount
add wave -noupdate /cfgbus_host_rom_tb/cfg_wrcount
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/cfgbus_host_rom_tb/cfg_cmd.clk {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.sysaddr {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.devaddr {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.regaddr {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.wdata {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.wstrb {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.wrcmd {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.rdcmd {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_cmd.reset_p {-radix hexadecimal}} /cfgbus_host_rom_tb/cfg_cmd
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/cfgbus_host_rom_tb/cfg_ack.rdata {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_ack.rdack {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_ack.rderr {-radix hexadecimal} /cfgbus_host_rom_tb/cfg_ack.irq {-radix hexadecimal}} /cfgbus_host_rom_tb/cfg_ack
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /cfgbus_host_rom_tb/uut/rom_addr
add wave -noupdate -radix hexadecimal /cfgbus_host_rom_tb/uut/rom_data
add wave -noupdate /cfgbus_host_rom_tb/uut/cmd_state
add wave -noupdate /cfgbus_host_rom_tb/uut/cmd_write
add wave -noupdate /cfgbus_host_rom_tb/uut/cfg_devaddr
add wave -noupdate /cfgbus_host_rom_tb/uut/cfg_regaddr
add wave -noupdate /cfgbus_host_rom_tb/uut/cfg_wrcmd
add wave -noupdate /cfgbus_host_rom_tb/uut/cfg_rdcmd
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4660704 ps} 0}
configure wave -namecolwidth 260
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {4173644 ps} {5330412 ps}
