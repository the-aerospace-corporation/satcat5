//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Basic type aliases and prototypes used throughout SatCat5

#pragma once

#include <cinttypes>

// Allow safe destruction of SatCat5 objects?
// Many embedded systems never need to delete anything, and disabling this
// feature can save several kilobytes of code-size.  Use with caution.
// For GCC/G++: compiler flag "-DSATCAT5_ALLOW_DELETION=0" to disable.
#ifndef SATCAT5_ALLOW_DELETION
#define SATCAT5_ALLOW_DELETION  1
#endif

#if SATCAT5_ALLOW_DELETION
#define SATCAT5_OPTIONAL_DTOR       // Full function defined elsewhere
#else
#define SATCAT5_OPTIONAL_DTOR {}    // Null inline placeholder
#endif

// Enable use of the QCBOR library?
// For GCC/G++: compiler flag "-DSATCAT5_QCBOR_ENABLE=1" to enable.
#ifndef SATCAT5_QCBOR_ENABLE
#define SATCAT5_QCBOR_ENABLE 0
#endif

// Shortcuts for fixed-size integer types.
typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;
typedef int8_t      s8;
typedef int16_t     s16;
typedef int32_t     s32;
typedef int64_t     s64;

// Prototypes for widely-used interfaces and data-structures.
// (Comment indicates the file containing the full definition.)
namespace satcat5 {
    namespace cfg {                 // ConfigBus and peripherals
        struct TrafficStats;        // satcat5/cfgbus_stats.h
        class ConfigBus;            // satcat5/cfgbus_core.h
        class ConfigBusMmap;        // satcat5/cfgbus_core.h
        class ConfigBusRemote;      // satcat5/cfgbus_remote.h
        class GpiRegister;          // satcat5/cfgbus_gpio.h
        class GpoRegister;          // satcat5/cfgbus_gpio.h
        class I2c;                  // satcat5/cfgbus_i2c.h
        class I2cEventListener;     // satcat5/cfgbus_i2c.h
        class Interrupt;            // satcat5/cfgbus_interrupt.h
        class LedArray;             // satcat5/cfgbus_led.h
        class Mdio;                 // satcat5/cfgbus_mdio.h
        class MdioEventListener;    // satcat5/cfgbus_mdio.h
        class MdioLogger;           // satcat5/cfgbus_mdio.h
        class MdioWrapper;          // satcat5/cfgbus_mdio.h
        class MultiSerial;          // satcat5/cfgbus_multiserial.h
        class NetworkStats;         // satcat5/cfgbus_stats.h
        class PtpRealtime;          // satcat5/cfgbus_ptpref.h
        class PtpReference;         // satcat5/cfgbus_ptpref.h
        class Spi;                  // satcat5/cfgbus_spi.h
        class SpiEventListener;     // satcat5/cfgbus_spi.h
        class Timer;                // satcat5/cfgbus_timer.h
        class Uart;                 // satcat5/cfgbus_uart.h
        class WrappedRegister;      // satcat5/cfgbus_core.h
        class WrappedRegisterPtr;   // satcat5/cfgbus_core.h
    }

    namespace datetime {            // Human-readable date and time
        struct GpsTime;             // satcat5/datetime.h
        struct RtcTime;             // satcat5/datetime.h
        class Clock;                // satcat5/datetime.h
        class IpClock;              // satcat5/datetime.h
    }

    namespace eth {                 // Ethernet networking
        struct Header;              // satcat5/eth_header.h
        struct MacAddr;             // satcat5/eth_header.h
        struct MacType;             // satcat5/eth_header.h
        struct VlanTag;             // satcat5/eth_header.h
        class Address;              // satcat5/eth_address.h
        class ArpListener;          // satcat5/eth_arp.h
        class ChecksumRx;           // satcat5/eth_checksum.h
        class ChecksumTx;           // satcat5/eth_checksum.h
        class ConfigBus;            // satcat5/cfgbus_remote.h
        class Dispatch;             // satcat5/eth_dispatch.h
        class Protocol;             // satcat5/eth_protocol.h
        class ProtoArp;             // satcat5/eth_arp.h
        class ProtoConfig;          // satcat5/net_cfgbus.h
        class ProtoEcho;            // satcat5/net_echo.h
        class SlipCodec;            // satcat5/eth_checksum.h
        class Socket;               // satcat5/eth_socket.h
        class SocketCore;           // satcat5/eth_socket.h
        class SwitchConfig;         // satcat5/switch_cfg.h
        class Telemetry;            // satcat5/net_telemetry.h
    };

