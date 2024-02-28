# -*- coding: utf-8 -*-

# Copyright 2020-2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Helper tool for configuring the AC-Galaxy test board, including
the various AR8031 PHY transceivers.
See also: cfgbus_host_uart.vhd, cfgbus_peripherals.vhd
'''

import os
import sys
import time

# Additional imports from SatCat5 core.
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))
from satcat5_uart import AsyncSLIPWriteOnly
from satcat5_cfgbus import ConfigBus, ConfigGPO, ConfigMDIO

class SwitchConfig:
    # Define various bits in FPGA GPO register.
    GPO_ALLPORT_RST = 2**16 - 1     # Reset all FPGA ports (0-15)
    GPO_SJA_RSTN    = 2**16         # Ext reset for SJA1105
    GPO_ETH1_RSTN   = 2**17         # Ext reset for Eth1 PHY (TJA1100)
    GPO_ETH1_WAKE   = 2**18         # Wake signal for Eth1 PHY (TJA1100)
    GPO_ETH1_EN     = 2**19         # Enable signal for Eth1 PHY (TJA1100)
    GPO_ETH1_MDIR   = 2**20         # MDIO direction for Eth1 PHY (1 = Output)
    GPO_ETH2_RSTN   = 2**21         # Ext reset for Eth2 PHY (AR8031)
    GPO_ETH3_RSTN   = 2**22         # Ext reset for Eth2 PHY (AR8031)
    GPO_CLKGEN_RST  = 2**23         # Int reset for FPGA clock generator
    GPO_RMII_FAST   = 2**24         # Eth0 speed control (RMII only)
    GPO_NOERR_MIIRX = 2**25         # Suppress MII-RX error reports
    GPO_CLKGEN_SHDN = 2**26         # Long-term shutdown for FPGA clock generator
    GPO_CLKGEN_SJA  = 2**27         # Use SJA1105 clock or external ref?
    GPO_CORE_RST    = 2**31         # Int reset for FPGA switch core

    # Set default state of FPGA GPO register.
    # All resets enabled, including active-low resets.
    GPO_INITIAL = (
        GPO_ALLPORT_RST |           # All ports reset/shutdown
        GPO_ETH1_MDIR |             # MDIO = Output
        GPO_RMII_FAST |             # RMII mode = 100 Mbps
        GPO_CORE_RST |              # Reset switch core
        GPO_CLKGEN_SHDN |           # Shut down clock generator
        GPO_CLKGEN_SJA |            # Use SJA clock reference
        GPO_CLKGEN_RST )            # Reset clock generator

    def __init__(self, serial):
        # Link to designated ConfigBus host.
        self._cfg = ConfigBus(
            AsyncSLIPWriteOnly(serial),
            mac_addr    = b'\x5A\x5A\xDE\xAD\xBE\xEF',
            ethertype   = 0x5C01,       # Hard-coded address and EType
            readable    = False)        # Reply line disconnected
        # Create wrappers for each peripheral.
        DEV_ADDR = 0x00                 # Shared device address
        REG_GPO  = 0x10                 # Control register for discrete GPO
        REG_MDIO = lambda n: 0x20 + n   # Control register for Nth MDIO
        self._gpo = ConfigGPO(self._cfg, DEV_ADDR, REG_GPO)
        self._mdio = [
            ConfigMDIO(self._cfg, DEV_ADDR, REG_MDIO(n))
            for n in range(8)
        ]
    
    def reset_all(self, eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk=False):
        '''Reset and configure all devices.'''
        # Reset EVERYTHING.
        self._gpo.set(self.GPO_INITIAL)
        # Start individual PHYs first; RX pins are used for initial config.
        self.reset_tja1100(self._mdio[0])
        self.reset_ar8031(1, eth2_sgmii)
        self.reset_ar8031(2, eth3_sgmii)
        # Start the FPGA.
        self.reset_fpga(eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk)

    def reset_fpga(self, eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk):
        '''Reset switch FPGA.'''
        # Reset SJA1105, which is nonfunctional but acts as a clock source.
        self._gpo.clr_mask(self.GPO_SJA_RSTN)
        self._gpo.set_mask(self.GPO_SJA_RSTN)
        # Assert all internal resets.
        self._gpo.set_mask( self.GPO_ALLPORT_RST
                          | self.GPO_CLKGEN_SHDN
                          | self.GPO_CLKGEN_RST
                          | self.GPO_CORE_RST )
        # Select the appropriate clock source.
        if use_extclk:
            self._gpo.clr_mask(self.GPO_CLKGEN_SJA) # Refclk 0 --> External
        else:
            self._gpo.set_mask(self.GPO_CLKGEN_SJA) # Refclk 1 --> SJA1105
        # If either SGMII mode is enabled, suppress MII-RX errors.
        # (This is a known issue, no sense crying wolf all the time.)
        # TODO: Remove this if resolved (or to measure error rate, etc.)
        if eth2_sgmii or eth2_sgmii:
            self._gpo.set_mask(self.GPO_NOERR_MIIRX)
        # Activate clock system, then the switch core
        self._gpo.clr_mask(self.GPO_CLKGEN_SHDN)
        time.sleep(0.010)
        self._gpo.clr_mask(self.GPO_CLKGEN_RST)
        time.sleep(0.010)
        self._gpo.clr_mask(self.GPO_CORE_RST)
        # Determine which ports to activate.
        if eth0_rgmii:
            # Extended interface --> Activate RGMII or SGMII, not both.
            port_mask = 0xFFF1      # Uplink and SPI/UART ports
            if eth2_sgmii:
                port_mask |= 0x0004 # SGMII0 = Eth2
            if eth3_sgmii:
                port_mask |= 0x0008 # SGMII1 = Eth3
            else:
                port_mask |= 0x0002 # RGMII1 = Eth3
        else:
            port_mask = self.GPO_ALLPORT_RST
        self._gpo.clr_mask(port_mask)

    def reset_tja1100(self, mdio_port):
        '''Reset and configure specified TJA1100 PHY.'''
        self._gpo.clr_mask(self.GPO_ETH1_RSTN)
        self._gpo.set_mask(self.GPO_ETH1_RSTN)
        mdio_port.mdio_send(0, 17, 0x9A04)   # Auto-mode, enable config reg
        mdio_port.mdio_send(0, 18, 0x4A10)   # PHY slave, RMII w/ crystal
        self._gpo.set_mask(self.GPO_ETH1_WAKE | self.GPO_ETH1_EN)

    def reset_ar8031(self, mdio_port, use_sgmii, blink_led=False, rx_clk_dly=False, dbg_clksel=0):
        '''Reset and configure specified AR8031 PHY.'''
        # Reset the appropriate PHY.
        if (mdio_port == 1):
            self._gpo.clr_mask(self.GPO_ETH2_RSTN)
            time.sleep(0.02)    # Hold reset >= 10 msec
            self._gpo.set_mask(self.GPO_ETH2_RSTN)
        elif (mdio_port == 2):
            self._gpo.clr_mask(self.GPO_ETH3_RSTN)
            time.sleep(0.02)    # Hold reset >= 10 msec
            self._gpo.set_mask(self.GPO_ETH3_RSTN)
        else:
            raise Exception("Invalid AR8031 port")
        # Select RGMII or SGMII interface.
        if use_sgmii:
            mode_cfg = 0x8501   # Copper + SGMII
        else:
            mode_cfg = 0x8500   # Copper + RGMII
        # Select status LED mode
        if blink_led:
            mode_led = 0x3045   # Test mode (blinking)
        else:
            mode_led = 0x3000   # Normal link indicators
        # Select RGMII clock delay mode
        if rx_clk_dly:
            mode_rxclk = 0x82EE # RXCLK internal delay
        else:
            mode_rxclk = 0x02EE # RXCLK external delay
        # Set all relevant registers.
        # Note: PHYADDR is indeterminate, just try all eight options.
        mdio = self._mdio[mdio_port]
        for phy_addr in range(8):
            # Regular register writes:
            mdio.mdio_send(phy_addr,  0, 0x1140)    # 1000 Mbps, full-duplex
            mdio.mdio_send(phy_addr,  4, 0x1001)    # XNP enabled, no PAUSE or 10/100 support
            mdio.mdio_send(phy_addr, 20, 0x0000)    # Disable "SmartSpeed"
            mdio.mdio_send(phy_addr, 25, mode_led)  # Select LED mode
            mdio.mdio_send(phy_addr, 31, mode_cfg)  # Select SGMII or RGMII
            # Indirect writes to Debug, MMD3, and MMD7 registers:
            mdio.mdbg_send(phy_addr, 0x0000, mode_rxclk)    # Set RGMII RX_CLK delay
            mdio.mmd3_send(phy_addr, 0x805D, 0x1000)        # Disable SmartEEE
            mdio.mmd7_send(phy_addr, 0x8011, 0x8000)        # Max SGMII drive strength
            mdio.mmd7_send(phy_addr, 0x8016, 4*dbg_clksel)  # Select debug output
