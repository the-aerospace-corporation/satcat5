# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {UUT0 (PRBS9)}
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut0/gen_data
add wave -noupdate /prng_lfsr_tb/uut0/gen_valid
add wave -noupdate /prng_lfsr_tb/uut0/gen_ready
add wave -noupdate /prng_lfsr_tb/uut0/gen_write
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut0/sync_local
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut0/sync_rcvd
add wave -noupdate /prng_lfsr_tb/uut0/sync_write
add wave -noupdate /prng_lfsr_tb/uut0/sync_reset
add wave -noupdate /prng_lfsr_tb/uut0/test_count
add wave -noupdate /prng_lfsr_tb/uut0/test_rate
add wave -noupdate /prng_lfsr_tb/uut0/test_reset
add wave -noupdate -divider {UUT1 (PRBS11)}
add wave -noupdate /prng_lfsr_tb/uut1/gen_data
add wave -noupdate /prng_lfsr_tb/uut1/gen_valid
add wave -noupdate /prng_lfsr_tb/uut1/gen_ready
add wave -noupdate /prng_lfsr_tb/uut1/gen_write
add wave -noupdate /prng_lfsr_tb/uut1/sync_local
add wave -noupdate /prng_lfsr_tb/uut1/sync_rcvd
add wave -noupdate /prng_lfsr_tb/uut1/sync_write
add wave -noupdate /prng_lfsr_tb/uut1/sync_reset
add wave -noupdate /prng_lfsr_tb/uut1/test_count
add wave -noupdate /prng_lfsr_tb/uut1/test_rate
add wave -noupdate /prng_lfsr_tb/uut1/test_reset
add wave -noupdate -divider {UUT2 (PRBS23)}
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut2/gen_data
add wave -noupdate /prng_lfsr_tb/uut2/gen_valid
add wave -noupdate /prng_lfsr_tb/uut2/gen_ready
add wave -noupdate /prng_lfsr_tb/uut2/gen_write
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut2/sync_local
add wave -noupdate -radix hexadecimal /prng_lfsr_tb/uut2/sync_rcvd
add wave -noupdate /prng_lfsr_tb/uut2/sync_write
add wave -noupdate /prng_lfsr_tb/uut2/sync_reset
add wave -noupdate /prng_lfsr_tb/uut2/test_count
add wave -noupdate /prng_lfsr_tb/uut2/test_rate
add wave -noupdate /prng_lfsr_tb/uut2/test_reset
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {9895491 ps} 0}
configure wave -namecolwidth 194
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
WaveRestoreZoom {9769810 ps} {10012116 ps}
