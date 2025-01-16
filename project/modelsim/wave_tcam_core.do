# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Simple
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/in_data
add wave -noupdate /tcam_core_tb/uut0/in_next
add wave -noupdate /tcam_core_tb/uut0/out_index
add wave -noupdate /tcam_core_tb/uut0/out_found
add wave -noupdate /tcam_core_tb/uut0/out_next
add wave -noupdate /tcam_core_tb/uut0/out_error
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/ref_data
add wave -noupdate /tcam_core_tb/uut0/ref_valid
add wave -noupdate /tcam_core_tb/uut0/cfg_index
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/cfg_data
add wave -noupdate /tcam_core_tb/uut0/cfg_plen
add wave -noupdate /tcam_core_tb/uut0/cfg_valid
add wave -noupdate /tcam_core_tb/uut0/cfg_ready
add wave -noupdate /tcam_core_tb/uut0/cfg_reject
add wave -noupdate /tcam_core_tb/uut0/scan_index
add wave -noupdate /tcam_core_tb/uut0/scan_valid
add wave -noupdate /tcam_core_tb/uut0/scan_ready
add wave -noupdate /tcam_core_tb/uut0/scan_found
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/scan_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/scan_mask
add wave -noupdate -divider {Simple Internals}
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/camrd_masks
add wave -noupdate /tcam_core_tb/uut0/uut/camrd_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/camwr_addr
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/camwr_mask
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/camwr_tval
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/reduce_data
add wave -noupdate /tcam_core_tb/uut0/uut/reduce_mask
add wave -noupdate /tcam_core_tb/uut0/uut/reduce_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/match_data
add wave -noupdate /tcam_core_tb/uut0/uut/match_index
add wave -noupdate /tcam_core_tb/uut0/uut/match_found
add wave -noupdate /tcam_core_tb/uut0/uut/match_type
add wave -noupdate /tcam_core_tb/uut0/uut/match_aux
add wave -noupdate /tcam_core_tb/uut0/uut/match_error
add wave -noupdate /tcam_core_tb/uut0/uut/match_reject
add wave -noupdate /tcam_core_tb/uut0/uut/match_start
add wave -noupdate /tcam_core_tb/uut0/uut/ctrl_state
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/ctrl_pmask
add wave -noupdate /tcam_core_tb/uut0/uut/ctrl_error
add wave -noupdate /tcam_core_tb/uut0/uut/repl_index
add wave -noupdate /tcam_core_tb/uut0/uut/cfg_exec
add wave -noupdate /tcam_core_tb/uut0/uut/cfg_ready_i
add wave -noupdate /tcam_core_tb/uut0/uut/cfg_write
add wave -noupdate /tcam_core_tb/uut0/uut/cfg_reset
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/scan_addr
add wave -noupdate /tcam_core_tb/uut0/uut/scan_match
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/scan_min
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut0/uut/scan_max
add wave -noupdate /tcam_core_tb/uut0/uut/scan_retry
add wave -noupdate /tcam_core_tb/uut0/uut/scan_wait
add wave -noupdate /tcam_core_tb/uut0/uut/scan_done
add wave -noupdate /tcam_core_tb/uut0/uut/scan_next
add wave -noupdate -divider Confirm
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/in_data
add wave -noupdate /tcam_core_tb/uut2/in_next
add wave -noupdate /tcam_core_tb/uut2/out_index
add wave -noupdate /tcam_core_tb/uut2/out_found
add wave -noupdate /tcam_core_tb/uut2/out_next
add wave -noupdate /tcam_core_tb/uut2/out_error
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/ref_data
add wave -noupdate /tcam_core_tb/uut2/ref_valid
add wave -noupdate /tcam_core_tb/uut2/cfg_index
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/cfg_data
add wave -noupdate /tcam_core_tb/uut2/cfg_plen
add wave -noupdate /tcam_core_tb/uut2/cfg_valid
add wave -noupdate /tcam_core_tb/uut2/cfg_ready
add wave -noupdate /tcam_core_tb/uut2/cfg_reject
add wave -noupdate /tcam_core_tb/uut2/scan_index
add wave -noupdate /tcam_core_tb/uut2/scan_valid
add wave -noupdate /tcam_core_tb/uut2/scan_ready
add wave -noupdate /tcam_core_tb/uut2/scan_found
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/scan_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/scan_mask
add wave -noupdate -divider {Confirm Internals}
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/camrd_masks
add wave -noupdate /tcam_core_tb/uut2/uut/camrd_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/camwr_addr
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/camwr_mask
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/camwr_tval
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/reduce_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/reduce_mask
add wave -noupdate /tcam_core_tb/uut2/uut/reduce_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/match_data
add wave -noupdate /tcam_core_tb/uut2/uut/match_index
add wave -noupdate /tcam_core_tb/uut2/uut/match_found
add wave -noupdate /tcam_core_tb/uut2/uut/match_type
add wave -noupdate /tcam_core_tb/uut2/uut/match_aux
add wave -noupdate /tcam_core_tb/uut2/uut/match_error
add wave -noupdate /tcam_core_tb/uut2/uut/match_reject
add wave -noupdate /tcam_core_tb/uut2/uut/match_start
add wave -noupdate /tcam_core_tb/uut2/uut/ctrl_state
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/ctrl_pmask
add wave -noupdate /tcam_core_tb/uut2/uut/ctrl_error
add wave -noupdate /tcam_core_tb/uut2/uut/repl_index
add wave -noupdate /tcam_core_tb/uut2/uut/cfg_exec
add wave -noupdate /tcam_core_tb/uut2/uut/cfg_ready_i
add wave -noupdate /tcam_core_tb/uut2/uut/cfg_write
add wave -noupdate /tcam_core_tb/uut2/uut/cfg_reset
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/scan_addr
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/scan_match
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/scan_min
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut2/uut/scan_max
add wave -noupdate /tcam_core_tb/uut2/uut/scan_retry
add wave -noupdate /tcam_core_tb/uut2/uut/scan_wait
add wave -noupdate /tcam_core_tb/uut2/uut/scan_done
add wave -noupdate /tcam_core_tb/uut2/uut/scan_next
add wave -noupdate -divider ArpCache
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/in_data
add wave -noupdate /tcam_core_tb/uut4/in_next
add wave -noupdate /tcam_core_tb/uut4/out_index
add wave -noupdate /tcam_core_tb/uut4/out_found
add wave -noupdate /tcam_core_tb/uut4/out_next
add wave -noupdate /tcam_core_tb/uut4/out_error
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/ref_data
add wave -noupdate /tcam_core_tb/uut4/ref_valid
add wave -noupdate /tcam_core_tb/uut4/cfg_index
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/cfg_data
add wave -noupdate /tcam_core_tb/uut4/cfg_plen
add wave -noupdate /tcam_core_tb/uut4/cfg_valid
add wave -noupdate /tcam_core_tb/uut4/cfg_ready
add wave -noupdate /tcam_core_tb/uut4/cfg_reject
add wave -noupdate /tcam_core_tb/uut4/scan_index
add wave -noupdate /tcam_core_tb/uut4/scan_valid
add wave -noupdate /tcam_core_tb/uut4/scan_ready
add wave -noupdate /tcam_core_tb/uut4/scan_found
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/scan_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/scan_mask
add wave -noupdate -divider {ArpCache Internals}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/tcam_core_tb/uut4/uut/camrd_masks(0) {-height 15 -radix hexadecimal} /tcam_core_tb/uut4/uut/camrd_masks(1) {-height 15 -radix hexadecimal} /tcam_core_tb/uut4/uut/camrd_masks(2) {-height 15 -radix hexadecimal} /tcam_core_tb/uut4/uut/camrd_masks(3) {-height 15 -radix hexadecimal} /tcam_core_tb/uut4/uut/camrd_masks(4) {-height 15 -radix hexadecimal} /tcam_core_tb/uut4/uut/camrd_masks(5) {-height 15 -radix hexadecimal}} /tcam_core_tb/uut4/uut/camrd_masks
add wave -noupdate /tcam_core_tb/uut4/uut/camrd_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/camwr_addr
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/camwr_mask
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/camwr_tval
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/reduce_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/reduce_mask
add wave -noupdate /tcam_core_tb/uut4/uut/reduce_type
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/match_data
add wave -noupdate /tcam_core_tb/uut4/uut/match_index
add wave -noupdate /tcam_core_tb/uut4/uut/match_found
add wave -noupdate /tcam_core_tb/uut4/uut/match_type
add wave -noupdate /tcam_core_tb/uut4/uut/match_aux
add wave -noupdate /tcam_core_tb/uut4/uut/match_error
add wave -noupdate /tcam_core_tb/uut4/uut/match_reject
add wave -noupdate /tcam_core_tb/uut4/uut/match_start
add wave -noupdate /tcam_core_tb/uut4/uut/ctrl_state
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/ctrl_pmask
add wave -noupdate /tcam_core_tb/uut4/uut/ctrl_error
add wave -noupdate /tcam_core_tb/uut4/uut/repl_index
add wave -noupdate /tcam_core_tb/uut4/uut/cfg_exec
add wave -noupdate /tcam_core_tb/uut4/uut/cfg_ready_i
add wave -noupdate /tcam_core_tb/uut4/uut/cfg_write
add wave -noupdate /tcam_core_tb/uut4/uut/cfg_reset
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/scan_addr
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/scan_match
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/scan_min
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut4/uut/scan_max
add wave -noupdate /tcam_core_tb/uut4/uut/scan_retry
add wave -noupdate /tcam_core_tb/uut4/uut/scan_wait
add wave -noupdate /tcam_core_tb/uut4/uut/scan_done
add wave -noupdate /tcam_core_tb/uut4/uut/scan_next
add wave -noupdate -divider IpRouter
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut6/in_data
add wave -noupdate /tcam_core_tb/uut6/in_next
add wave -noupdate /tcam_core_tb/uut6/out_index
add wave -noupdate /tcam_core_tb/uut6/out_found
add wave -noupdate /tcam_core_tb/uut6/out_next
add wave -noupdate /tcam_core_tb/uut6/out_error
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut6/ref_data
add wave -noupdate /tcam_core_tb/uut6/ref_valid
add wave -noupdate /tcam_core_tb/uut6/cfg_index
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut6/cfg_data
add wave -noupdate /tcam_core_tb/uut6/cfg_plen
add wave -noupdate /tcam_core_tb/uut6/cfg_valid
add wave -noupdate /tcam_core_tb/uut6/cfg_ready
add wave -noupdate /tcam_core_tb/uut6/cfg_reject
add wave -noupdate /tcam_core_tb/uut6/scan_index
add wave -noupdate /tcam_core_tb/uut6/scan_valid
add wave -noupdate /tcam_core_tb/uut6/scan_ready
add wave -noupdate /tcam_core_tb/uut6/scan_found
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut6/scan_data
add wave -noupdate -radix hexadecimal /tcam_core_tb/uut6/scan_mask
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {250629009 ps} 0}
configure wave -namecolwidth 306
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
WaveRestoreZoom {250610245 ps} {250659755 ps}
