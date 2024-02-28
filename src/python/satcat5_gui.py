#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Wrappers for PyQt GUI elements that provide additional features.
"""

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
