#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Wrappers for PyQt GUI elements that provide additional features.
"""

import logging
import PyQt5.QtCore as qtc
import PyQt5.QtWidgets as qtw

class BetterComboBox(qtw.QComboBox):
    """Variant of QComboBox which indicates when user opens the dropdown."""
    openEvent = qtc.pyqtSignal()
    closeEvent = qtc.pyqtSignal()
    isOpen = False

    def showPopup(self):
        self.isOpen = True
        self.openEvent.emit()
        super(BetterComboBox, self).showPopup()

    def hidePopup(self):
        self.isOpen = False
        self.closeEvent.emit()
        super(BetterComboBox, self).hidePopup()

class LogDisplay(logging.StreamHandler):
    """Helper object for appending Python log messages to a PyQT textbox."""
    def __init__(self, txtbox):
        super().__init__()
        self.txtbox = txtbox
        logging.getLogger(__name__).addHandler(self)

    def close(self):
        '''Graceful shutdown of this handler.'''
        self.txtbox = None

    def emit(self, record):
        '''
        The "emit" handler is called by parent class for each log message.
        If the level exceeds a threshold, append the contents of that message.
        '''
        if self.txtbox and record.levelno >= logging.WARNING:
            self.txtbox.appendPlainText('%s\t%s' % (record.levelname, record.msg))

class ReadOnlyCheckBox(qtw.QCheckBox):
    """Variant of QCheckBox for information display only.
       Use the setCheckState(...) method to set display state."""
    def __init__(self, *args, **kwargs):
        qtw.QCheckBox.__init__(self, *args, **kwargs)
        self.setTristate(True)
        self.setCheckState(qtc.Qt.PartiallyChecked)

    # Override and ignore all events that would change state.
    def mousePressEvent(self, event):
        event.accept()
    def mouseMoveEvent(self, event):
        event.accept()
    def mouseReleaseEvent(self, event):
        event.accept()
    def keyPressEvent(self, event):
        event.accept()
