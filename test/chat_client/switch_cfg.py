# -*- coding: utf-8 -*-

# Copyright 2019 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

'''
Helper tool for configuring the AC-Galaxy test board, including
the SJA1105 switch ASIC and several AR8031 PHY transceivers.
See also: demo_config.vhd
'''

from numpy import hstack, uint32, zeros
from serial_utils import slipEncode
from struct import pack
from zlib import crc32
import time

def make_sja_table(field_list):
    '''Construct an SJA1105 table entry from a list of size/value pairs.'''
    # Build giant integer, one field at a time.
    tot_value = 0
    tot_nbits = 0
    for (nbits, value) in field_list:
        tot_value = (tot_value << nbits) + value
        tot_nbits += nbits
    # Sanity check: Length should be a multiple of 32 bits.
    nwords = tot_nbits // 32
    assert (tot_nbits == 32*nwords)
    # Convert giant integer to uint32 list, LSW-first.
    # (Each 32-bit word is big-endian, but words are LSW-first.)
    result = zeros(nwords, dtype='uint32')
    for ndx in range(nwords):
        result[ndx] = tot_value % 2**32
        tot_value //= 2**32
    return result

class DefaultSJA1105:
    '''
    Set default configuration tables for SJA1105.

    Refer to UM10851 sections 4.2.2 - 4.2.11 for details.
    Note each table is listed LSW-first, even though each
    32-bit word is send in big-endian order!
    '''
    # Define speed codes for use with MAC_CONFIG_SINGLE, below.
    MAC_SPEED_10Mbps    = 0x00
    MAC_SPEED_100Mbps   = 0x01
    MAC_SPEED_1000Mbps  = 0x02
    MAC_SPEED_DYNAMIC   = 0x03

    # Define MAC-to-PHY or MAC-to-MAC interface codes for use with XMII_MODE, below.
    TYPE_PORT_DISABLED      = 0x07  # Port shutdown
    TYPE_MAC2PHY_MII        = 0x00  # Normal MAC mode (MAC2PHY)
    TYPE_MAC2PHY_RMII       = 0x01
    TYPE_MAC2PHY_RGMII      = 0x02
    TYPE_MAC2MAC_MII        = 0x04  # PHY emulation for MAC2MAC support
    TYPE_MAC2MAC_RMII       = 0x05
    TYPE_MAC2MAC_RGMII      = 0x06

    # L2 policing table, 45 entries (Section 4.2.2)
    L2_POLICING = hstack([make_sja_table((
        (6,n),                      # SHARINDX    = Increment [0..44]
        (16,65535),                 # SMAX        = 65535 (no burst limit)
        (16,64000),                 # RATE        = 64000 (max 1 Gbps)
        (11,1518),                  # MAXLEN      = 1518 bytes per packet
        (15,0)))                    # PARTITION   = Index 0
        for n in range(45)])

    # VLAN Lookup table, one entry (Section 4.2.3)
    VLAN_LOOKUP = make_sja_table((
        (5,0),                      # VING_MIRR
        (5,0),                      # VEGR_MIRR
        (5,0x1F),                   # VMEMB_PORT = All ports
        (5,0x1F),                   # VLAN_BC = All ports
        (5,0x1F),                   # TAG_PORT = All ports
        (12,0),                     # VLANID
        (27,0)))                    # Reserved

    # L2 Forwarding table, 13 entries (5 ports + 8 VLANs) (Section 4.2.4)
    L2_FORWARD = hstack((
        hstack([make_sja_table((    # 5 Regular ports...
            (5,0x1F &~ 2**n),       # BC_DOMAIN = All except self
            (5,0x1F &~ 2**n),       # REACH_PORT = All except self
            (5,0x1F &~ 2**n),       # FL_DOMAIN = All except self
            (3,7),                  # VLAN_PMAP[7] = 7
            (3,6),                  # VLAN_PMAP[6] = 6
            (3,5),                  # VLAN_PMAP[5] = 5
            (3,4),                  # VLAN_PMAP[4] = 4
            (3,3),                  # VLAN_PMAP[3] = 3
            (3,2),                  # VLAN_PMAP[2] = 2
            (3,1),                  # VLAN_PMAP[1] = 1
            (3,0),                  # VLAN_PMAP[0] = 0
            (25,0)))                # Reserved
            for n in range(5)]),
        hstack([make_sja_table((    # 8 VLAN ports...
            (15+9,0),               # Unused
            (3,n),                  # VLAN_PMAP[4] = n
            (3,n),                  # VLAN_PMAP[3] = n
            (3,n),                  # VLAN_PMAP[2] = n
            (3,n),                  # VLAN_PMAP[1] = n
            (3,n),                  # VLAN_PMAP[0] = n
            (25,0)))                # Reserved
            for n in range(8)])))

    def mac_config_single(self, spd):
        '''
        MAC Configuration table, each entry (Section 4.2.5)
        (User concatenates five entries to set speed of each port.)
        '''
        return make_sja_table((
            (9,511),(9,448),(1,1),  # TOP+BASE+ENABLED [7]
            (9,447),(9,384),(1,1),  # TOP+BASE+ENABLED [6]
            (9,383),(9,320),(1,1),  # TOP+BASE+ENABLED [5]
            (9,319),(9,256),(1,1),  # TOP+BASE+ENABLED [4]
            (9,255),(9,192),(1,1),  # TOP+BASE+ENABLED [3]
            (9,191),(9,128),(1,1),  # TOP+BASE+ENABLED [2]
            (9,127),(9, 64),(1,1),  # TOP+BASE+ENABLED [1]
            (9, 63),(9,  0),(1,1),  # TOP+BASE+ENABLED [0]
            (5,12),                 # IFG = 12 (Standard inter-frame gap)
            (2,spd),                # SPEED: User-specified (MAC_SPEED_xx)
            (16,0),(16,0),(8,0),    # TP_DELIN, TP_DELOUT, Unused
            (3,0),                  # VLANPRIO (Untagged traffic = Queue N)
            (12,0),                 # VLANID (VLAN tag value if adding one)
            (10,0x0E)))             # Bit flags: Set DYN_LEARN, EGRESS, INGRESS

    # L2 Forwarding Parameters (Section 4.2.7)
    L2_FWD_PARAM = make_sja_table((
        (3,0),                      # MAX_DYNP
        (10*7,0),                   # PART_SPC[7..1] = 0 (No memory alloc)
        (10,929),                   # PART_SPC[0] = 929 (Max to queue #0)
        (13,0)))                    # Unused

    # General parameters (Section 4.2.9)
    GENERAL_PARAM = make_sja_table((
        (2,0),(3,0),(3,0),          # MIRR_PTACU, SWITCHID, Unused
        (48,0x0180C2000000),        # MAC_FLTRES[1] (Spanning tree, etc.)
        (48,0xDEADBEEFCAFE),        # MAC_FLTRES[0] (Unused)
        (48,0xFFFFFF000000),        # MAC_FLT[1] (Spanning tree, etc.)
        (48,0x000000000000),        # MAC_FLT[0] (Unused)
        (4,8),                      # INCL_SRCPT and SEND_META flags
        (3,0), (3,0),               # CASC_PORT = HOST_PORT = Eth0
        (3,7),                      # MIRR_PORT = 7 (None/invalid)
        (64,0),                     # Unused
        (16,0x8100),                # TPID (Ethertype, single-tagged VLAN)
        (1,0),                      # IGNORE2STF
        (16,0x9100),                # TPID2 (Ethertype, double-tagged VLAN)
        (10,0)))                    # Unused

    def xmii_mode(self, type_array):
        '''xMII Mode parameters (Section 4.2.11)'''
        return make_sja_table((
            (3,type_array[4]),      # PHY_MAC+xMII_MODE [4]
            (3,type_array[3]),      # PHY_MAC+xMII_MODE [3]
            (3,type_array[2]),      # PHY_MAC+xMII_MODE [2]
            (3,type_array[1]),      # PHY_MAC+xMII_MODE [1]
            (3,type_array[0]),      # PHY_MAC+xMII_MODE [0]
            (17,0)))                # Unused

