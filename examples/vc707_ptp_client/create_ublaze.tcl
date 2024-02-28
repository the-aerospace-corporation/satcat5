# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# To make updates easier, this script has minimal edits from the Vivado
# auto-generated TCL script. (File -> Export -> Export Block Design...)
#

# Retain this boilerplate.
variable design_name {vc707_ptp}
variable script_folder [file normalize [file dirname [info script]]]

# ------------------------------------------------------------------------
# Auto-generated script starts here!
# (First few lines must be deleted and replaced with the above.)
# ------------------------------------------------------------------------

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_msg_id "BD_TCL-001" "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_msg_id "BD_TCL-002" "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES:
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_msg_id "BD_TCL-004" "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_msg_id "BD_TCL-005" "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_msg_id "BD_TCL-114" "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\
aero.org:satcat5:cfgbus_gpi:1.0\
aero.org:satcat5:cfgbus_i2c_controller:1.0\
aero.org:satcat5:cfgbus_led:1.0\
aero.org:satcat5:cfgbus_mdio:1.0\
aero.org:satcat5:cfgbus_split:1.0\
aero.org:satcat5:cfgbus_text_lcd:1.0\
aero.org:satcat5:cfgbus_timer:1.0\
aero.org:satcat5:cfgbus_uart:1.0\
xilinx.com:ip:ila:6.2\
aero.org:satcat5:port_mailmap:1.0\
aero.org:satcat5:port_serial_uart_4wire:1.0\
aero.org:satcat5:port_sgmii_raw_gtx:1.0\
aero.org:satcat5:ptp_reference:1.0\
aero.org:satcat5:switch_aux:1.0\
aero.org:satcat5:switch_core:1.0\
aero.org:satcat5:synth_mgt_from_rtc:1.0\
xilinx.com:ip:xlconcat:2.1\
xilinx.com:ip:axi_crossbar:2.1\
aero.org:satcat5:cfgbus_host_axi:1.0\
xilinx.com:ip:mdm:3.2\
xilinx.com:ip:microblaze:11.0\
xilinx.com:ip:axi_intc:4.1\
xilinx.com:ip:proc_sys_reset:5.0\
aero.org:satcat5:ublaze_reset:1.0\
xilinx.com:ip:mig_7series:4.2\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:lmb_bram_if_cntlr:4.0\
xilinx.com:ip:lmb_v10:3.0\
xilinx.com:ip:blk_mem_gen:8.4\
"

   set list_ips_missing ""
   common::send_msg_id "BD_TCL-006" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_msg_id "BD_TCL-115" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "BD_TCL-1003" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}


##################################################################
# MIG PRJ FILE TCL PROCs
##################################################################

