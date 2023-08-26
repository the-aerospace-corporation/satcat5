# -*- coding: utf-8 -*-

# Copyright 2023 The Aerospace Corporation
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
Console demo for remote control of the "arty_managed" OLED

The application opens the designated UART interface, then begins sending
a repeating sequence of updates to the OLED display.
"""

# Python library imports
import logging, os, sys, time
from datetime import datetime
from traceback import format_exception

# Additional imports from SatCat5 core.
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', '..', 'src', 'python'))
import satcat5_cfgbus
import satcat5_i2c
import satcat5_oled
import satcat5_uart

# Start logging system.
logger = logging.getLogger(__name__)
logger.info('Starting logger...')
logger.setLevel('INFO')

# MAC addresses for the Ethernet-over-UART interface.
REMOTE_MAC = b'\xDE\xAD\xBE\xEF\xCA\xFE'

# ConfigBus address for the I2C controller:
DEVADDR_I2C = 10

class ArtyDemo:
    def __init__(self, if_obj):
        """Create a demo controller linked to the designated interface."""
        # Create each of the driver objects:
        self.cfg = satcat5_cfgbus.ConfigBus(if_obj, REMOTE_MAC)
        self.i2c = satcat5_i2c.I2cController(self.cfg, DEVADDR_I2C)
        self.oled = satcat5_oled.Ssd1306(self.i2c)
        # Counter cycles between display modes.
        self.cycle = 0

    def ok(self):
        """Connectivity test."""
        regval = self.cfg.read_reg(DEVADDR_I2C, 0)
        return regval is not None

    def display_next(self):
        """Write the next message to the OLED display."""
        # Format the current time.
        day = datetime.now().strftime('%Y-%m-%d')
        now = datetime.now().strftime('%H:%M:%S')
        # Generate the complete message...
        if self.cycle == 0:
            msg = f'Time: {now:9s} Date: {day}'
        elif self.cycle == 1:
            msg = f'Time: {now:9s} SatCat5 demo!'
        else:
            msg = f'Time: {now:9s} Meow meow meow.'
        # Update message index and write to screen.
        ok = self.oled.display(msg)
        if ok:
            self.cycle = (self.cycle + 1) % 3
            logger.info(msg)
        else:
            logger.error('Error updating OLED.')
        return ok

    def run_forever(self):
        """Write a new message every second until user hits Ctrl+C."""
        while self.display_next():
            time.sleep(1.0)

# Main function: Initialize and run the demo.
if __name__ == '__main__':
    # Configure logging to print to console.
    logger.addHandler(logging.StreamHandler(sys.stdout))
    # User must specify the UART port to select.
    if len(sys.argv) > 1:
        uart_name = sys.argv[1]
    else:
        print('Usage: python3 oled_demo.py [uart_name]')
        print('  Where "ifname" is the USB-UART attached to the arty_managed FPGA.')
        sys.exit(1)
    # Start application and catch any errors.
    try:
        port = satcat5_uart.AsyncSLIPPort(uart_name, logger)
        demo = ArtyDemo(port)
        if demo.ok():
            demo.run_forever()
        else:
            logger.error('Could not connect to I2C interface.')
            sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        logger.error("Error: %s" % format_exception(e))
        sys.exit(1)
