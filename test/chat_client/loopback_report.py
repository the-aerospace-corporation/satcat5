#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2020-2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
GUI for displaying test results from the "config_stats" block

Dependencies: PySerial
'''

# Standard libraries
import logging, os, sys, threading, traceback
import PyQt5.QtCore as qtc
import PyQt5.QtGui as qtg
import PyQt5.QtWidgets as qtw
from struct import unpack

# Additional imports from SatCat5 core.
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))
import satcat5_uart
from satcat5_gui import BetterComboBox

# Start logging system.
logger = logging.getLogger(__name__)
logger.info('Starting logger...')
logger.setLevel('INFO')

class LoopbackGUI(qtw.QMainWindow):
    '''GUI window for displaying loopback test results.'''

    def __init__(self):
        '''Initialize this class.'''
        super().__init__()
        self.batch_lock = threading.Lock()
        self.report_new = False
        self.report_str = '--WAITING--'
        self.uart = None
        # Create GUI elements
        self.cbo_uart = BetterComboBox(self)
        self.cbo_uart.activated[str].connect(self.open_uart)
        self.txt_report = qtw.QPlainTextEdit(self)
        self.txt_report.setReadOnly(True)
        self.txt_report.setMinimumHeight(120)
        self.txt_status = qtw.QLineEdit(self)
        self.txt_status.setReadOnly(True)
        # Create GUI layout
        layout_main = qtw.QVBoxLayout()
        layout_main.addWidget(self.cbo_uart)
        layout_main.addWidget(self.txt_report)
        layout_main.addWidget(self.txt_status)
        group_main = qtw.QGroupBox(self)
        group_main.setLayout(layout_main)
        self.setCentralWidget(group_main)
        # Setup list of UART interfaces.
        self.list_uart = satcat5_uart.list_uart_interfaces()
        for lbl in self.list_uart.keys():
            self.cbo_uart.addItem(lbl)
        # Start a timer for refreshing the display.
        self.disp_timer = qtc.QTimer()
        self.disp_timer.timeout.connect(self._refresh)
        self.disp_timer.start(125)      # 8x / second
        # Display the GUI window.
        self.setWindowTitle('Loopback-Report')
        self.show()

    def open_uart(self, port_name):
        '''Open UART by user-readable name.'''
        self.close_uart()
        if port_name in self.list_uart:
            logger.info('Connecting to UART port: %s' % port_name)
            self._open_uart_object(satcat5_uart.AsyncSLIPPort(
                self.list_uart[port_name], logger, baudrate=115200, eth_fcs=False))
        else:
            logger.warning('Connection failed, no such port name: %s' % port_name)
            self.close_uart()

    def close_uart(self):
        '''Close the active UART device, if any.'''
        if self.uart is not None:
            self.uart.close()
            self.uart = None

    def _open_uart_object(self, port_obj):
        '''Open the designated UART object.'''
        self.uart = port_obj
        self.uart.set_callback(self._pkt_rcvd)

    def _pkt_rcvd(self, msg):
        '''Callback for received UART messages.'''
        # Note: This is not the GUI thread, update asynchronously.
        logger.info('Received %d bytes' % len(msg))
        report = ''
        try:
            nports = len(msg) // 12
            for n in range(nports):
                [ntx, nbad, ngood] = unpack('>III', msg[12*n:12*n+12])
                report += 'Port %d:\tTx %u\tRx %u\tErr %u\n' % (n, ntx, nbad+ngood, nbad)
        except:
            logger.error(traceback.format_exc())
            report = '--ERROR--'
        with self.batch_lock:
            self.report_new = True
            self.report_str = report

    def _refresh(self):
        with self.batch_lock:
            if self.report_new:
                self.txt_report.setPlainText(self.report_str)
                self.txt_status.setText('OK')
            else:
                self.txt_status.setText('--')
            self.report_new = False

if __name__ == '__main__':
    '''Main function: Instantiate and run GUI.'''
    # Configure logging to print to console.
    logger.addHandler(logging.StreamHandler(sys.stdout))
    # Create the main GUI window.
    logger.info('Starting main GUI...')
    app = qtw.QApplication([])
    gui = LoopbackGUI()
    # If command-line specifies a UART name, open the closest match.
    if len(sys.argv) > 1:
        name = sys.argv[1].lower()
        for port in gui.list_uart.keys():
            if port.lower().startswith(name):
                gui.open_uart(port)
                break
    try:
        sys.exit(app.exec_())
        logger.info('Exiting...')
    except Exception as e:
        print("Error: %s" % e)
        sys.exit(1)
