#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2020-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Top-level GUI for raw-Ethernet chat client and Galaxy switch setup.

Note: Requires ScaPy and must be run with administrative privileges.
      For Windows platforms, see additional instructions here:
        https://scapy.readthedocs.io/en/latest/installation.html#windows
'''

# Python library imports
import logging
import PyQt5.QtCore as qtc
import PyQt5.QtGui as qtg
import PyQt5.QtWidgets as qtw
import os
import sys
import threading
import time
import traceback
from numpy import ceil, random
from struct import pack, unpack

# Other imports from this folder.
import switch_cfg

# Additional imports from SatCat5 core.
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))
import satcat5_eth
from satcat5_gui import BetterComboBox
import satcat5_uart

# Start logging system.
logger = logging.getLogger(__name__)
logger.info('Starting logger...')
logger.setLevel('INFO')

def create_hamlet_generator():
    '''
    Infinite generator function for lines from Hamlet.
    Usage:
        obj = create_hamlet_generator()
        print(next(obj))
        print(next(obj))
    '''
    # Open the source file from Project Gutenberg.
    file = open('hamlet_oss.txt')
    para = ''   # Paragraph accumulator (see below)
    while True:
        # Seek to beginning of file.
        file.seek(0)
        # Skip through the copyright notice.
        while file.readline().startswith('//'):
            continue
        # Read one line at a time until end of file.
        # Append consecutive lines to form a full paragraph.
        for line in file:
            line = line.strip()
            if len(line) > 0:
                para += line + ' '  # Append line to paragraph
            elif len(para) > 0:
                yield para.strip()  # Emit complete paragraph
                para = ''

class ChatClient(qtw.QMainWindow):
    '''GUI window representing a single chat client.'''
    ETYPE_BEAT  = b'\x99\x9B'
    ETYPE_CHAT  = b'\x99\x9C'
    ETYPE_DATA  = b'\x99\x9D'
    MAC_BCAST   = 6*b'\xFF'
    MAX_MSGS    = 100
    LOG_VERBOSE = False

    def __init__(self):
        '''Initialize member variables.'''
        super().__init__()
        self.auto_data_count = 0
        self.auto_text_delay = 1.0
        self.bcast_lbl = self._format_address(self.MAC_BCAST, 'Broadcast')
        self.username = 'UNDEFINED'
        self.txrate_kbps = 0.0
        self.rxrate_kbps = 0.0
        self.sent_count  = 0
        self.rcvd_count  = 0
        self.rcvd_macs   = {}
        self.batch_txbytes = 0
        self.batch_rxbytes = 0
        self.batch_msgs  = []
        self.batch_lock  = threading.Lock()
        self.disp_msgs   = []
        self.port = None
        self._auto_text_gen = create_hamlet_generator()
        # Create various thread objects (started later).
        self._auto_text_thread = threading.Thread(
            target=self._auto_text_loop,
            name='Client auto-text')
        self._auto_text_thread.setDaemon(True)
        self._auto_data_thread = threading.Thread(
            target=self._auto_data_loop,
            name='Client auto-data')
        self._auto_data_thread.setDaemon(True)
        self._heartbeat_run = False
        self._heartbeat_thread = threading.Thread(
            target=self._heartbeat_loop,
            name='Client heartbeat')
        self._heartbeat_thread.setDaemon(True)
        # Create GUI elements.
        self.setWindowTitle('Chat: Placeholder')
        self.txt_macaddr = qtw.QLineEdit(self)
        self.txt_macaddr.setReadOnly(True)
        self.txt_username = qtw.QLineEdit(self)
        self.txt_username.setMaxLength(64)
        self.txt_username.editingFinished.connect(self.update_username)
        self.txt_txrate = qtw.QLineEdit(self)
        self.txt_txrate.setReadOnly(True)
        self.txt_rxrate = qtw.QLineEdit(self)
        self.txt_rxrate.setReadOnly(True)
        self.txt_sentcount = qtw.QLineEdit(self)
        self.txt_sentcount.setReadOnly(True)
        self.txt_rcvdcount = qtw.QLineEdit(self)
        self.txt_rcvdcount.setReadOnly(True)
        self.btn_rcvdclear = qtw.QPushButton('Clear', self)
        self.btn_rcvdclear.clicked.connect(self.clear_msgs)
        self.txt_rcvdlist = qtw.QPlainTextEdit(self)
        self.txt_rcvdlist.setReadOnly(True)
        self.cbo_sendto = BetterComboBox(self)
        self.cbo_sendto.setCurrentText(self.bcast_lbl)
        self.sld_autotext = qtw.QSlider(qtc.Qt.Horizontal, self)
        self.sld_autotext.valueChanged.connect(self.update_autotext)
        self.txt_autotext = qtw.QLabel(self)
        self.txt_sendmsg = qtw.QLineEdit(self)
        self.txt_sendmsg.returnPressed.connect(self.send_user_chat)
        self.btn_send = qtw.QPushButton('Send', self)
        self.btn_send.clicked.connect(self.send_user_chat)
        self.sld_autodata = qtw.QSlider(qtc.Qt.Horizontal, self)
        self.sld_autodata.valueChanged.connect(self.update_autodata)
        self.txt_autodata = qtw.QLabel(self)
        self.cbo_datato = BetterComboBox(self)
        self.cbo_datato.setCurrentText(self.bcast_lbl)
        # Create GUI layout.
        layout0a = qtw.QHBoxLayout()
        layout0a.addWidget(qtw.QLabel('Rate Tx:'))
        layout0a.addWidget(self.txt_txrate)
        layout0a.addWidget(qtw.QLabel('Rx:'))
        layout0a.addWidget(self.txt_rxrate)
        layout0b = qtw.QHBoxLayout()
        layout0b.addWidget(qtw.QLabel('Frames Tx:'))
        layout0b.addWidget(self.txt_sentcount)
        layout0b.addWidget(qtw.QLabel('Rx:'))
        layout0b.addWidget(self.txt_rcvdcount)
        layout0b.addWidget(self.btn_rcvdclear)
        layout0 = qtw.QFormLayout()
        layout0.addRow(layout0a)
        layout0.addRow(layout0b)
        group0 = qtw.QGroupBox('Status')
        group0.setLayout(layout0)
        layout1a = qtw.QHBoxLayout()
        layout1a.addWidget(qtw.QLabel('From:'))
        layout1a.addWidget(self.txt_macaddr)
        layout1a.addWidget(self.txt_username)
        layout1b = qtw.QHBoxLayout()
        layout1b.addWidget(qtw.QLabel('Auto-text:'))
        layout1b.addWidget(self.sld_autotext)
        layout1b.addWidget(self.txt_autotext)
        layout1 = qtw.QFormLayout()
        layout1.addRow(layout1a)
        layout1.addRow(qtw.QLabel('To:'), self.cbo_sendto)
        layout1.addRow(layout1b)
        layout1.addRow(self.txt_sendmsg)
        layout1.addRow(self.btn_send)
        group1 = qtw.QGroupBox('Send messages')
        group1.setLayout(layout1)
        layout2b = qtw.QHBoxLayout()
        layout2b.addWidget(qtw.QLabel('Auto-data:'))
        layout2b.addWidget(self.sld_autodata)
        layout2b.addWidget(self.txt_autodata)
        layout2 = qtw.QFormLayout()
        layout2.addRow(qtw.QLabel('To:'), self.cbo_datato)
        layout2.addRow(layout2b)
        group2 = qtw.QGroupBox('Send random data')
        group2.setLayout(layout2)
        layout_main = qtw.QVBoxLayout()
        layout_main.addWidget(group0)
        layout_main.addWidget(self.txt_rcvdlist)
        layout_main.addWidget(group1)
        layout_main.addWidget(group2)
        group_main = qtw.QGroupBox(self)
        group_main.setLayout(layout_main)
        self.setCentralWidget(group_main)
        # Create timer that batch-updates message display.
        self.batch_timer = qtc.QTimer()
        self.batch_timer.timeout.connect(self.update_timer)
        # Set default window state.
        self.resize(self.minimumSize().width(), self.height())
        self.clear_msgs()
        self.update_autodata()
        self.update_autotext()
        self.update_recipients()

    def connect(self, port_obj):
        '''
        Connect to specified port object.
        Keyword arguments:
        port_obj -- AsyncEthernetPort or AsyncSLIPPort object
        '''
        # Connect and start both worker threads.
        self.port = port_obj
        self._heartbeat_run = True
        self._heartbeat_thread.start()
        self._auto_data_thread.start()
        self._auto_text_thread.start()
        self.batch_timer.start(125)     # 8 updates/sec
        # Update and launch GUI.
        self.setWindowTitle('Chat: ' + port_obj.lbl)
        self.txt_macaddr.setText(satcat5_eth.mac2str(port_obj.mac))
        self.txt_username.setText(port_obj.lbl)
        self.username = port_obj.lbl
        self.show()

    def closeEvent(self, event):
        '''
        This window or parent is closing, exit cleanly.
        (Note: This overrides the built-in closeEvent() method.)
        '''
        if self._heartbeat_run:
            self._heartbeat_run = False
            self.port.close()
            self._auto_data_thread.join()
            self._auto_text_thread.join()
            self._heartbeat_thread.join()
        if event is not None:
            event.accept()

    def clear_msgs(self):
        '''Clear accumulated messages from chat log.'''
        with self.batch_lock:
            self.txrate_kbps = 0.0
            self.rxrate_kbps = 0.0
            self.sent_count = 0
            self.rcvd_count = 0
            self.disp_msgs  = []
            self.txt_sentcount.setText('0')
            self.txt_rcvdcount.setText('0')
            self.txt_rcvdlist.clear()

    def send_user_chat(self):
        '''Send the user-entered chat message.'''
        # Grab current message before clearing it.
        msg = self.txt_sendmsg.text()
        self.txt_sendmsg.clear()
        # Send the message frame.
        self.frame_send_chat(msg)

    def update_autodata(self):
        '''Update GUI display of the random-data rate.'''
        # Get integer rate setting (0-99) from slider.
        rate_int = self.sld_autodata.value()
        if rate_int == 0:
            # Disabled
            self.auto_data_count = 0
        elif self.port.is_uart():
            # UART mode: Linear mapping from 1 - 6 pkts/interval
            self.auto_data_count = int(ceil(rate_int / 16.5))
        else:
            # GigE mode: Logarithmic mapping from 1 - 6000 pkts/interval
            self.auto_data_count = int(ceil(10**(rate_int / 26.2033)))
        # Display result next to slider.
        if rate_int > 0:
            rate_pkts = self.auto_data_count * 10   # 10 interval / sec
            rate_kbps = rate_pkts * 12              # 1500 bytes/pkt = 12 kbit/pkt
            self.txt_autodata.setText('%d kbps' % rate_kbps)
        else:
            self.txt_autodata.setText('None')

    def update_autotext(self):
        '''Update GUI display of the auto-message rate.'''
        # Get integer rate setting (0-99) from slider.
        rate_int = self.sld_autotext.value()
        # Logarithmic mapping: 0 -> 1.0, 99 -> 0.001 seconds.
        self.auto_text_delay = 10**(rate_int / -33.0)
        # Display result next to slider.
        rate_inv = (1.0/self.auto_text_delay)
        if rate_int > 0:
            self.txt_autotext.setText('%.1f/sec' % rate_inv)
        else:
            self.txt_autotext.setText('None')

    def update_recipients(self):
        '''Update GUI display for the list of potential recipients.'''
        for cbo in (self.cbo_sendto, self.cbo_datato):
            # Leave it alone if the dropdown is currently open.
            if cbo.isOpen: continue
            # Note: clear() affects list and text, so save first and restore after.
            prev = cbo.currentText()
            cbo.clear()
            cbo.addItem(self.bcast_lbl)
            for mac,lbl in self.rcvd_macs.items():
                cbo.addItem(lbl)
            cbo.setCurrentText(prev)

    def update_timer(self):
        '''
        Periodically update message display from within GUI thread.
        (This prevents crashes caused by incoming message overload.)
        '''
        self.update_recipients()
        self.update_status()

    def update_status(self):
        '''Update displayed messages and rate information.'''
        with self.batch_lock:
            # Update sent and received frame counts.
            self.txt_sentcount.setText('%d' % self.sent_count)
            self.txt_rcvdcount.setText('%d' % self.rcvd_count)
            # If there are any messages...
            if len(self.batch_msgs) > 0:
                # Append new messages, and trim old ones.
                self.disp_msgs = (self.disp_msgs + self.batch_msgs)[-self.MAX_MSGS:]
                self.batch_msgs = []
                # Update display text and scroll to latest.
                self.txt_rcvdlist.setPlainText('\n'.join(self.disp_msgs))
                self.txt_rcvdlist.moveCursor(qtg.QTextCursor.End)
            # Estimate rate over the last interval (8 intervals/sec, 8 bits/byte)
            tx_kbps = self.batch_txbytes * 0.064
            rx_kbps = self.batch_rxbytes * 0.064
            self.batch_txbytes = 0
            self.batch_rxbytes = 0
            # Running-average update for displayed Tx and Rx rates.
            self.txrate_kbps += 0.1 * (tx_kbps - self.txrate_kbps)
            self.rxrate_kbps += 0.1 * (rx_kbps - self.rxrate_kbps)
            self.txt_txrate.setText('%.1f kbps' % self.txrate_kbps)
            self.txt_rxrate.setText('%.1f kbps' % self.rxrate_kbps)

    def update_username(self):
        '''Update the username that's sent in the heartbeat message.'''
        self.username = self.txt_username.text()

    def frame_rcvd_raw(self, frame_bytes):
        '''
        Callback for each received message.
        Keyword arguments:
        frame_bytes -- Byte string containing a raw Ethernet frame.
        '''
        # Sanity check packet length.
        if len(frame_bytes) < 14:
            logger.warning(self.port.lbl + ': Packet too short.')
            return
        if len(frame_bytes) > 1550:
            logger.warning(self.port.lbl + ': Packet too long.')
            return
        # Update the received-data count.
        with self.batch_lock:
            self.rcvd_count += 1
            self.batch_rxbytes += len(frame_bytes)
        # Parse Ethernet frame into components.
        assert len(frame_bytes) > 14
        assert len(frame_bytes) < 1550
        mac_dst = frame_bytes[0:6]
        mac_src = frame_bytes[6:12]
        etype   = frame_bytes[12:14]
        payload = frame_bytes[14:]
        # Reject messages from our own source address.
        # (Network drivers may echo broadcast packets.)
        if (mac_src == self.port.mac):
            return
        # Reject messages that aren't for us.
        if (mac_dst != self.MAC_BCAST) and (mac_dst != self.port.mac):
            return
        # Handle message based on Ethertype:
        if (etype == self.ETYPE_BEAT):
            if self.LOG_VERBOSE:
                logger.info(self.port.lbl + ': Got heartbeat from ' + satcat5_eth.mac2str(mac_src))
            self.frame_rcvd_beat(mac_src, self._decode_string(payload))
        elif (etype == self.ETYPE_CHAT):
            if self.LOG_VERBOSE:
                logger.info(self.port.lbl + ': Got chat from ' + satcat5_eth.mac2str(mac_src))
            self.frame_rcvd_chat(mac_src, self._decode_string(payload))
        elif (etype == self.ETYPE_DATA):
            if self.LOG_VERBOSE:
                logger.info(self.port.lbl + ': Got data from ' + satcat5_eth.mac2str(mac_src))
        else:
            [etype_int] = unpack('>H', etype)
            logger.info(self.port.lbl + ': Unrecognized EtherType 0x%04X' % etype_int)

    def _decode_string(self, payload):
        '''
        Decode string from chat or heartbeat frame (payload only)
        Some errors are expected; just return an empty string.
        Keyword arguments:
        payload -- Byte string containing only the payload of a chat or heartbeat frame.
        '''
        # Sanity check before reading length:
        if len(payload) < 2:
            return ''   # Nothing to decode here
        msg_len = unpack('>H', payload[0:2])[0]
        # Confirm length is valid.
        if (msg_len < 1) or (msg_len+2 > len(payload)):
            return ''   # Invalid length
        try:
            return payload[2:2+msg_len].decode()
        except:
            return ''   # UTF-8 decoder error

    def _format_address(self, mac_src, label=''):
        if label:
            return satcat5_eth.mac2str(mac_src) + ' (%s)' % label
        else:
            return satcat5_eth.mac2str(mac_src)

    def frame_rcvd_beat(self, mac_src, msg_str):
        '''
        Received heartbeat message, update recipient list as needed.
        Keyword arguments:
        mac_src -- Byte string, length 6, containing the sender's MAC address.
        msg_str -- Decoded username string, see _decode_string(...).
        '''
        # Add new or updated recipient (MAC + label) to the list.
        lbl_str = self._format_address(mac_src, msg_str)
        logger.info(self.port.lbl + ': Got heartbeat ' + lbl_str)
        self.rcvd_macs[mac_src] = lbl_str

    def frame_rcvd_chat(self, mac_src, msg_str):
        '''
        Received chat message, update displayed list.
        Keyword arguments:
        mac_src -- Byte string, length 6, containing the sender's MAC address.
        msg_str -- Decoded message string, see _decode_string(...).
        '''
        # Inspect message contents.
        if len(msg_str) == 0:
            logger.error(self.port.lbl + ': Invalid chat message.')
            return
        if not msg_str.endswith('\n'):
            msg_str += '\n'
        # Format message (including sender information)
        if mac_src in self.rcvd_macs.keys():
            lbl_src = self.rcvd_macs[mac_src]
        else:
            lbl_src = satcat5_eth.mac2str(mac_src)
        msg_txt = 'From ' + lbl_src + ':\n' + msg_str
        # Queue this message for next GUI update.
        with self.batch_lock:
            self.batch_msgs.append(msg_txt)

    def frame_send_chat(self, msg):
        '''
        Send the current chat message, if any.
        Keyword arguments:
        msg -- The message string to be sent.
        '''
        # Sanity-check length.
        if len(msg) < 1:
            return
        if len(msg) > 1000:
            msg = msg[:1000]
        # Construct and send packet.
        mac_dst = satcat5_eth.str2mac(self.cbo_sendto.currentText())
        mac_src = self.port.mac
        payload = pack('>H', len(msg)) + msg.encode()
        self._frame_send(mac_dst + mac_src + self.ETYPE_CHAT + payload)

    def _auto_data_loop(self):
        '''Send auto-generated data at regular intervals.'''
        while self._heartbeat_run:
            # If enabled, send N identical packets.
            if self.auto_data_count > 0:
                # Construct the reference packet.
                mac_dst = satcat5_eth.str2mac(self.cbo_datato.currentText())
                mac_src = self.port.mac
                pkt_dat = mac_dst + mac_src + self.ETYPE_DATA + random.bytes(1486)
                # Send the same packet N times.
                for n in range(self.auto_data_count):
                    self._frame_send(pkt_dat)
            # Sleep for a brief interval.
            time.sleep(0.1)

    def _auto_text_loop(self):
        '''Send auto-generated text at regular intervals.'''
        while self._heartbeat_run:
            # If enabled, send next line of auto-text.
            rate = self.sld_autotext.value()
            if rate > 0:
                line = next(self._auto_text_gen)
                self.frame_send_chat(line)
            # Sleep for a brief interval.
            time.sleep(self.auto_text_delay)

    def _heartbeat_loop(self):
        '''Send heartbeat packets at regular intervals.'''
        # Keep sending it until told to stop...
        while self._heartbeat_run:
            payload = pack('>H', len(self.username)) + self.username.encode()
            beat_msg = self.MAC_BCAST + self.port.mac + self.ETYPE_BEAT + payload
            self._frame_send(beat_msg)
            time.sleep(1.0)

    def _frame_send(self, msg):
        '''
        Send the given Ethernet frame.
        Keyword arguments:
        msg -- Byte string containing a valid Ethernet frame.
        '''
        # Send the given message.
        self.port.msg_send(msg)
        # Update the transmit-data count.
        with self.batch_lock:
            self.sent_count += 1
            self.batch_txbytes += len(msg)

