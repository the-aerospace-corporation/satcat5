//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstdio>
#include <hal_posix/posix_uart.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

// Additional includes for specific platforms:
#if SATCAT5_WIN32
    #include <windows.h>        // All-in-one for Win32 API
    #undef ERROR                // Deconflict Windows "ERROR" macro
#else
    #include <fcntl.h>          // Various file-related constants
    #include <termios.h>        // Termios and related constants
    #include <unistd.h>         // For open(), close(), etc.
    #include <sys/ioctl.h>      // For ioctl() etc.

    // POSIX support for rates above 230 kbaud is optional.
    #ifndef B460800
        #define B460800     0
        #define B500000     0
        #define B576000     0
        #define B921600     0
        #define B1000000    0
        #define B1152000    0
        #define B1500000    0
        #define B2000000    0
    #endif

    // Baud-rate lookup for the predefined constants.
    inline tcflag_t baud_lookup(unsigned baud) {
        switch(baud) {
        case 9600: return B9600;
        case 19200: return B19200;
        case 38400: return B38400;
        case 57600: return B57600;
        case 115200: return B115200;
        case 230400: return B230400;
        case 460800: return B460800;
        case 500000: return B500000;
        case 576000: return B576000;
        case 921600: return B921600;
        case 1000000: return B1000000;
        case 1152000: return B1152000;
        case 1500000: return B1500000;
        case 2000000: return B2000000;
        default: return 0;
        }
    }
#endif

using satcat5::io::PosixUart;
using satcat5::io::SlipUart;
using satcat5::util::min_unsigned;
namespace log = satcat5::log;

PosixUart::PosixUart(const char* device, unsigned baud, unsigned buffer_size_bytes)
    : satcat5::io::BufferedIO(
        new u8[buffer_size_bytes], buffer_size_bytes, 0,    // Tx buffer
        new u8[buffer_size_bytes], buffer_size_bytes, 0)    // Rx buffer
    , m_ok(true)
    , m_uart(0)
{
    // Platform-specific calls to open and configure the UART.
#if SATCAT5_WIN32
    // Convert short name to full device name ("COM3" -> "\\.\COM3")
    char full_name[32];
    snprintf(full_name, sizeof(full_name), "\\\\.\\%s", device);

    // Open the device.
    m_uart = CreateFile(full_name,
        GENERIC_READ | GENERIC_WRITE,
        0, NULL, OPEN_EXISTING, 0, NULL);

    // Set configuration.
    DCB dcb;
    m_ok = m_ok && GetCommState(m_uart, &dcb);
    if (m_ok) {
        dcb.BaudRate        = baud;
        dcb.fBinary         = 1;
        dcb.fParity         = 0;
        dcb.fOutxCtsFlow    = 0;
        dcb.fOutxDsrFlow    = 0;
        dcb.fDtrControl     = DTR_CONTROL_DISABLE;
        dcb.fDsrSensitivity = 0;
        dcb.fTXContinueOnXoff = 0;
        dcb.fOutX           = 0;
        dcb.fInX            = 0;
        dcb.fErrorChar      = 0;
        dcb.fNull           = 0;
        dcb.fRtsControl     = RTS_CONTROL_HANDSHAKE;
        dcb.fAbortOnError   = 0;
        dcb.wReserved       = 0;
        dcb.ByteSize        = 8;
        dcb.Parity          = NOPARITY;
        dcb.StopBits        = ONESTOPBIT;
        m_ok = !!SetCommState(m_uart, &dcb);
    }

    // Disable read timeouts (i.e., always return immediately)
    // https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-commtimeouts
    COMMTIMEOUTS timeout;
    m_ok = m_ok && GetCommTimeouts(m_uart, &timeout);
    if (m_ok) {
        timeout.ReadIntervalTimeout = MAXDWORD;
        timeout.ReadTotalTimeoutMultiplier = 0;
        timeout.ReadTotalTimeoutConstant = 0;
        m_ok = !!SetCommTimeouts(m_uart, &timeout);
    }

    // If an error occurred, log the error number.
    if (!m_ok) {
        s32 errnum = GetLastError();
        log::Log(log::ERROR, "UART setup error").write10(errnum);
    }

#else
    // Open the specified device.
    m_uart = open(device, O_RDWR | O_NDELAY | O_NOCTTY);
    m_ok = m_ok && (m_uart >= 0);

    // Attempt baud-rate lookup.
    tcflag_t bcode = baud_lookup(baud);
    m_ok = m_ok && (bcode != 0);

    // Set terminal options using the legacy API.
    struct termios tty;
    m_ok = m_ok && (tcgetattr(m_uart, &tty) >= 0);
    if (m_ok) {
        tty.c_iflag = IGNBRK | IGNPAR;
        tty.c_oflag = 0;
        tty.c_cflag = CS8 | CREAD | CLOCAL;
        tty.c_lflag = 0;
        cfsetispeed(&tty, bcode);
        cfsetospeed(&tty, bcode);
        m_ok = (tcsetattr(m_uart, TCSANOW, &tty) >= 0);
    }

    // Ignore CTS, but keep RTS asserted.
    int rts_flag = TIOCM_RTS;
    m_ok = m_ok && (ioctl(m_uart, TIOCMBIS, &rts_flag) >= 0);
#endif
}