class SwitchConfig:
    '''Define various bits in FPGA GPO register.'''
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
        self._serial = serial

    def reset_all(self, eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk=False):
        '''Reset and configure all devices.'''
        # Reset EVERYTHING.
        self._gpo_send(self.GPO_INITIAL)
        # Start individual PHYs first; RX pins are used for initial config.
        self.reset_tja1100(0)
        self.reset_ar8031(1, eth2_sgmii)
        self.reset_ar8031(2, eth3_sgmii)
        # Start the switch.
        self.reset_sja1105(eth0_rgmii, eth2_sgmii)
        # Start the FPGA.
        self.reset_fpga(eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk)

    def reset_fpga(self, eth0_rgmii, eth2_sgmii, eth3_sgmii, use_extclk):
        '''Reset switch FPGA.'''
        # Assert all internal resets.
        self._gpo_raise( self.GPO_ALLPORT_RST
                       | self.GPO_CLKGEN_SHDN
                       | self.GPO_CLKGEN_RST
                       | self.GPO_CORE_RST )
        # Select the appropriate clock source.
        if use_extclk:
            self._gpo_lower(self.GPO_CLKGEN_SJA) # Refclk 0 --> External
        else:
            self._gpo_raise(self.GPO_CLKGEN_SJA) # Refclk 1 --> SJA1105
        # If either SGMII mode is enabled, suppress MII-RX errors.
        # (This is a known issue, no sense crying wolf all the time.)
        # TODO: Remove this if resolved (or to measure error rate, etc.)
        if eth2_sgmii or eth2_sgmii:
            self._gpo_raise(self.GPO_NOERR_MIIRX)
        # Activate clock system, then the switch core
        self._gpo_lower(self.GPO_CLKGEN_SHDN)
        time.sleep(0.010)
        self._gpo_lower(self.GPO_CLKGEN_RST)
        time.sleep(0.010)
        self._gpo_lower(self.GPO_CORE_RST)
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
        self._gpo_lower(port_mask)

    def reset_sja1105(self, eth0_rgmii, eth2_sgmii):
        '''Reset and configure SJA1105 switch.'''
        # Run the self-test function before proceeding.
        assert (self._sja_config_crc_test())
        # Global reset.
        self._gpo_lower(self.GPO_SJA_RSTN)
        self._gpo_raise(self.GPO_SJA_RSTN)
        # The link to the FPGA (Eth0) may be configured as RMII or RGMII.
        sja = DefaultSJA1105()
        if eth0_rgmii:
            eth0_spd    = sja.MAC_SPEED_1000Mbps
            eth0_type   = sja.TYPE_MAC2MAC_RGMII
        else:
            eth0_spd    = sja.MAC_SPEED_100Mbps
            eth0_type   = sja.TYPE_MAC2MAC_RMII
        # Eth2 PHY is connected to SJA1105 in RGMII mode, but
        # may be driven by the FPGA's SGMII interface instead.
        if eth2_sgmii:
            eth2_spd    = sja.MAC_SPEED_10Mbps      # Disabled
            eth2_type   = sja.TYPE_PORT_DISABLED
        else:
            eth2_spd    = sja.MAC_SPEED_1000Mbps    # Enabled
            eth2_type   = sja.TYPE_MAC2PHY_RGMII
        # Construct each configuration block (See UM10851 Table 2)
        # For now, we only set minimum mandatory set.
        blk_06h = self._sja_config_block(0x06, sja.L2_POLICING)
        blk_07h = self._sja_config_block(0x07, sja.VLAN_LOOKUP)
        blk_08h = self._sja_config_block(0x08, sja.L2_FORWARD)
        blk_09h = self._sja_config_block(0x09, hstack((
            sja.mac_config_single(eth0_spd),                # MII0 = FPGA
            sja.mac_config_single(sja.MAC_SPEED_100Mbps),   # MII1 = TJA1100
            sja.mac_config_single(eth2_spd),                # MII2 = AR8031
            sja.mac_config_single(sja.MAC_SPEED_10Mbps),    # MII3 = No connect
            sja.mac_config_single(sja.MAC_SPEED_10Mbps))))  # MII4 = No connect
        blk_0Eh = self._sja_config_block(0x0E, sja.L2_FWD_PARAM)
        blk_11h = self._sja_config_block(0x11, sja.GENERAL_PARAM)
        blk_4Eh = self._sja_config_block(0x4E, sja.xmii_mode([
            eth0_type,                      # MII0 = FPGA
            sja.TYPE_MAC2PHY_RMII,          # MII1 = TJA1100
            eth2_type,                      # MII2 = AR8031
            sja.TYPE_PORT_DISABLED,         # MII3 = No connect
            sja.TYPE_PORT_DISABLED]))       # MII4 = No connect
        blk_all = (blk_06h, blk_07h, blk_08h, blk_09h, blk_0Eh, blk_11h, blk_4Eh)
        # Issue a reset command
        self._sja_send_register(0x100440, 0x04)         # Cold reset
        time.sleep(0.1)
        # Send the complete configuration sequence.
        cfg_all = self._sja_config_footer(hstack(blk_all))
        self._sja_send_register(0x020000, cfg_all)
        time.sleep(0.3)
        # Configure the Clock Generation Unit (UM10851 Section 5.3)
        # Note: RMII-PHY mode sets RMII_REF_CLK = PLL1 (50 MHz)
        #       RMII-MAC also sets RMII_REF_CLK EXT_TX_CLK = PLL1 (50 MHz)
        #       RGMII mode sets RGMII_TX_CLK = PLL0 (125 MHz)
        self._sja_send_register(0x10000A, 0x0A010140)   # Start PLL1
        self._sja_send_register(0x100015, 0xE << 24)    # MII0_RMII_REF = PLL1
        self._sja_send_register(0x100016, 0xB << 24)    # MII0_RGMII_TX = PLL0
        self._sja_send_register(0x100018, 0xE << 24)    # MII0_EXT_TX = PLL1
        self._sja_send_register(0x10001C, 0xE << 24)    # MII1_RMII_REF = PLL1
        self._sja_send_register(0x100024, 0xB << 24)    # MII2_RGMII_TX = PLL0
        time.sleep(0.1)

    def reset_tja1100(self, mdio_port):
        '''Reset and configure specified TJA1100 PHY.'''
        self._gpo_lower(self.GPO_ETH1_RSTN)
        self._gpo_raise(self.GPO_ETH1_RSTN)
        self._mdio_send(mdio_port, 0, 17, 0x9A04)   # Auto-mode, enable config reg
        self._mdio_send(mdio_port, 0, 18, 0x4A10)   # PHY slave, RMII w/ crystal
        self._gpo_raise(self.GPO_ETH1_WAKE | self.GPO_ETH1_EN)

    def reset_ar8031(self, mdio_port, use_sgmii, blink_led=False, rx_clk_dly=False, dbg_clksel=0):
        '''Reset and configure specified AR8031 PHY.'''
        # Reset the appropriate PHY.
        if (mdio_port == 1):
            self._gpo_lower(self.GPO_ETH2_RSTN)
            time.sleep(0.02)    # Hold reset >= 10 msec
            self._gpo_raise(self.GPO_ETH2_RSTN)
        elif (mdio_port == 2):
            self._gpo_lower(self.GPO_ETH3_RSTN)
            time.sleep(0.02)    # Hold reset >= 10 msec
            self._gpo_raise(self.GPO_ETH3_RSTN)
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
        # Note: Not sure how PHYADDR is set, just try everything.
        # TODO: Confirm correct PHYADDR and remove this loop.
        for phy_addr in range(8):
            # Regular register writes:
            self._mdio_send(mdio_port, phy_addr,  0, 0x1140)    # 1000 Mbps, full-duplex
            self._mdio_send(mdio_port, phy_addr,  4, 0x1001)    # XNP enabled, no PAUSE or 10/100 support
            self._mdio_send(mdio_port, phy_addr, 20, 0x0000)    # Disable "SmartSpeed"
            self._mdio_send(mdio_port, phy_addr, 25, mode_led)  # Select LED mode
            self._mdio_send(mdio_port, phy_addr, 31, mode_cfg)  # Select SGMII or RGMII
            # Indirect writes to Debug, MMD3, and MMD7 registers:
            self._mdbg_send(mdio_port, phy_addr, 0x0000, mode_rxclk)    # Set RGMII RX_CLK delay
            self._mmd3_send(mdio_port, phy_addr, 0x805D, 0x1000)        # Disable SmartEEE
            self._mmd7_send(mdio_port, phy_addr, 0x8011, 0x8000)        # Max SGMII drive strength
            self._mmd7_send(mdio_port, phy_addr, 0x8016, 4*dbg_clksel)  # Select debug output

    def _sja_config_crc_test(self):
        '''Self-test of the CRC function.'''
        # Reference data from the "sja1105-tool":
        #   https://github.com/openil/sja1105-tool
        #   src/lib/static-config/default.c
        blk1 = uint32([0x07000000, 0x00000002])     # VLAN Lookup Header
        ref1 = b'\x07\x00\x00\x00\x00\x00\x00\x02\x7D\x0B\xCB\xF2'
        uut1 = self._sja_config_blockcrc(blk1).byteswap().tobytes()
        blk2 = uint32([0x00000000, 0x003FF000])     # VLAN Lookup Table
        ref2 = b'\x00\x00\x00\x00\x00\x3F\xF0\x00\x88\x38\x86\x85'
        uut2 = self._sja_config_blockcrc(blk2).byteswap().tobytes()
        blk3 = uint32([
            0x10000000, 0xF7BDF58D, 0x10000000, 0xEF7BF58D,
            0x10000000, 0xDEF7F58D, 0x10000000, 0xBDEFF58D,
            0x10000000, 0x7BDFF58D, 0x00000000, 0x00000000,
            0x92000000, 0x00000024, 0x24000000, 0x00000049,
            0xB6000000, 0x0000006D, 0x48000000, 0x00000092,
            0xDA000000, 0x000000B6, 0x6C000000, 0x000000DB,
            0xFE000000, 0x000000FF])                # L2 Forwarding Table
        ref3 = blk3.byteswap().tobytes() + b'\x67\x42\xE0\x06'
        uut3 = self._sja_config_blockcrc(blk3).byteswap().tobytes()
        return (ref1 == uut1) and (ref2 == uut2) and (ref3 == uut3)

    def _sja_config_blockcrc(self, blk_u32):
        '''
        Calculate and append CRC32 for SJA1105 configuration interface.
        Returns the resulting byte-stream for the entire block.
        '''
        # CRC is calculated as if data is sent little-endian, even though
        # each word is send big-endian.
        blk_crc = uint32(crc32(blk_u32.tobytes()) & 0xFFFFFFFF)
        # Bytes are actually sent big-endian, including CRC.
        # Note: This appears to contradict Section 4.1.1?
        return hstack((blk_u32, blk_crc))

    def _sja_config_block(self, blk_id, blk_dat):
        '''
        Construct one block of data (header + CRC + data + CRC) for the
        SJA1105 configuration interface. (Refer to: UM10851 section 4.1.1)
        '''
        hdr_dat = uint32([blk_id << 24, len(blk_dat)])
        hdr_crc = self._sja_config_blockcrc(hdr_dat)
        blk_crc = self._sja_config_blockcrc(blk_dat)
        return hstack((hdr_crc, blk_crc))

    def _sja_config_footer(self, cfg_blks):
        '''
        Construct footer block (footer + CRC) for the
        SJA1105 configuration interface. (Refer to: UM10851 section 4.1.1)
        '''
        dev_id  = uint32(0x9F00030E)     # Magic number from Section 4.1.1
        ftr_dat = hstack((dev_id, cfg_blks, 0, 0))
        return self._sja_config_blockcrc(ftr_dat)

    def _sja_send_register(self, reg_addr, reg_data):
        '''
        Write one SPI register using SJA1105 programming interface.
        (Refer to: UM10851 section 3.1)
        '''
        cmd = uint32((2**31) | (16*reg_addr))
        arg = uint32(reg_data)  # Singleton or array
        self._spi_send(hstack((cmd, arg)))

    def _gpo_raise(self, mask):
        '''Raise/set specific bits in FPGA GPO register.'''
        self._gpo_send(self._gpo | mask)

    def _gpo_lower(self, mask):
        '''Lower/clear specific bits in FPGA GPO register.'''
        self._gpo_send(self._gpo & ~mask)

    def _gpo_send(self, bits):
        '''Directly set new FPGA GPO register value.'''
        cmd = pack('>BL', 0x11, bits)
        self._gpo = bits
        self._serial.msg_send(slipEncode(cmd), blocking=True)

    def _mdio_send(self, mdio_port, phy_addr, reg_addr, reg_data):
        '''
        Send MDIO command to specified port and address.
        Command = 9 bytes:
           1 byte:  FPGA opcode (select MDIO port)
           4 bytes: MDIO-preamble (32 consecutive '1's)
           2 bytes: MDIO-opcode (start, write, phy & reg address)
           2 bytes: MDIO-data (16-bit register value)
        '''
        upper = 0x5002 | (phy_addr << 7) | (reg_addr << 2)
        cmd = pack('>BlHH', 0x20 + mdio_port, -1, upper, reg_data)
        self._serial.msg_send(slipEncode(cmd), blocking=True)
        time.sleep(0.001)   # Brief delay for command execution

    def _mdbg_send(self, mdio_port, phy_addr, reg_addr, reg_data):
        '''Write AR8031 indirect MDIO registers (Debug, MMD3, or MMD7).'''
        self._mdio_send(mdio_port, phy_addr, 29, reg_addr)  # Debug register address
        self._mdio_send(mdio_port, phy_addr, 30, reg_data)  # Debug register value

    def _mmd3_send(self, mdio_port, phy_addr, reg_addr, reg_data):
        self._mdio_send(mdio_port, phy_addr, 13, 0x0003)    # Next command = MMD3 address
        self._mdio_send(mdio_port, phy_addr, 14, reg_addr)  # Register address
        self._mdio_send(mdio_port, phy_addr, 13, 0x4003)    # Next command = MMD3 data
        self._mdio_send(mdio_port, phy_addr, 14, reg_data)  # Register value

    def _mmd7_send(self, mdio_port, phy_addr, reg_addr, reg_data):
        self._mdio_send(mdio_port, phy_addr, 13, 0x0007)    # Next command = MMD7 address
        self._mdio_send(mdio_port, phy_addr, 14, reg_addr)  # Register address
        self._mdio_send(mdio_port, phy_addr, 13, 0x4007)    # Next command = MMD7 data
        self._mdio_send(mdio_port, phy_addr, 14, reg_data)  # Register value

    def _spi_send(self, data):
        '''Send SPI command. (Input data must be numpy.uint32 array.)'''
        cmd = b'\x10' + data.byteswap().tobytes() # Output = Big-endian
        self._serial.msg_send(slipEncode(cmd), blocking=True)