    namespace io {                  // Input and output streams
        class ArrayRead;            // satcat5/io_readable.h
        class ArrayWrite;           // satcat5/io_writeable.h
        class BufferedCopy;         // satcat5/io_buffer.h
        class BufferedIO;           // satcat5/io_buffer.h
        class BufferedWriter;       // satcat5/io_buffer.h
        class EventListener;        // satcat5/io_readable.h
        class LimitedRead;          // satcat5/io_readable.h
        class PacketBuffer;         // satcat5/pkt_buffer.h
        class Readable;             // satcat5/io_readable.h
        class ReadableRedirect;     // satcat5/io_readable.h
        class SlipCodec;            // satcat5/slip.h
        class SlipDecoder;          // satcat5/slip.h
        class SlipEncoder;          // satcat5/slip.h
        class Writeable;            // satcat5/io_writeable.h
        class WriteableRedirect;    // satcat5/io_writeable.h
    }

    namespace ip {                  // Internet Protocol v4
        struct Addr;                // satcat5/ip_core.h
        struct Header;              // satcat5/ip_core.h
        struct Mask;                // satcat5/ip_core.h
        struct Port;                // satcat5/ip_core.h
        struct Subnet;              // satcat5/ip_core.h
        class Address;              // satcat5/ip_address.h
        class DhcpClient;           // satcat5/ip_dhcp.h
        class DhcpServer;           // satcat5/ip_dhcp.h
        class Dispatch;             // satcat5/ip_dispatch.h
        class Ping;                 // satcat5/ip_ping.h
        class ProtoIcmp;            // satcat5/ip_icmp.h
        class Stack;                // satcat5/ip_stack.h
    }

    namespace irq {                 // Interrupt handling
        class AtomicLock;           // satcat5/interrupts.h
        class Controller;           // satcat5/interrupts.h
        class Handler;              // satcat5/interrupts.h
        class Shared;               // satcat5/interrupts.h
        class VirtualTimer;         // satcat5/polling.h
    }

    namespace log {                 // Logging
        class EventHandler;         // satcat5/log.h
        class Log;                  // satcat5/log.h
        class LogBuffer;            // satcat5/log.h
        class ToWriteable;          // satcat5/log.h
    }

    namespace net {                 // Generic networking
        struct Type;                // satcat5/net_type.h
        class Address;              // satcat5/net_address.h
        class Dispatch;             // satcat5/net_dispatch.h
        class Protocol;             // satcat5/net_protocol.h
        class ProtoConfig;          // satcat5/net_cfgbus.h
        class SocketCore;           // satcat5/net_socket.h
        class TelemetryAggregator;  // satcat5/net_telemetry.h
        class TelemetrySource;      // satcat5/net_telemetry.h
        class TelemetryTier;        // satcat5/net_telemetry.h
    }

    namespace poll {                // Queued-task servicing
        class Always;               // satcat5/polling.h
        class OnDemand;             // satcat5/polling.h
        class Timer;                // satcat5/polling.h
        class TimerAdapter;         // satcat5/polling.h
    }

    namespace port {                // Network ports
        class Mailbox;              // satcat5/port_mailbox.h
        class Mailmap;              // satcat5/port_mailmap.h
        class SerialGeneric;        // satcat5/port_serial.h
        class SerialAuto;           // satcat5/port_serial.h
        class SerialI2cController;  // satcat5/port_serial.h
        class SerialI2cPeripheral;  // satcat5/port_serial.h
        class SerialSpiController;  // satcat5/port_serial.h
        class SerialSpiPeripheral;  // satcat5/port_serial.h
        class SerialUart;           // satcat5/port_serial.h
    }

    namespace ptp {                 // Precision Time Protocol (PTP)
        class Time;                 // satcat5/ptp_time.h
        class TrackingClock;        // satcat5/ptp_tracking.h
        struct TrackingCoeff;       // satcat5/ptp_tracking.h
        class TrackingDither;       // satcat5/ptp_tracking.h
        class TrackingController;   // satcat5/ptp_tracking.h
    }

    namespace udp {                 // UDP networking
        class Address;              // satcat5/udp_core.h
        class ConfigBus;            // satcat5/cfgbus_remote.h
        class Dispatch;             // satcat5/udp_dispatch.h
        class ProtoConfig;          // satcat5/net_cfgbus.h
        class ProtoEcho;            // satcat5/net_echo.h
        class Socket;               // satcat5/udp_socket.h
        class SocketCore;           // satcat5/udp_socket.h
        class Telemetry;            // satcat5/net_telemetry.h
    }

    namespace util {                // Other utilities
        class GenericTimer;         // satcat5/timer.h
        struct I2cAddr;             // satcat5/cfg_i2c.h
        class ListCore;             // satcat5/list.h
        template <class T>
            class List;             // satcat5/list.h
        class Prng;                 // satcat5/utils.h
        class RunningMax;           // satcat5/utils.h
        class TimerRegister;        // satcat5/timer.h
        template <unsigned W>
            struct UintWide;        // satcat5/uint_wide.h
    }
}