class ChatControl(qtw.QMainWindow):
    '''GUI window for setting up FPGA and launching other windows.'''
    MAX_MSGS = 100

    def __init__(self):
        super().__init__()
        # Internal variables
        self.children   = []    # List of child dialogs
        self.batch_msgs = []    # Thread-safe queue for status messages
        self.batch_lock = threading.Lock()
        self.disp_msgs  = []    # List of status messages
        self.msg_count  = 0     # Count of status messages
        self.msg_rate   = 0.0   # Rate of status messages
        # Create config interface objects, but don't connect yet.
        self.serial = satcat5_uart.AsyncSerialPort(logger, self.msg_rcvd)
        # Create GUI elements.
        self.setWindowTitle('Switch Configuration')
        self.cbo_config = qtw.QComboBox(self)
        self.cbo_config.activated[str].connect(self.open_control)
        self.chk_eth0rgmii = qtw.QCheckBox('Eth0 RGMII', self)
        self.chk_eth0rgmii.stateChanged.connect(self.config_change)
        self.chk_eth2sgmii = qtw.QCheckBox('Eth2 SGMII', self)
        self.chk_eth3sgmii = qtw.QCheckBox('Eth3 SGMII', self)
        self.chk_extclk = qtw.QCheckBox('External clock', self)
        self.btn_config = qtw.QPushButton('Load Config', self)
        self.btn_config.clicked.connect(self.config_reset)
        self.txt_msgcount = qtw.QLineEdit(self)
        self.txt_msgcount.setReadOnly(True)
        self.txt_msgrate = qtw.QLineEdit(self)
        self.txt_msgrate.setReadOnly(True)
        self.btn_msgclear = qtw.QPushButton('Clear', self)
        self.btn_msgclear.clicked.connect(self.clear_msgs)
        self.txt_msglist = qtw.QPlainTextEdit(self)
        self.txt_msglist.setReadOnly(True)
        self.cbo_client = qtw.QComboBox(self)
        self.cbo_client.activated[str].connect(self.open_client)
        # Populate the two interface lists.
        self.list_eth = satcat5_eth.list_eth_interfaces()
        self.list_uart = satcat5_uart.list_uart_interfaces()
        for lbl in self.list_uart.keys():
            self.cbo_config.addItem(lbl)
            self.cbo_client.addItem(lbl)
        for lbl in self.list_eth.keys():
            self.cbo_client.addItem(lbl)
        # Create GUI layout.
        layout0 = qtw.QFormLayout()
        layout0.addRow(qtw.QLabel('Port:'), self.cbo_config)
        layout0.addRow(self.chk_eth0rgmii)
        layout0.addRow(self.chk_eth2sgmii)
        layout0.addRow(self.chk_eth3sgmii)
        layout0.addRow(self.chk_extclk)
        layout0.addRow(self.btn_config)
        group0 = qtw.QGroupBox('Configuration')
        group0.setLayout(layout0)
        layout1 = qtw.QHBoxLayout()
        layout1.addWidget(qtw.QLabel('Rate:'))
        layout1.addWidget(self.txt_msgrate)
        layout1.addWidget(qtw.QLabel('Total:'))
        layout1.addWidget(self.txt_msgcount)
        layout1.addWidget(self.btn_msgclear)
        group1 = qtw.QGroupBox('Status')
        group1.setLayout(layout1)
        layout2 = qtw.QFormLayout()
        layout2.addRow(qtw.QLabel('Port:'), self.cbo_client)
        group2 = qtw.QGroupBox('Clients')
        group2.setLayout(layout2)
        layout_main = qtw.QVBoxLayout()
        layout_main.addWidget(group0)
        layout_main.addWidget(group1)
        layout_main.addWidget(self.txt_msglist)
        layout_main.addWidget(group2)
        group_main = qtw.QGroupBox(self)
        group_main.setLayout(layout_main)
        self.setCentralWidget(group_main)
        # Create timer that batch-updates message display.
        self.batch_timer = qtc.QTimer()
        self.batch_timer.timeout.connect(self.update_timer)
        self.batch_timer.start(125)     # 8 updates/sec
        # Put window in default state.
        self.resize(self.minimumSize().width(), self.height())
        self.clear_msgs()
        self.config_change()
        self.show()

    def clear_msgs(self):
        '''Clear accumulated messages from output log.'''
        self.msg_count = 0
        self.msg_rate  = 0.0
        self.disp_msgs = []
        self.txt_msgrate.setText('0.0')
        self.txt_msgcount.setText('0')
        self.txt_msglist.clear()

    def closeEvent(self, event):
        '''
        Window closing, exit application cleanly.
        (Note: This overrides the built-in closeEvent() method.)
        '''
        # Close all open interfaces (including children).
        self.serial.close()
        for c in self.children:
            c.close()
        # Proceed with Qt cleanup.
        event.accept()

    def config_change(self):
        '''Update window state based on configuration checkboxes.'''
        if self.chk_eth0rgmii.isChecked():
            # RGMII mode --> Allow changes to SGMII options.
            self.chk_eth2sgmii.setEnabled(True)
            self.chk_eth3sgmii.setEnabled(True)
            self.chk_extclk.setEnabled(True)
        else:
            # RMII mode --> SGMII is not supported.
            self.chk_eth2sgmii.setEnabled(False)
            self.chk_eth3sgmii.setEnabled(False)
            self.chk_extclk.setEnabled(False)

    def config_reset(self):
        '''Load configuration data for switch and FPGA.'''
        eth0rgmii = self.chk_eth0rgmii.isChecked()
        eth2sgmii = self.chk_eth2sgmii.isChecked()
        eth3sgmii = self.chk_eth3sgmii.isChecked()
        extclk = self.chk_extclk.isChecked()
        try:
            logger.info('Starting switch configuration...')
            cfg = switch_cfg.SwitchConfig(self.serial)
            cfg.reset_all(eth0rgmii, eth2sgmii, eth3sgmii, extclk)
            logger.info('Done!')
        except:
            logger.error('Configuration error:\n' + traceback.format_exc())

    def msg_rcvd(self, text):
        '''
        Status message received from switch FPGA.
        Keyword arguments:
        text -- UART status message to be displayed.
        '''
        # Add new text to the intermediate buffer.
        with self.batch_lock:
            try:
                self.batch_msgs.append(text.decode())
            except:
                logger.error('Invalid status message: %s\n', text)
                self.batch_msgs.append('UNKNOWN')

    def update_timer(self):
        '''
        Periodically update message display from within GUI thread.
        (This prevents crashes caused by incoming message overload.)
        '''
        with self.batch_lock:
            # Running-average update for received messages per second.
            new_msgs = len(self.batch_msgs)
            self.msg_rate += 0.05 * (8.0*new_msgs - self.msg_rate)
            self.txt_msgrate.setText('%.1f' % self.msg_rate)
            # If there are any messages...
            if new_msgs > 0:
                # Update received-message count.
                self.msg_count += new_msgs
                self.txt_msgcount.setText('%d' % self.msg_count)
                # Append new messages, and trim old ones.
                self.disp_msgs = (self.disp_msgs + self.batch_msgs)[-self.MAX_MSGS:]
                self.batch_msgs = []
                # Update display text and scroll to latest.
                self.txt_msglist.setPlainText('\n'.join(self.disp_msgs))
                self.txt_msglist.moveCursor(qtg.QTextCursor.End)

    def open_control(self, port_name):
        '''
        Open or re-open the hardware control interface.
        Selected port should be a member of self.list_uart.keys().
        Keyword arguments:
        port_name -- Name of the selected UART.
        '''
        # Note: port_name may be OS-name or full description.
        if port_name in self.list_uart.keys():
            # Already have the long name (user-selected)
            os_name = self.list_uart[port_name]
        else:
            # Reverse lookup to update GUI display.
            matches = [k for k,v in self.list_uart.items() if v == port_name]
            if len(matches) == 0:
                self.cbo_config.setCurrentText(port_name)   # No match
            else:
                self.cbo_config.setCurrentText(matches[0])  # First match
            os_name = port_name
        # Open the specified serial port.
        self.serial.close()
        self.serial.open(os_name)

    def open_client(self, port_name):
        '''
        Open a new chat client with specified interface.
        Selected port should be a member of self.list_uart.keys() or
        self.list_eth.keys().
        Keyword arguments:
        port_name -- Name of the selected UART or Ethernet port.
        '''
        # Open the appropriate port type.
        if port_name in self.list_uart.keys():
            obj = satcat5_uart.AsyncSLIPPort(
                self.list_uart[port_name], logger)
        elif port_name in self.list_eth.keys():
            obj = satcat5_eth.AsyncEthernetPort(
                port_name, self.list_eth[port_name], logger)
        else:
            logger.warning('No such port name')
            return
        self._open_client_obj(obj)

    def _open_client_obj(self, port_obj):
        '''Post-validation helper for open_client()'''
        client = ChatClient()
        client.connect(port_obj)
        port_obj.set_callback(client.frame_rcvd_raw)
        self.children.append(client)


if __name__ == '__main__':
    # Main function: Instantiate and run GUI.
    # Configure logging to print to console.
    logger.addHandler(logging.StreamHandler(sys.stdout))
    # Create the main GUI window.
    logger.info('Starting main GUI...')
    app = qtw.QApplication([])
    gui = ChatControl()
    # Execute command line arguments (if any)
    if len(sys.argv) > 1:
        # First is the name of the command interface.
        gui.open_control(sys.argv[1])
    for n in range(2, len(sys.argv)):
        # Any others are names of test interfaces.
        gui.open_client(sys.argv[n])
    # Start the GUI!
    try:
        sys.exit(app.exec_())
        logger.info('Exiting...')
    except Exception as e:
        print("Error: %s" % e)
        sys.exit(1)