PosixUart::~PosixUart()
{
    // Close platform-specific device.
#if SATCAT5_WIN32
    CloseHandle(m_uart);
#else
    close(m_uart);
#endif

    // Free Tx and Rx buffers.
    delete[] m_tx.get_buff_dtor();
    delete[] m_rx.get_buff_dtor();
}

void PosixUart::data_rcvd()
{
    // Copy data from transmit buffer to the UART object.
    while (m_ok && chunk_tx()) {}   // Copy data until none is left.
    m_tx.read_finalize();           // End of packet, move to the next.
}

void PosixUart::poll_always()
{
    // Copy data from UART object to the receive buffer.
    while (m_ok && chunk_rx()) {}   // Copy data until none is left.
}

unsigned PosixUart::chunk_rx()
{
    // Copy a single block of received data.
    u8 buff[64];
    unsigned cpy_bytes = 0;
#if SATCAT5_WIN32
    DWORD status = 0;
    m_ok = ReadFile(m_uart, buff, sizeof(buff), &status, NULL);
    if (!m_ok) {
        s32 errnum = GetLastError();
        log::Log(log::ERROR, "UART Rx error").write10(errnum);
    } else if (status > 0) {
        cpy_bytes = (unsigned)status;
    }
#else
    int status = 0;
    m_ok = (ioctl(m_uart, FIONREAD, &status) >= 0);
    if (status > 0) {
        cpy_bytes = min_unsigned(status, sizeof(buff));
        status = read(m_uart, buff, cpy_bytes);
        cpy_bytes = (unsigned)status;
    }
#endif
    // Copy that data to the receive buffer.
    if (cpy_bytes) {
        m_rx.write_bytes(cpy_bytes, buff);
        m_rx.write_finalize();
    }
    return cpy_bytes;
}

unsigned PosixUart::chunk_tx()
{
    // Copy a single chunk of transmit data.
    unsigned cpy_bytes = 0;
    unsigned max_bytes = m_tx.get_peek_ready();
    const u8* buff = m_tx.peek(max_bytes);
#if SATCAT5_WIN32
    DWORD status = 0;
    m_ok = WriteFile(m_uart, buff, max_bytes, &status, NULL);
    if (!m_ok) {
        s32 errnum = GetLastError();
        log::Log(log::ERROR, "UART Tx error").write10(errnum);
    } else if (status > 0) {
        cpy_bytes = (unsigned)status;
    }
#else
    int status = write(m_uart, buff, max_bytes);
    if (status > 0) cpy_bytes = (unsigned)status;
#endif
    // Consume copied data, but do not finalize.
    // (There may still be additional data in the same packet.)
    if (cpy_bytes) {
        m_tx.read_consume(cpy_bytes);
    }
    return cpy_bytes;
}

SlipUart::SlipUart(const char* device, unsigned baud, unsigned buffer)
    : satcat5::io::WriteableRedirect(&m_slip)
    , satcat5::io::ReadableRedirect(&m_slip)
    , m_uart(device, baud, buffer)
    , m_slip(&m_uart, &m_uart)
{
    // Nothing else to initialize.
}
