#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2021 The Aerospace Corporation
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