proc write_mig_file_vc707_ptp_mig_7series_0_0 { str_mig_prj_filepath } {

   file mkdir [ file dirname "$str_mig_prj_filepath" ]
   set mig_prj_file [open $str_mig_prj_filepath  w+]

   puts $mig_prj_file {﻿<?xml version="1.0" encoding="UTF-8" standalone="no" ?>}
   puts $mig_prj_file {<Project NoOfControllers="1">}
   puts $mig_prj_file {  <!-- IMPORTANT: This is an internal file that has been generated by the MIG software. Any direct editing or changes made to this file may result in unpredictable behavior or data corruption. It is strongly advised that users do not edit the contents of this file. Re-run the MIG GUI with the required settings if any of the options provided below need to be altered. -->}
   puts $mig_prj_file {  <ModuleName>vc707_ptp_mig_7series_0_0</ModuleName>}
   puts $mig_prj_file {  <dci_inouts_inputs>1</dci_inouts_inputs>}
   puts $mig_prj_file {  <dci_inputs>1</dci_inputs>}
   puts $mig_prj_file {  <Debug_En>OFF</Debug_En>}
   puts $mig_prj_file {  <DataDepth_En>1024</DataDepth_En>}
   puts $mig_prj_file {  <LowPower_En>ON</LowPower_En>}
   puts $mig_prj_file {  <XADC_En>Enabled</XADC_En>}
   puts $mig_prj_file {  <TargetFPGA>xc7vx485t-ffg1761/-2</TargetFPGA>}
   puts $mig_prj_file {  <Version>4.2</Version>}
   puts $mig_prj_file {  <SystemClock>Differential</SystemClock>}
   puts $mig_prj_file {  <ReferenceClock>Use System Clock</ReferenceClock>}
   puts $mig_prj_file {  <SysResetPolarity>ACTIVE HIGH</SysResetPolarity>}
   puts $mig_prj_file {  <BankSelectionFlag>FALSE</BankSelectionFlag>}
   puts $mig_prj_file {  <InternalVref>0</InternalVref>}
   puts $mig_prj_file {  <dci_hr_inouts_inputs>50 Ohms</dci_hr_inouts_inputs>}
   puts $mig_prj_file {  <dci_cascade>0</dci_cascade>}
   puts $mig_prj_file {  <Controller number="0">}
   puts $mig_prj_file {    <MemoryDevice>DDR3_SDRAM/SODIMMs/MT8JTF12864HZ-1G6</MemoryDevice>}
   puts $mig_prj_file {    <TimePeriod>1250</TimePeriod>}
   puts $mig_prj_file {    <VccAuxIO>2.0V</VccAuxIO>}
   puts $mig_prj_file {    <PHYRatio>4:1</PHYRatio>}
   puts $mig_prj_file {    <InputClkFreq>200</InputClkFreq>}
   puts $mig_prj_file {    <UIExtraClocks>0</UIExtraClocks>}
   puts $mig_prj_file {    <MMCM_VCO>800</MMCM_VCO>}
   puts $mig_prj_file {    <MMCMClkOut0> 1.000</MMCMClkOut0>}
   puts $mig_prj_file {    <MMCMClkOut1>1</MMCMClkOut1>}
   puts $mig_prj_file {    <MMCMClkOut2>1</MMCMClkOut2>}
   puts $mig_prj_file {    <MMCMClkOut3>1</MMCMClkOut3>}
   puts $mig_prj_file {    <MMCMClkOut4>1</MMCMClkOut4>}
   puts $mig_prj_file {    <DataWidth>64</DataWidth>}
   puts $mig_prj_file {    <DeepMemory>1</DeepMemory>}
   puts $mig_prj_file {    <DataMask>1</DataMask>}
   puts $mig_prj_file {    <ECC>Disabled</ECC>}
   puts $mig_prj_file {    <Ordering>Normal</Ordering>}
   puts $mig_prj_file {    <BankMachineCnt>4</BankMachineCnt>}
   puts $mig_prj_file {    <CustomPart>FALSE</CustomPart>}
   puts $mig_prj_file {    <NewPartName></NewPartName>}
   puts $mig_prj_file {    <RowAddress>14</RowAddress>}
   puts $mig_prj_file {    <ColAddress>10</ColAddress>}
   puts $mig_prj_file {    <BankAddress>3</BankAddress>}
   puts $mig_prj_file {    <MemoryVoltage>1.5V</MemoryVoltage>}
   puts $mig_prj_file {    <C0_MEM_SIZE>1073741824</C0_MEM_SIZE>}
   puts $mig_prj_file {    <UserMemoryAddressMap>BANK_ROW_COLUMN</UserMemoryAddressMap>}
   puts $mig_prj_file {    <PinSelection>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="B21" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[10]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="B17" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[11]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[12]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A21" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[13]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="B19" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A19" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[3]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A17" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[4]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[5]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="D20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[6]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C18" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[7]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="D17" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[8]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C19" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_addr[9]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="D21" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ba[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C21" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ba[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="D18" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ba[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="K17" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_cas_n"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15" PADName="G18" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ck_n[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15" PADName="H19" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ck_p[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="K19" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_cke[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="J17" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_cs_n[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="M13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="K15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="F12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="A14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[3]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C23" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[4]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="D25" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[5]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="C31" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[6]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="F31" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dm[7]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="N14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="H13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[10]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="J13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[11]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="L16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[12]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="L15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[13]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="H14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[14]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="J15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[15]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[16]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[17]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[18]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[19]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="N13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="G13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[20]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="G12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[21]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[22]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="G14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[23]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[24]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[25]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[26]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[27]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[28]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[29]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="L14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[30]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[31]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A24" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[32]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B23" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[33]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B27" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[34]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B26" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[35]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A22" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[36]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B22" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[37]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A25" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[38]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C24" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[39]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="M14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[3]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E24" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[40]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D23" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[41]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D26" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[42]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C25" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[43]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E23" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[44]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D22" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[45]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F22" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[46]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E22" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[47]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A30" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[48]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D27" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[49]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="M12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[4]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A29" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[50]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C28" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[51]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D28" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[52]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="B31" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[53]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A31" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[54]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="A32" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[55]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E30" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[56]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F29" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[57]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F30" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[58]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F27" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[59]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="N15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[5]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="C30" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[60]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="E29" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[61]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="F26" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[62]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="D30" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[63]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="M11" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[6]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="L12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[7]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="K14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[8]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15_T_DCI" PADName="K13" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dq[9]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="M16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="J12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="G16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="C14" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[3]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="A27" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[4]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="E25" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[5]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="B29" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[6]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="E28" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_n[7]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="N16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="K12" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="H16" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="C15" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[3]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="A26" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[4]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="F25" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[5]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="B28" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[6]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="DIFF_SSTL15_T_DCI" PADName="E27" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_dqs_p[7]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="H20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_odt[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="E20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_ras_n"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="LVCMOS15" PADName="C29" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_reset_n"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="SSTL15" PADName="F20" SLEW="FAST" VCCAUX_IO="HIGH" name="ddr3_we_n"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="LVCMOS18" PADName="AM39" SLEW="SLOW" VCCAUX_IO="" name="led[0]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="LVCMOS18" PADName="AN39" SLEW="SLOW" VCCAUX_IO="" name="led[1]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="LVCMOS18" PADName="AR37" SLEW="SLOW" VCCAUX_IO="" name="led[2]"/>}
   puts $mig_prj_file {      <Pin IN_TERM="" IOSTANDARD="LVCMOS18" PADName="AT37" SLEW="SLOW" VCCAUX_IO="" name="led[3]"/>}
   puts $mig_prj_file {    </PinSelection>}
   puts $mig_prj_file {    <System_Clock>}
   puts $mig_prj_file {      <Pin Bank="38" PADName="E19/E18(CC_P/N)" name="sys_clk_p/n"/>}
   puts $mig_prj_file {    </System_Clock>}
   puts $mig_prj_file {    <System_Control>}
   puts $mig_prj_file {      <Pin Bank="Select Bank" PADName="No connect" name="sys_rst"/>}
   puts $mig_prj_file {      <Pin Bank="Select Bank" PADName="No connect" name="init_calib_complete"/>}
   puts $mig_prj_file {      <Pin Bank="Select Bank" PADName="No connect" name="tg_compare_error"/>}
   puts $mig_prj_file {    </System_Control>}
   puts $mig_prj_file {    <TimingParameters>}
   puts $mig_prj_file {      <Parameters tcke="5" tfaw="30" tras="35" trcd="13.75" trefi="7.8" trfc="110" trp="13.75" trrd="6" trtp="7.5" twtr="7.5"/>}
   puts $mig_prj_file {    </TimingParameters>}
   puts $mig_prj_file {    <mrBurstLength name="Burst Length">8 - Fixed</mrBurstLength>}
   puts $mig_prj_file {    <mrBurstType name="Read Burst Type and Length">Sequential</mrBurstType>}
   puts $mig_prj_file {    <mrCasLatency name="CAS Latency">11</mrCasLatency>}
   puts $mig_prj_file {    <mrMode name="Mode">Normal</mrMode>}
   puts $mig_prj_file {    <mrDllReset name="DLL Reset">No</mrDllReset>}
   puts $mig_prj_file {    <mrPdMode name="DLL control for precharge PD">Slow Exit</mrPdMode>}
   puts $mig_prj_file {    <emrDllEnable name="DLL Enable">Enable</emrDllEnable>}
   puts $mig_prj_file {    <emrOutputDriveStrength name="Output Driver Impedance Control">RZQ/7</emrOutputDriveStrength>}
   puts $mig_prj_file {    <emrMirrorSelection name="Address Mirroring">Disable</emrMirrorSelection>}
   puts $mig_prj_file {    <emrCSSelection name="Controller Chip Select Pin">Enable</emrCSSelection>}
   puts $mig_prj_file {    <emrRTT name="RTT (nominal) - On Die Termination (ODT)">RZQ/4</emrRTT>}
   puts $mig_prj_file {    <emrPosted name="Additive Latency (AL)">0</emrPosted>}
   puts $mig_prj_file {    <emrOCD name="Write Leveling Enable">Disabled</emrOCD>}
   puts $mig_prj_file {    <emrDQS name="TDQS enable">Enabled</emrDQS>}
   puts $mig_prj_file {    <emrRDQS name="Qoff">Output Buffer Enabled</emrRDQS>}
   puts $mig_prj_file {    <mr2PartialArraySelfRefresh name="Partial-Array Self Refresh">Full Array</mr2PartialArraySelfRefresh>}
   puts $mig_prj_file {    <mr2CasWriteLatency name="CAS write latency">8</mr2CasWriteLatency>}
   puts $mig_prj_file {    <mr2AutoSelfRefresh name="Auto Self Refresh">Enabled</mr2AutoSelfRefresh>}
   puts $mig_prj_file {    <mr2SelfRefreshTempRange name="High Temparature Self Refresh Rate">Normal</mr2SelfRefreshTempRange>}
   puts $mig_prj_file {    <mr2RTTWR name="RTT_WR - Dynamic On Die Termination (ODT)">Dynamic ODT off</mr2RTTWR>}
   puts $mig_prj_file {    <PortInterface>AXI</PortInterface>}
   puts $mig_prj_file {    <AXIParameters>}
   puts $mig_prj_file {      <C0_C_RD_WR_ARB_ALGORITHM>RD_PRI_REG</C0_C_RD_WR_ARB_ALGORITHM>}
   puts $mig_prj_file {      <C0_S_AXI_ADDR_WIDTH>30</C0_S_AXI_ADDR_WIDTH>}
   puts $mig_prj_file {      <C0_S_AXI_DATA_WIDTH>256</C0_S_AXI_DATA_WIDTH>}
   puts $mig_prj_file {      <C0_S_AXI_ID_WIDTH>4</C0_S_AXI_ID_WIDTH>}
   puts $mig_prj_file {      <C0_S_AXI_SUPPORTS_NARROW_BURST>0</C0_S_AXI_SUPPORTS_NARROW_BURST>}
   puts $mig_prj_file {    </AXIParameters>}
   puts $mig_prj_file {  </Controller>}
   puts $mig_prj_file {</Project>}

   close $mig_prj_file
}
# End of write_mig_file_vc707_ptp_mig_7series_0_0()



##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: microblaze_0_local_memory
proc create_hier_cell_microblaze_0_local_memory { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_msg_id "BD_TCL-102" "ERROR" "create_hier_cell_microblaze_0_local_memory() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB

  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB


  # Create pins
  create_bd_pin -dir I -type clk LMB_Clk
  create_bd_pin -dir I -type rst SYS_Rst

  # Create instance: dlmb_bram_if_cntlr, and set properties
  set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 dlmb_bram_if_cntlr ]
  set_property -dict [ list \
   CONFIG.C_ECC {0} \
 ] $dlmb_bram_if_cntlr

  # Create instance: dlmb_v10, and set properties
  set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 dlmb_v10 ]

  # Create instance: ilmb_bram_if_cntlr, and set properties
  set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 ilmb_bram_if_cntlr ]
  set_property -dict [ list \
   CONFIG.C_ECC {0} \
 ] $ilmb_bram_if_cntlr

  # Create instance: ilmb_v10, and set properties
  set ilmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 ilmb_v10 ]

  # Create instance: lmb_bram, and set properties
  set lmb_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 lmb_bram ]
  set_property -dict [ list \
   CONFIG.Memory_Type {True_Dual_Port_RAM} \
   CONFIG.use_bram_block {BRAM_Controller} \
 ] $lmb_bram

  # Create interface connections
  connect_bd_intf_net -intf_net microblaze_0_dlmb [get_bd_intf_pins DLMB] [get_bd_intf_pins dlmb_v10/LMB_M]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_bus [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB] [get_bd_intf_pins dlmb_v10/LMB_Sl_0]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_cntlr [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net microblaze_0_ilmb [get_bd_intf_pins ILMB] [get_bd_intf_pins ilmb_v10/LMB_M]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_bus [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB] [get_bd_intf_pins ilmb_v10/LMB_Sl_0]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_cntlr [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

  # Create port connections
  connect_bd_net -net SYS_Rst_1 [get_bd_pins SYS_Rst] [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst] [get_bd_pins dlmb_v10/SYS_Rst] [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst] [get_bd_pins ilmb_v10/SYS_Rst]
  connect_bd_net -net microblaze_0_Clk [get_bd_pins LMB_Clk] [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] [get_bd_pins dlmb_v10/LMB_Clk] [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk] [get_bd_pins ilmb_v10/LMB_Clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: ublaze0
proc create_hier_cell_ublaze0 { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_msg_id "BD_TCL-102" "ERROR" "create_hier_cell_ublaze0() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:ConfigBus_rtl:1.0 CfgBus

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr3

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk


  # Create pins
  create_bd_pin -dir I clk_125
  create_bd_pin -dir I -type rst cpu_reset
  create_bd_pin -dir I emc_clk
  create_bd_pin -dir I -from 0 -to 0 ext_clk_detect
  create_bd_pin -dir I -type rst mig_reset
  create_bd_pin -dir O -type rst reset_n
  create_bd_pin -dir O -from 0 -to 0 -type rst reset_p
  create_bd_pin -dir I -type rst wdog_resetp

  # Create instance: axi_crossbar_0, and set properties
  set axi_crossbar_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_crossbar:2.1 axi_crossbar_0 ]
  set_property -dict [ list \
   CONFIG.CONNECTIVITY_MODE {SASD} \
   CONFIG.NUM_MI {3} \
   CONFIG.PROTOCOL {AXI4LITE} \
   CONFIG.R_REGISTER {1} \
   CONFIG.S00_SINGLE_THREAD {1} \
 ] $axi_crossbar_0

  # Create instance: cfgbus_host_axi_0, and set properties
  set cfgbus_host_axi_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_host_axi:1.0 cfgbus_host_axi_0 ]

  # Create instance: ila_reset, and set properties
  set ila_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_reset ]
  set_property -dict [ list \
   CONFIG.ALL_PROBE_SAME_MU {true} \
   CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
   CONFIG.C_ENABLE_ILA_AXI_MON {false} \
   CONFIG.C_EN_STRG_QUAL {1} \
   CONFIG.C_INPUT_PIPE_STAGES {2} \
   CONFIG.C_MONITOR_TYPE {Native} \
   CONFIG.C_NUM_OF_PROBES {10} \
 ] $ila_reset

  # Create instance: mdm_1, and set properties
  set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm:3.2 mdm_1 ]
  set_property -dict [ list \
   CONFIG.C_ADDR_SIZE {32} \
   CONFIG.C_M_AXI_ADDR_WIDTH {32} \
   CONFIG.C_USE_UART {1} \
 ] $mdm_1

  # Create instance: microblaze_0, and set properties
  set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0 ]
  set_property -dict [ list \
   CONFIG.C_DEBUG_ENABLED {1} \
   CONFIG.C_D_AXI {1} \
   CONFIG.C_D_LMB {1} \
   CONFIG.C_I_AXI {0} \
   CONFIG.C_I_LMB {1} \
   CONFIG.C_USE_BARREL {1} \
   CONFIG.C_USE_DIV {1} \
   CONFIG.C_USE_FPU {2} \
   CONFIG.C_USE_HW_MUL {2} \
 ] $microblaze_0

  # Create instance: microblaze_0_axi_intc, and set properties
  set microblaze_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 microblaze_0_axi_intc ]
  set_property -dict [ list \
   CONFIG.C_HAS_FAST {1} \
 ] $microblaze_0_axi_intc

  # Create instance: microblaze_0_axi_periph, and set properties
  set microblaze_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 microblaze_0_axi_periph ]
  set_property -dict [ list \
   CONFIG.M00_HAS_DATA_FIFO {2} \
   CONFIG.M00_HAS_REGSLICE {3} \
   CONFIG.M01_HAS_DATA_FIFO {0} \
   CONFIG.M01_HAS_REGSLICE {3} \
   CONFIG.NUM_MI {2} \
   CONFIG.S00_HAS_DATA_FIFO {0} \
 ] $microblaze_0_axi_periph

  # Create instance: microblaze_0_local_memory
  create_hier_cell_microblaze_0_local_memory $hier_obj microblaze_0_local_memory

  # Create instance: microblaze_0_reset0, and set properties
  set microblaze_0_reset0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 microblaze_0_reset0 ]
  set_property -dict [ list \
   CONFIG.C_AUX_RESET_HIGH {1} \
 ] $microblaze_0_reset0

  # Create instance: microblaze_0_reset1, and set properties
  set microblaze_0_reset1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:ublaze_reset:1.0 microblaze_0_reset1 ]

  # Create instance: microblaze_0_xlconcat, and set properties
  set microblaze_0_xlconcat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 microblaze_0_xlconcat ]
  set_property -dict [ list \
   CONFIG.NUM_PORTS {2} \
 ] $microblaze_0_xlconcat

  # Create instance: mig_7series_0, and set properties
  set mig_7series_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_7series_0 ]

  # Generate the PRJ File for MIG
  set str_mig_folder [get_property IP_DIR [ get_ips [ get_property CONFIG.Component_Name $mig_7series_0 ] ] ]
  set str_mig_file_name vc707_mig.prj
  set str_mig_file_path ${str_mig_folder}/${str_mig_file_name}

  write_mig_file_vc707_ptp_mig_7series_0_0 $str_mig_file_path

  set_property -dict [ list \
   CONFIG.BOARD_MIG_PARAM {Custom} \
   CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
   CONFIG.RESET_BOARD_INTERFACE {Custom} \
   CONFIG.XML_INPUT_FILE {vc707_mig.prj} \
 ] $mig_7series_0

  # Create instance: util_vector_logic_0, and set properties
  set util_vector_logic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0 ]
  set_property -dict [ list \
   CONFIG.C_OPERATION {not} \
   CONFIG.C_SIZE {1} \
   CONFIG.LOGO_FILE {data/sym_notgate.png} \
 ] $util_vector_logic_0

  # Create instance: util_vector_logic_1, and set properties
  set util_vector_logic_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_1 ]
  set_property -dict [ list \
   CONFIG.C_OPERATION {or} \
   CONFIG.C_SIZE {1} \
   CONFIG.LOGO_FILE {data/sym_orgate.png} \
 ] $util_vector_logic_1

  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins CfgBus] [get_bd_intf_pins cfgbus_host_axi_0/Cfg]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins ddr3] [get_bd_intf_pins mig_7series_0/DDR3]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins sys_clk] [get_bd_intf_pins mig_7series_0/SYS_CLK]
  connect_bd_intf_net -intf_net axi_crossbar_0_M00_AXI [get_bd_intf_pins axi_crossbar_0/M00_AXI] [get_bd_intf_pins microblaze_0_axi_intc/s_axi]
  connect_bd_intf_net -intf_net axi_crossbar_0_M01_AXI [get_bd_intf_pins axi_crossbar_0/M01_AXI] [get_bd_intf_pins cfgbus_host_axi_0/CtrlAxi]
  connect_bd_intf_net -intf_net axi_crossbar_0_M02_AXI [get_bd_intf_pins axi_crossbar_0/M02_AXI] [get_bd_intf_pins mdm_1/S_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_dp [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins microblaze_0_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M00_AXI [get_bd_intf_pins microblaze_0_axi_periph/M00_AXI] [get_bd_intf_pins mig_7series_0/S_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M01_AXI [get_bd_intf_pins axi_crossbar_0/S00_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M01_AXI]
  connect_bd_intf_net -intf_net microblaze_0_debug [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_1 [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins microblaze_0_local_memory/DLMB]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_1 [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins microblaze_0_local_memory/ILMB]
  connect_bd_intf_net -intf_net microblaze_0_interrupt [get_bd_intf_pins microblaze_0/INTERRUPT] [get_bd_intf_pins microblaze_0_axi_intc/interrupt]

  # Create port connections
  connect_bd_net -net M00_ACLK_1 [get_bd_pins microblaze_0_axi_periph/M00_ACLK] [get_bd_pins microblaze_0_reset0/slowest_sync_clk] [get_bd_pins mig_7series_0/ui_clk]
  connect_bd_net -net SYS_Rst_1 [get_bd_pins microblaze_0_local_memory/SYS_Rst] [get_bd_pins microblaze_0_reset1/bus_struct_reset]
  connect_bd_net -net cfgbus_host_axi_0_irq_out [get_bd_pins cfgbus_host_axi_0/irq_out] [get_bd_pins microblaze_0_xlconcat/In0]
  connect_bd_net -net cpu_reset [get_bd_pins cpu_reset] [get_bd_pins ila_reset/probe9] [get_bd_pins util_vector_logic_1/Op1]
  connect_bd_net -net emc_clk_1 [get_bd_pins emc_clk] [get_bd_pins ila_reset/clk]
  connect_bd_net -net ext_clk_detect [get_bd_pins ext_clk_detect] [get_bd_pins ila_reset/probe8]
  connect_bd_net -net mb_aresetn [get_bd_pins axi_crossbar_0/aresetn] [get_bd_pins cfgbus_host_axi_0/axi_aresetn] [get_bd_pins ila_reset/probe6] [get_bd_pins mdm_1/S_AXI_ARESETN] [get_bd_pins microblaze_0_axi_intc/s_axi_aresetn] [get_bd_pins microblaze_0_axi_periph/ARESETN] [get_bd_pins microblaze_0_axi_periph/M01_ARESETN] [get_bd_pins microblaze_0_axi_periph/S00_ARESETN] [get_bd_pins microblaze_0_reset0/ext_reset_in] [get_bd_pins microblaze_0_reset1/interconnect_aresetn]
  connect_bd_net -net mb_peripheral_reset [get_bd_pins reset_p] [get_bd_pins ila_reset/probe7] [get_bd_pins microblaze_0_reset1/peripheral_reset]
  connect_bd_net -net mb_reset [get_bd_pins ila_reset/probe5] [get_bd_pins microblaze_0/Reset] [get_bd_pins microblaze_0_axi_intc/processor_rst] [get_bd_pins microblaze_0_reset1/mb_reset]
  connect_bd_net -net mdm_1_Interrupt [get_bd_pins mdm_1/Interrupt] [get_bd_pins microblaze_0_xlconcat/In1]
  connect_bd_net -net mdm_1_debug_rst [get_bd_pins ila_reset/probe4] [get_bd_pins mdm_1/Debug_SYS_Rst] [get_bd_pins microblaze_0_reset1/mb_debug_sys_rst]
  connect_bd_net -net microblaze_0_reset1_peripheral_aresetn [get_bd_pins reset_n] [get_bd_pins microblaze_0_reset1/peripheral_aresetn]
  connect_bd_net -net microblaze_0_xlconcat_dout [get_bd_pins microblaze_0_axi_intc/intr] [get_bd_pins microblaze_0_xlconcat/dout]
  connect_bd_net -net mig_aresetn [get_bd_pins ila_reset/probe3] [get_bd_pins microblaze_0_axi_periph/M00_ARESETN] [get_bd_pins microblaze_0_reset0/interconnect_aresetn] [get_bd_pins mig_7series_0/aresetn]
  connect_bd_net -net mig_mmcm_locked [get_bd_pins ila_reset/probe2] [get_bd_pins microblaze_0_reset0/dcm_locked] [get_bd_pins microblaze_0_reset1/dcm_locked] [get_bd_pins mig_7series_0/mmcm_locked]
  connect_bd_net -net mig_reset [get_bd_pins mig_reset] [get_bd_pins ila_reset/probe0] [get_bd_pins mig_7series_0/sys_rst] [get_bd_pins util_vector_logic_0/Op1]
  connect_bd_net -net slowest_sync_clk_0_1 [get_bd_pins clk_125] [get_bd_pins axi_crossbar_0/aclk] [get_bd_pins cfgbus_host_axi_0/axi_clk] [get_bd_pins mdm_1/S_AXI_ACLK] [get_bd_pins microblaze_0/Clk] [get_bd_pins microblaze_0_axi_intc/processor_clk] [get_bd_pins microblaze_0_axi_intc/s_axi_aclk] [get_bd_pins microblaze_0_axi_periph/ACLK] [get_bd_pins microblaze_0_axi_periph/M01_ACLK] [get_bd_pins microblaze_0_axi_periph/S00_ACLK] [get_bd_pins microblaze_0_local_memory/LMB_Clk] [get_bd_pins microblaze_0_reset1/slowest_sync_clk]
  connect_bd_net -net util_vector_logic_0_Res [get_bd_pins microblaze_0_reset1/ext_reset_in] [get_bd_pins util_vector_logic_0/Res]
  connect_bd_net -net util_vector_logic_1_Res [get_bd_pins microblaze_0_reset1/aux_reset_in] [get_bd_pins util_vector_logic_1/Res]
  connect_bd_net -net wdog_resetp [get_bd_pins wdog_resetp] [get_bd_pins ila_reset/probe1] [get_bd_pins util_vector_logic_1/Op2]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set ddr3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr3 ]

  set fmc_ref [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 fmc_ref ]

  set mgt_ref [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 mgt_ref ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
   ] $mgt_ref

  set sgmii_rj45 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_rj45 ]

  set sgmii_sfp [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_sfp ]

  set sgmii_sma [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_sma ]

  set sys_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk ]

  set text_lcd [ create_bd_intf_port -mode Master -vlnv aero.org:satcat5:TextLCD_rtl:1.0 text_lcd ]


  # Create ports
  set cpu_reset [ create_bd_port -dir I -type rst cpu_reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $cpu_reset
  set dip_sw [ create_bd_port -dir I -from 7 -to 0 dip_sw ]
  set emc_clk [ create_bd_port -dir I -type clk emc_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {80000000} \
 ] $emc_clk
  set fmc_synth_n [ create_bd_port -dir O -from 3 -to 0 fmc_synth_n ]
  set fmc_synth_p [ create_bd_port -dir O -from 3 -to 0 fmc_synth_p ]
  set phy_mdio_sck [ create_bd_port -dir O phy_mdio_sck ]
  set phy_mdio_sda [ create_bd_port -dir IO phy_mdio_sda ]
  set pushbtn [ create_bd_port -dir I -from 7 -to 0 pushbtn ]
  set sfp_enable [ create_bd_port -dir O -type rst sfp_enable ]
  set sfp_i2c_sck [ create_bd_port -dir IO sfp_i2c_sck ]
  set sfp_i2c_sda [ create_bd_port -dir IO sfp_i2c_sda ]
  set status_led [ create_bd_port -dir O -from 7 -to 0 status_led ]
  set usb_cts_n [ create_bd_port -dir I usb_cts_n ]
  set usb_rts_n [ create_bd_port -dir O usb_rts_n ]
  set usb_rxd [ create_bd_port -dir I usb_rxd ]
  set usb_txd [ create_bd_port -dir O usb_txd ]

  # Create instance: cfgbus_gpi_0, and set properties
  set cfgbus_gpi_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_gpi:1.0 cfgbus_gpi_0 ]
  set_property -dict [ list \
   CONFIG.DEV_ADDR {10} \
   CONFIG.GPI_WIDTH {18} \
 ] $cfgbus_gpi_0

  # Create instance: cfgbus_i2c_controller_0, and set properties
  set cfgbus_i2c_controller_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_i2c_controller:1.0 cfgbus_i2c_controller_0 ]
  set_property -dict [ list \
   CONFIG.DEV_ADDR {4} \
 ] $cfgbus_i2c_controller_0

  # Create instance: cfgbus_led_0, and set properties
  set cfgbus_led_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_led:1.0 cfgbus_led_0 ]
  set_property -dict [ list \
   CONFIG.DEV_ADDR {7} \
   CONFIG.LED_COUNT {8} \
 ] $cfgbus_led_0

  # Create instance: cfgbus_mdio_0, and set properties
  set cfgbus_mdio_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_mdio:1.0 cfgbus_mdio_0 ]
  set_property -dict [ list \
   CONFIG.CLKREF_HZ {125000000} \
   CONFIG.DEV_ADDR {6} \
 ] $cfgbus_mdio_0

  # Create instance: cfgbus_split_0, and set properties
  set cfgbus_split_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_split:1.0 cfgbus_split_0 ]
  set_property -dict [ list \
   CONFIG.DLY_BUFFER {true} \
   CONFIG.PORT_COUNT {11} \
 ] $cfgbus_split_0

  # Create instance: cfgbus_text_lcd_0, and set properties
  set cfgbus_text_lcd_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_text_lcd:1.0 cfgbus_text_lcd_0 ]
  set_property -dict [ list \
   CONFIG.CFG_CLK_HZ {125000000} \
   CONFIG.DEV_ADDR {9} \
 ] $cfgbus_text_lcd_0

  # Create instance: cfgbus_timer_0, and set properties
  set cfgbus_timer_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_timer:1.0 cfgbus_timer_0 ]
  set_property -dict [ list \
   CONFIG.CFG_CLK_HZ {125000000} \
   CONFIG.DEV_ADDR {5} \
   CONFIG.EVT_ENABLE {false} \
   CONFIG.TMR_ENABLE {true} \
 ] $cfgbus_timer_0

  # Create instance: cfgbus_uart_0, and set properties
  set cfgbus_uart_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_uart:1.0 cfgbus_uart_0 ]
  set_property -dict [ list \
   CONFIG.DEV_ADDR {8} \
 ] $cfgbus_uart_0

  # Create instance: ila_synth, and set properties
  set ila_synth [ create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_synth ]
  set_property -dict [ list \
   CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
   CONFIG.C_ENABLE_ILA_AXI_MON {false} \
   CONFIG.C_EN_STRG_QUAL {1} \
   CONFIG.C_INPUT_PIPE_STAGES {2} \
   CONFIG.C_MONITOR_TYPE {Native} \
   CONFIG.C_NUM_OF_PROBES {4} \
   CONFIG.C_PROBE0_MU_CNT {2} \
   CONFIG.C_PROBE0_WIDTH {8} \
   CONFIG.C_PROBE1_MU_CNT {2} \
   CONFIG.C_PROBE1_WIDTH {48} \
   CONFIG.C_PROBE2_MU_CNT {2} \
   CONFIG.C_PROBE3_MU_CNT {2} \
 ] $ila_synth

  # Create instance: port_mailmap, and set properties
  set port_mailmap [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_mailmap:1.0 port_mailmap ]
  set_property -dict [ list \
   CONFIG.CFG_CLK_HZ {125000000} \
   CONFIG.DEV_ADDR {2} \
   CONFIG.PTP_ENABLE {true} \
   CONFIG.PTP_REF_HZ {125000000} \
 ] $port_mailmap

  # Create instance: port_serial_uart, and set properties
  set port_serial_uart [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_uart_4wire:1.0 port_serial_uart ]
  set_property -dict [ list \
   CONFIG.CFG_DEV_ADDR {3} \
   CONFIG.CFG_ENABLE {true} \
   CONFIG.CLKREF_HZ {125000000} \
 ] $port_serial_uart

  # Create instance: port_sgmii_raw_gtx_0, and set properties
  set port_sgmii_raw_gtx_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_sgmii_raw_gtx:1.0 port_sgmii_raw_gtx_0 ]
  set_property -dict [ list \
   CONFIG.PTP_ENABLE {true} \
   CONFIG.PTP_REF_HZ {125000000} \
 ] $port_sgmii_raw_gtx_0

  # Create instance: port_sgmii_raw_gtx_1, and set properties
  set port_sgmii_raw_gtx_1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_sgmii_raw_gtx:1.0 port_sgmii_raw_gtx_1 ]
  set_property -dict [ list \
   CONFIG.PTP_ENABLE {true} \
   CONFIG.PTP_REF_HZ {125000000} \
   CONFIG.SHARED_EN {false} \
 ] $port_sgmii_raw_gtx_1

  # Create instance: port_sgmii_raw_gtx_2, and set properties
  set port_sgmii_raw_gtx_2 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_sgmii_raw_gtx:1.0 port_sgmii_raw_gtx_2 ]
  set_property -dict [ list \
   CONFIG.PTP_ENABLE {true} \
   CONFIG.PTP_REF_HZ {125000000} \
   CONFIG.SHARED_EN {false} \
 ] $port_sgmii_raw_gtx_2

  # Create instance: ptp_reference_0, and set properties
  set ptp_reference_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:ptp_reference:1.0 ptp_reference_0 ]
  set_property -dict [ list \
   CONFIG.PTP_REF_HZ {125000000} \
 ] $ptp_reference_0

  # Create instance: switch_aux_0, and set properties
  set switch_aux_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_aux:1.0 switch_aux_0 ]
  set_property -dict [ list \
   CONFIG.SCRUB_CLK_HZ {80000000} \
 ] $switch_aux_0

  # Create instance: switch_core, and set properties
  set switch_core [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_core:1.0 switch_core ]
  set_property -dict [ list \
   CONFIG.ALLOW_PRECOMMIT {true} \
   CONFIG.ALLOW_RUNT {false} \
   CONFIG.CFG_DEV_ADDR {0} \
   CONFIG.CFG_ENABLE {true} \
   CONFIG.CORE_CLK_HZ {125000000} \
   CONFIG.DATAPATH_BYTES {3} \
   CONFIG.HBUF_KBYTES {2} \
   CONFIG.PORT_COUNT {5} \
   CONFIG.STATS_DEVADDR {1} \
   CONFIG.STATS_ENABLE {true} \
   CONFIG.SUPPORT_PTP {true} \
   CONFIG.SUPPORT_VLAN {true} \
 ] $switch_core

  # Create instance: synth_mgt_from_rtc_0, and set properties
  set synth_mgt_from_rtc_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:synth_mgt_from_rtc:1.0 synth_mgt_from_rtc_0 ]
  set_property -dict [ list \
   CONFIG.CFG_DEV_ADDR {11} \
   CONFIG.CFG_ENABLE {true} \
   CONFIG.PTP_REF_HZ {125000000} \
   CONFIG.RTC_REF_HZ {125000000} \
 ] $synth_mgt_from_rtc_0

  # Create instance: ublaze0
  create_hier_cell_ublaze0 [current_bd_instance .] ublaze0

  # Create instance: xlconcat_0, and set properties
  set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
  set_property -dict [ list \
   CONFIG.NUM_PORTS {4} \
 ] $xlconcat_0

  # Create interface connections
  connect_bd_intf_net -intf_net GTREFCLK_0_1 [get_bd_intf_ports fmc_ref] [get_bd_intf_pins synth_mgt_from_rtc_0/GTREFCLK]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port00 [get_bd_intf_pins cfgbus_split_0/Port00] [get_bd_intf_pins switch_core/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port01 [get_bd_intf_pins cfgbus_split_0/Port01] [get_bd_intf_pins port_mailmap/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port02 [get_bd_intf_pins cfgbus_split_0/Port02] [get_bd_intf_pins port_serial_uart/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port03 [get_bd_intf_pins cfgbus_i2c_controller_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port03]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port04 [get_bd_intf_pins cfgbus_split_0/Port04] [get_bd_intf_pins cfgbus_timer_0/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port05 [get_bd_intf_pins cfgbus_mdio_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port05]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port06 [get_bd_intf_pins cfgbus_led_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port06]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port07 [get_bd_intf_pins cfgbus_split_0/Port07] [get_bd_intf_pins cfgbus_uart_0/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port08 [get_bd_intf_pins cfgbus_split_0/Port08] [get_bd_intf_pins cfgbus_text_lcd_0/Cfg]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port09 [get_bd_intf_pins cfgbus_gpi_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port09]
  connect_bd_intf_net -intf_net cfgbus_split_0_Port10 [get_bd_intf_pins cfgbus_split_0/Port10] [get_bd_intf_pins synth_mgt_from_rtc_0/Cfg]
  connect_bd_intf_net -intf_net mgt_ref_1 [get_bd_intf_ports mgt_ref] [get_bd_intf_pins port_sgmii_raw_gtx_0/GTREFCLK]
  connect_bd_intf_net -intf_net port_mailmap_0_Eth [get_bd_intf_pins port_mailmap/Eth] [get_bd_intf_pins switch_core/Port00]
connect_bd_intf_net -intf_net port_mailmap_PtpTime [get_bd_intf_pins port_mailmap/PtpTime] [get_bd_intf_pins synth_mgt_from_rtc_0/PtpTime]
  connect_bd_intf_net -intf_net port_serial_uart_4wi_0_Eth [get_bd_intf_pins port_serial_uart/Eth] [get_bd_intf_pins switch_core/Port01]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_0_Eth [get_bd_intf_pins port_sgmii_raw_gtx_0/Eth] [get_bd_intf_pins switch_core/Port02]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_0_SGMII [get_bd_intf_ports sgmii_rj45] [get_bd_intf_pins port_sgmii_raw_gtx_0/SGMII]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_1_Eth [get_bd_intf_pins port_sgmii_raw_gtx_1/Eth] [get_bd_intf_pins switch_core/Port03]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_1_SGMII [get_bd_intf_ports sgmii_sfp] [get_bd_intf_pins port_sgmii_raw_gtx_1/SGMII]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_2_Eth [get_bd_intf_pins port_sgmii_raw_gtx_2/Eth] [get_bd_intf_pins switch_core/Port04]
  connect_bd_intf_net -intf_net port_sgmii_raw_gtx_2_SGMII [get_bd_intf_ports sgmii_sma] [get_bd_intf_pins port_sgmii_raw_gtx_2/SGMII]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef [get_bd_intf_pins port_mailmap/PtpRef] [get_bd_intf_pins ptp_reference_0/PtpRef]
connect_bd_intf_net -intf_net [get_bd_intf_nets ptp_reference_0_PtpRef] [get_bd_intf_pins port_sgmii_raw_gtx_0/PtpRef] [get_bd_intf_pins ptp_reference_0/PtpRef]
connect_bd_intf_net -intf_net [get_bd_intf_nets ptp_reference_0_PtpRef] [get_bd_intf_pins port_sgmii_raw_gtx_1/PtpRef] [get_bd_intf_pins ptp_reference_0/PtpRef]
connect_bd_intf_net -intf_net [get_bd_intf_nets ptp_reference_0_PtpRef] [get_bd_intf_pins port_sgmii_raw_gtx_2/PtpRef] [get_bd_intf_pins ptp_reference_0/PtpRef]
connect_bd_intf_net -intf_net [get_bd_intf_nets ptp_reference_0_PtpRef] [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins synth_mgt_from_rtc_0/PtpRef]
  connect_bd_intf_net -intf_net switch_aux_0_text_lcd [get_bd_intf_ports text_lcd] [get_bd_intf_pins cfgbus_text_lcd_0/text_lcd]
  connect_bd_intf_net -intf_net sys_clk_1 [get_bd_intf_ports sys_clk] [get_bd_intf_pins ublaze0/sys_clk]
  connect_bd_intf_net -intf_net ublaze0_CfgBus [get_bd_intf_pins cfgbus_split_0/Cfg] [get_bd_intf_pins ublaze0/CfgBus]
  connect_bd_intf_net -intf_net ublaze0_ddr3_0 [get_bd_intf_ports ddr3] [get_bd_intf_pins ublaze0/ddr3]

  # Create port connections
  connect_bd_net -net cfgbus_timer_0_wdog_resetp [get_bd_pins cfgbus_timer_0/wdog_resetp] [get_bd_pins ublaze0/wdog_resetp]
  connect_bd_net -net cpu_clk_1 [get_bd_pins port_serial_uart/refclk] [get_bd_pins ptp_reference_0/ref_clk] [get_bd_pins switch_core/core_clk] [get_bd_pins synth_mgt_from_rtc_0/out_clk_125] [get_bd_pins ublaze0/clk_125]
  connect_bd_net -net cpu_reset_1 [get_bd_ports cpu_reset] [get_bd_pins port_sgmii_raw_gtx_0/reset_p] [get_bd_pins port_sgmii_raw_gtx_1/reset_p] [get_bd_pins port_sgmii_raw_gtx_2/reset_p]
  connect_bd_net -net cpu_reset_2 [get_bd_pins synth_mgt_from_rtc_0/out_reset_p] [get_bd_pins ublaze0/cpu_reset]
  connect_bd_net -net cts_n_0_1 [get_bd_ports usb_cts_n] [get_bd_pins port_serial_uart/cts_n]
  connect_bd_net -net dip_sw_1 [get_bd_ports dip_sw] [get_bd_pins xlconcat_0/In0]
  connect_bd_net -net phy_mdio_sck [get_bd_ports phy_mdio_sck] [get_bd_pins cfgbus_mdio_0/mdio_clk]
  connect_bd_net -net phy_mdio_sda [get_bd_ports phy_mdio_sda] [get_bd_pins cfgbus_mdio_0/mdio_data]
  connect_bd_net -net port_serial_uart_rts_n [get_bd_ports usb_rts_n] [get_bd_pins port_serial_uart/rts_n]
  connect_bd_net -net port_serial_uart_txd [get_bd_ports usb_txd] [get_bd_pins port_serial_uart/txd]
  connect_bd_net -net port_sgmii_raw_gtx_0_out_clk_125 [get_bd_pins port_sgmii_raw_gtx_0/out_clk_125] [get_bd_pins synth_mgt_from_rtc_0/sys_clk_125]
  connect_bd_net -net port_sgmii_raw_gtx_0_out_reset_p [get_bd_pins port_sgmii_raw_gtx_0/out_reset_p] [get_bd_pins synth_mgt_from_rtc_0/sys_reset_p] [get_bd_pins ublaze0/mig_reset]
  connect_bd_net -net port_sgmii_raw_gtx_0_shared_out [get_bd_pins port_sgmii_raw_gtx_0/shared_out] [get_bd_pins port_sgmii_raw_gtx_1/shared_in] [get_bd_pins port_sgmii_raw_gtx_2/shared_in]
  connect_bd_net -net pushbtn_1 [get_bd_ports pushbtn] [get_bd_pins xlconcat_0/In3]
  connect_bd_net -net rxd_0_1 [get_bd_ports usb_rxd] [get_bd_pins port_serial_uart/rxd]
  connect_bd_net -net scrub_clk_0_1 [get_bd_ports emc_clk] [get_bd_pins port_sgmii_raw_gtx_0/gtsysclk] [get_bd_pins port_sgmii_raw_gtx_1/gtsysclk] [get_bd_pins port_sgmii_raw_gtx_2/gtsysclk] [get_bd_pins switch_aux_0/scrub_clk] [get_bd_pins ublaze0/emc_clk]
  connect_bd_net -net sfp_sck [get_bd_ports sfp_i2c_sck] [get_bd_pins cfgbus_i2c_controller_0/i2c_sclk]
  connect_bd_net -net sfp_sda [get_bd_ports sfp_i2c_sda] [get_bd_pins cfgbus_i2c_controller_0/i2c_sdata]
  connect_bd_net -net status_led [get_bd_ports status_led] [get_bd_pins cfgbus_led_0/led_out]
  connect_bd_net -net switch_aux_0_scrub_req_t [get_bd_pins switch_aux_0/scrub_req_t] [get_bd_pins switch_core/scrub_req_t]
  connect_bd_net -net switch_aux_0_status_uart [get_bd_pins cfgbus_uart_0/uart_rxd] [get_bd_pins switch_aux_0/status_uart]
  connect_bd_net -net switch_core_errvec_t [get_bd_pins switch_aux_0/errvec_00] [get_bd_pins switch_core/errvec_t]
  connect_bd_net -net synth_mgt_from_rtc_0_debug1_flag [get_bd_pins ila_synth/probe2] [get_bd_pins synth_mgt_from_rtc_0/debug1_flag]
  connect_bd_net -net synth_mgt_from_rtc_0_debug1_time [get_bd_pins ila_synth/probe3] [get_bd_pins synth_mgt_from_rtc_0/debug1_time]
  connect_bd_net -net synth_mgt_from_rtc_0_debug2_clk [get_bd_pins ila_synth/clk] [get_bd_pins synth_mgt_from_rtc_0/debug2_clk]
  connect_bd_net -net synth_mgt_from_rtc_0_debug2_flag [get_bd_pins ila_synth/probe0] [get_bd_pins synth_mgt_from_rtc_0/debug2_flag]
  connect_bd_net -net synth_mgt_from_rtc_0_debug2_time [get_bd_pins ila_synth/probe1] [get_bd_pins synth_mgt_from_rtc_0/debug2_time]
  connect_bd_net -net synth_mgt_from_rtc_0_mgt_synth_n [get_bd_ports fmc_synth_n] [get_bd_pins synth_mgt_from_rtc_0/mgt_synth_n]
  connect_bd_net -net synth_mgt_from_rtc_0_mgt_synth_p [get_bd_ports fmc_synth_p] [get_bd_pins synth_mgt_from_rtc_0/mgt_synth_p]
  connect_bd_net -net synth_mgt_from_rtc_0_out_detect [get_bd_pins synth_mgt_from_rtc_0/out_detect] [get_bd_pins ublaze0/ext_clk_detect] [get_bd_pins xlconcat_0/In1]
  connect_bd_net -net synth_mgt_from_rtc_0_out_select [get_bd_pins synth_mgt_from_rtc_0/out_select] [get_bd_pins xlconcat_0/In2]
  connect_bd_net -net ublaze0_peripheral_aresetn_0 [get_bd_ports sfp_enable] [get_bd_pins ublaze0/reset_n]
  connect_bd_net -net ublaze0_reset_p [get_bd_pins port_serial_uart/reset_p] [get_bd_pins ptp_reference_0/reset_p] [get_bd_pins switch_aux_0/reset_p] [get_bd_pins switch_core/reset_p] [get_bd_pins ublaze0/reset_p]
  connect_bd_net -net xlconcat_0_dout [get_bd_pins cfgbus_gpi_0/gpi_in] [get_bd_pins xlconcat_0/dout]

  # Create address segments
  create_bd_addr_seg -range 0x00100000 -offset 0x44A00000 [get_bd_addr_spaces ublaze0/microblaze_0/Data] [get_bd_addr_segs ublaze0/cfgbus_host_axi_0/CtrlAxi/CtrlAxi_addr] SEG_cfgbus_host_axi_0_CtrlAxi_addr
  create_bd_addr_seg -range 0x00040000 -offset 0x00000000 [get_bd_addr_spaces ublaze0/microblaze_0/Data] [get_bd_addr_segs ublaze0/microblaze_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] SEG_dlmb_bram_if_cntlr_Mem
  create_bd_addr_seg -range 0x00040000 -offset 0x00000000 [get_bd_addr_spaces ublaze0/microblaze_0/Instruction] [get_bd_addr_segs ublaze0/microblaze_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] SEG_ilmb_bram_if_cntlr_Mem
  create_bd_addr_seg -range 0x00001000 -offset 0x41400000 [get_bd_addr_spaces ublaze0/microblaze_0/Data] [get_bd_addr_segs ublaze0/mdm_1/S_AXI/Reg] SEG_mdm_1_Reg
  create_bd_addr_seg -range 0x00010000 -offset 0x41200000 [get_bd_addr_spaces ublaze0/microblaze_0/Data] [get_bd_addr_segs ublaze0/microblaze_0_axi_intc/S_AXI/Reg] SEG_microblaze_0_axi_intc_Reg
  create_bd_addr_seg -range 0x40000000 -offset 0x80000000 [get_bd_addr_spaces ublaze0/microblaze_0/Data] [get_bd_addr_segs ublaze0/mig_7series_0/memmap/memaddr] SEG_mig_7series_0_memaddr


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""
