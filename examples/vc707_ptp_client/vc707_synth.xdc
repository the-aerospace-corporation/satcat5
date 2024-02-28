# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for vc707_ptp_client
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

set_property PACKAGE_PIN AV40   [get_ports {cpu_reset}];        # CPU_RESET
set_property PACKAGE_PIN AP37   [get_ports {emc_clk}];          # FPGA_EMCCLK (80 MHz)
set_property PACKAGE_PIN K8     [get_ports {fmc_ref_clk_p}];    # FMC2_HPC_GBTCLK0_M2C_P
set_property PACKAGE_PIN N2     [get_ports {fmc_synth_p[0]}];   # FMC2_HPC_DP0_C2M_P
set_property PACKAGE_PIN M4     [get_ports {fmc_synth_p[1]}];   # FMC2_HPC_DP1_C2M_P
set_property PACKAGE_PIN L2     [get_ports {fmc_synth_p[2]}];   # FMC2_HPC_DP2_C2M_P
set_property PACKAGE_PIN K4     [get_ports {fmc_synth_p[3]}];   # FMC2_HPC_DP3_C2M_P
set_property PACKAGE_PIN AH8    [get_ports {mgt_ref_clk_p}];    # SGMIICLK_Q0_P (125 MHz)
set_property PACKAGE_PIN AH31   [get_ports {phy_mdio_sck}];     # PHY_MDC_LS
set_property PACKAGE_PIN AK33   [get_ports {phy_mdio_sda}];     # PHY_MDIO_LS
set_property PACKAGE_PIN AP33   [get_ports {sfp_enable}];       # SFP_TX_DISABLE (mislabeled)
set_property PACKAGE_PIN AT35   [get_ports {sfp_i2c_sck}];      # IIC_SCL_MAIN_LS
set_property PACKAGE_PIN AU32   [get_ports {sfp_i2c_sda}];      # IIC_SDA_MAIN_LS
set_property PACKAGE_PIN AM8    [get_ports {sgmii_rj45_rxp}];   # SGMII to PHY + RJ45 connector
set_property PACKAGE_PIN AN2    [get_ports {sgmii_rj45_txp}];   # (SGMII_RX_P, SGMII_TX_P)
set_property PACKAGE_PIN AL6    [get_ports {sgmii_sfp_rxp}];    # SGMII to SFP cage
set_property PACKAGE_PIN AM4    [get_ports {sgmii_sfp_txp}];    # (SFP_RX_P, SFP_TX_P)
set_property PACKAGE_PIN AN6    [get_ports {sgmii_sma_rxp}];    # SGMII to SMA connectors
set_property PACKAGE_PIN AP4    [get_ports {sgmii_sma_txp}];    # (SMA_MGT_RX_P, SMA_MGT_TX_P)
set_property PACKAGE_PIN AM39   [get_ports {status_led[0]}];    # GPIO_LED_*_LS
set_property PACKAGE_PIN AN39   [get_ports {status_led[1]}];
set_property PACKAGE_PIN AR37   [get_ports {status_led[2]}];
set_property PACKAGE_PIN AT37   [get_ports {status_led[3]}];
set_property PACKAGE_PIN AR35   [get_ports {status_led[4]}];
set_property PACKAGE_PIN AP41   [get_ports {status_led[5]}];
set_property PACKAGE_PIN AP42   [get_ports {status_led[6]}];
set_property PACKAGE_PIN AU39   [get_ports {status_led[7]}];
set_property PACKAGE_PIN E19    [get_ports {sys_clk_clk_p}];    # SYSCLK_P (200 MHz)
set_property PACKAGE_PIN AT42   [get_ports {text_lcd_lcd_db[0]}];
set_property PACKAGE_PIN AR38   [get_ports {text_lcd_lcd_db[1]}];
set_property PACKAGE_PIN AR39   [get_ports {text_lcd_lcd_db[2]}];
set_property PACKAGE_PIN AN40   [get_ports {text_lcd_lcd_db[3]}];
set_property PACKAGE_PIN AT40   [get_ports {text_lcd_lcd_e}];
set_property PACKAGE_PIN AN41   [get_ports {text_lcd_lcd_rs}];
set_property PACKAGE_PIN AR42   [get_ports {text_lcd_lcd_rw}];
set_property PACKAGE_PIN AT32   [get_ports {usb_cts_n}];        # USB_UART_RTS
set_property PACKAGE_PIN AU36   [get_ports {usb_txd}];          # USB_UART_RX
set_property PACKAGE_PIN AU33   [get_ports {usb_rxd}];          # USB_UART_TX
set_property PACKAGE_PIN AR34   [get_ports {usb_rts_n}];        # USB_UART_CTS

set_property PACKAGE_PIN AV30   [get_ports {dip_sw[0]}];        # GPIO_DIP_SW*
set_property PACKAGE_PIN AY33   [get_ports {dip_sw[1]}];
set_property PACKAGE_PIN BA31   [get_ports {dip_sw[2]}];
set_property PACKAGE_PIN BA32   [get_ports {dip_sw[3]}];
set_property PACKAGE_PIN AW30   [get_ports {dip_sw[4]}];
set_property PACKAGE_PIN AY30   [get_ports {dip_sw[5]}];
set_property PACKAGE_PIN BA30   [get_ports {dip_sw[6]}];
set_property PACKAGE_PIN BB31   [get_ports {dip_sw[7]}];

set_property PACKAGE_PIN AR40   [get_ports {pushbtn[0]}];       # GPIO_SW_N (North)
set_property PACKAGE_PIN AP40   [get_ports {pushbtn[1]}];       # GPIO_SW_S (South)
set_property PACKAGE_PIN AU38   [get_ports {pushbtn[2]}];       # GPIO_SW_E (East)
set_property PACKAGE_PIN AW40   [get_ports {pushbtn[3]}];       # GPIO_SW_W (West)
set_property PACKAGE_PIN AV39   [get_ports {pushbtn[4]}];       # GPIO_SW_C (Center)
set_property PACKAGE_PIN AR33   [get_ports {pushbtn[5]}];       # ROTARY_INCA
set_property PACKAGE_PIN AT31   [get_ports {pushbtn[6]}];       # ROTARY_INCB
set_property PACKAGE_PIN AW31   [get_ports {pushbtn[7]}];       # ROTARY_PUSH

#####################################################################
### Set all voltages and signaling standards

# All single-ended I/O pins at 1.8V
set_property IOSTANDARD LVCMOS18 [get_ports cpu_reset];
set_property IOSTANDARD LVCMOS18 [get_ports emc_clk];
set_property IOSTANDARD LVCMOS18 [get_ports phy_mdio*];
set_property IOSTANDARD LVCMOS18 [get_ports pushbtn*];
set_property IOSTANDARD LVCMOS18 [get_ports sfp_*];
set_property IOSTANDARD LVCMOS18 [get_ports status_led*];
set_property IOSTANDARD LVCMOS18 [get_ports text_lcd*];
set_property IOSTANDARD LVCMOS18 [get_ports usb_*];
set_property IOSTANDARD LVCMOS18 [get_ports dip_sw*];

# CFGBVS pin = GND.
set_property CFGBVS GND [current_design];
set_property CONFIG_VOLTAGE 1.8 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
