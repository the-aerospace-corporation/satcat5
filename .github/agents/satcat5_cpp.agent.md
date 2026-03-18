---
# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
#
# AI Disclosure Statement: This documentation file was developed with the
# assistance of generative AI tools: Claude Sonnet 4 by Anthropic,
# December 2025, for the purpose of analyzing existing codebase patterns,
# generating style guidelines, and creating comprehensive usage examples.
# All generated content was reviewed and validated against the actual
# SatCat5 codebase for accuracy and consistency. Use of this generative AI
# tool is in compliance with all applicable Aerospace policies, procedures,
# and directives in effect at the time of use.

name: SatCat5_CPP_Agent
description: Comprehensive coding style guide and conventions for the SatCat5 C++ embedded networking codebase, including patterns for classes, inheritance, documentation, memory management, and usage examples.
model: Claude Sonnet 4
tools: ['runCommands', 'runTasks', 'edit', 'search', 'todos', 'runSubagent', 'usages', 'vscodeAPI', 'problems', 'changes', 'testFailure', 'fetch', 'githubRepo']
---

# SatCat5 C++ Coding Style Agent

This document captures the coding style and conventions used throughout the SatCat5 C++ codebase for consistent code generation and maintenance.

## Target Environment

- **C++ Standard**: C++14 (for embedded bare-metal compatibility)
- **STL Usage**: **BANNED** - No Standard Template Library usage allowed
- **Target**: Embedded bare-metal systems with resource constraints
- **Memory Management**: **Dynamic allocation PROHIBITED** - Use static allocation with templates (e.g., ArrayWriteStatic)

## Code Quality Requirements

**For Pull Request approval, the following are REQUIRED:**
- **100% code coverage** - All new code must be fully covered by tests
- **cpplint compliance** - Code must pass cpplint style checking
- **cppcheck compliance** - Code must pass static analysis without warnings

These requirements ensure code quality and maintainability across the SatCat5 codebase.

## File Header and Copyright

All source files MUST begin with a copyright header that reflects the creation date and last modification date:
```cpp
//////////////////////////////////////////////////////////////////////////
// Copyright YYYY-YYYY The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
```

**Examples:**
- New file created in 2025: `// Copyright 2025 The Aerospace Corporation.`
- File created in 2021, last modified 2025: `// Copyright 2021-2025 The Aerospace Corporation.`
- File created and modified same year: `// Copyright 2024 The Aerospace Corporation.`

### AI Disclosure Requirements

**For Aerospace Corporation contributors**: AI disclosure is required for significant AI assistance beyond "light" usage (brainstorming, code completion <10%, syntax fixes, bugs, minor edits).

When AI disclosure is required, add the following **immediately after the copyright notice**:

```cpp
//////////////////////////////////////////////////////////////////////////
// Copyright YYYY-YYYY The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// AI Disclosure Statement: This [Content Type] was [developed/created/
// composed/designed] with the assistance of generative AI tools:
// [Model Information: Tool Name, Model Provider - Model Name, Date of Use],
// for the purpose of [Scope of Use]. [Review Process]. Use of this
// generative AI tool is in compliance with all applicable Aerospace
// policies, procedures, and directives in effect at the time of use.
//////////////////////////////////////////////////////////////////////////
```

**Example:**
```cpp
// AI Disclosure Statement: This source file was developed with the
// assistance of generative AI tools: GitHub Copilot, OpenAI GPT-4,
// December 2025, for the purpose of code generation and optimization.
// All generated code was reviewed and validated by qualified engineers.
// Use of this generative AI tool is in compliance with all applicable
// Aerospace policies, procedures, and directives in effect at the time of use.
```

## Documentation Style

### File Documentation
Use Doxygen-style comments for file headers:
```cpp
//! \file
//! Brief description of the file purpose
//!
//! \details
//! Detailed description explaining the file's purpose, usage patterns,
//! and important concepts. Use multiple paragraphs for complex topics.
//!
//! Additional sections may include examples, warnings, or references
//! to related files and concepts.
```

### Class Documentation
```cpp
//! Brief description of the class purpose.
//!
//! Detailed description of the class functionality, usage patterns,
//! and relationships to other classes. Include examples when helpful.
//!
//! \copydoc filename.h (for cross-referencing shared documentation)
class MyClass {
    // Implementation...
};
```

### Method Documentation
```cpp
//! Brief description of what the method does.
//! More detailed explanation if needed, including parameter relationships,
//! side effects, and usage patterns.
//! \param param1 Description of first parameter
//! \param param2 Description of second parameter
//! \return Description of return value
virtual void my_method(unsigned param1, const Type& param2) = 0;

//! \copydetails other_class::method_name() (for inherited documentation)
u32 inherited_method() override;
```

### Doxygen Grouping
Use Doxygen groups for related functions or variables:
```cpp
//! Read unsigned integers in big-endian format.
//! Each function reads the number of bytes indicated by the suffix.
//!@{
u8 read_u8();       // Read 1 byte
u16 read_u16();     // Read 2 bytes
u32 read_u32();     // Read 4 bytes
u64 read_u64();     // Read 8 bytes
//!@}

//! Write unsigned integers in big-endian format.
//!@{
void write_u8(u8 val);
void write_u16(u16 val);
void write_u32(u32 val);
//!@}
```
Use grouping when multiple functions/variables share common documentation to avoid repetition.

### Struct Documentation
Structs with public members should document each field:
```cpp
//! State information for a single deferred packet.
struct DeferPkt {
public:
    satcat5::io::MultiPacket* pkt;  //!< Packet object
    satcat5::ip::Addr dst_ip;       //!< Destination IP address
    SATCAT5_PMASK_TYPE dst_mask;    //!< Destination port-mask
    u16 sent;                       //!< Number of attempts so far
    u16 trem;                       //!< Remaining time in msec
};
```

## Code Formatting Standards

### Line Length and Indentation
- **Maximum line length**: 80 characters (STRICT)
- **Indentation**: 4 spaces everywhere (no tabs)
- **All files must end with a newline**

### Const Correctness
```cpp
// const pointer (can't reassign pointer) - used when object set in constructor
satcat5::cfg::ConfigBus* const m_cfg;

// pointer to const (can't modify data through pointer) - used for immutable data
const u32* read_only_data;

// const reference parameter (can't modify object) - preferred for complex types
void process_addr(const satcat5::eth::MacAddr& addr);
```

### Constructor Specifiers
Always prefer `constexpr explicit` order:
```cpp
// Preferred order
constexpr explicit MyClass(int value) : m_value(value) {}

// Avoid
explicit constexpr MyClass(int value) : m_value(value) {}
```

### Inline Function Style
Use single-line when it fits within 80 characters, multi-line otherwise:
```cpp
// Single-line (preferred when it fits)
inline u16 vid() const { return (value >> 0) & 0xFFF; }

// Multi-line (when single line exceeds 80 characters)
inline satcat5::eth::MacAddr reply_mac() const
    { return m_reply_srcaddr; }
```

### Member Variable Documentation
All member variables SHOULD have Doxygen inline comments:
```cpp
protected:
    satcat5::cfg::ConfigBus* const m_cfg;       //!< Parent ConfigBus interface
    const unsigned m_reg;                       //!< Device + register index
    satcat5::eth::MacAddr m_addr;               //!< Local MAC address
    satcat5::eth::MacAddr m_reply_dstaddr;      //!< Reply destination MAC

    // Column-align comments when possible (on 4-space tab boundaries)
    satcat5::io::Writeable* const m_dst;        //!< Output destination
    satcat5::io::Readable* m_src;               //!< Input source
```

**Note**: Current codebase has some files with missing member documentation.
This is often developer oversight - all new code should include inline
documentation

### Typedef vs Using Declarations
```cpp
// Use typedef for type aliases (especially when the type could be struct/class)
typedef volatile u32* Register;
typedef SATCAT5_PMASK_TYPE PortMask;

// Use 'using' for template specializations and bringing names into scope
using satcat5::cbor::MapWriter<const char*>::add_bool;
using satcat5::log::Log;
```

### Final Classes
- Use `final` for leaf classes that should not be inherited from
- **Do NOT default to final** - ask user preference
- Classes should generally be designed for inheritance flexibility
```cpp
// Use final for true leaf classes
class ConnectionUdp final : public satcat5::coap::Connection {
    // Implementation that should not be inherited from
};

// Avoid final for extensible classes
class MyProtocol : public satcat5::eth::Protocol {
    // Designed to allow inheritance
};
```

## Namespace Structure

All SatCat5 code MUST be within the `satcat5` namespace with logical sub-namespaces:

```cpp
namespace satcat5 {
    namespace cfg {      // Configuration bus related
        // Classes and functions
        class ExampleClass {
            // Implementation
        };
    } // namespace cfg

    namespace eth {      // Ethernet related
        // Classes and functions
    } // namespace eth

    namespace io {       // I/O interfaces
        // Classes and functions
    } // namespace io

    namespace ptp {      // Precision Time Protocol
        // Classes and functions
    } // namespace ptp

    namespace util {     // Utilities
        // Classes and functions
    } // namespace util
} // namespace satcat5
```

**Note**: Current codebase often omits namespace closing comments. While the Agent recommends
`// namespace name` comments for clarity, omitting them (as in existing files) is acceptable for consistency.

## Class Structure and Inheritance

### Class Declaration Order
1. Public interface first
2. Protected members (for inheritance)
3. Private implementation details

### Inheritance Syntax
- Use `: public BaseClass` format (space before colon)
- Multiple inheritance on separate lines with proper alignment
- Prefer `final` for classes not intended for further inheritance

```cpp
class Client
    : public satcat5::poll::Timer
    , public satcat5::ptp::Source
{
public:
    // Public interface

protected:
    // Protected members for inheritance

private:
    // Private implementation
};

class ConnectionSpp final : public satcat5::coap::Connection {
    // Final class - no further inheritance
};
```

### Constructor Style
```cpp
//! Constructor with explicit parameter documentation.
MyClass(
    satcat5::cfg::ConfigBus* cfg_bus,
    unsigned device_index,
    const ConfigStruct& config = DEFAULT_CONFIG);
```

### Destructor Style
Use the SatCat5 destructor macro ONLY for objects that will never be destroyed (saves code size):
```cpp
~MyClass() SATCAT5_OPTIONAL_DTOR;
```

The `SATCAT5_OPTIONAL_DTOR` macro is used to remove heavy destructor code in embedded systems where objects are never destroyed. Use this macro only for:
- Global/static objects with application lifetime
- Objects allocated once and never freed
- Objects where destruction would indicate a system error

Do NOT use for:
- Stack-allocated objects that will go out of scope
- Objects that need proper cleanup
- Objects in systems where dynamic allocation/deallocation occurs

## Method Declarations

### Virtual Methods
```cpp
//! Pure virtual methods use = 0
virtual IoStatus read(unsigned regaddr, u32& rdval) = 0;

//! Virtual methods with default implementation
virtual IoStatus read_array(
    unsigned regaddr, unsigned count, u32* result);

//! Override specifier for inherited methods
void data_rcvd(satcat5::io::Readable* src) override;
```

### Inline Methods
Prefer inline getters in header files:
```cpp
//! Inline getter with clear return type documentation.
inline satcat5::eth::MacAddr macaddr() const
    { return m_addr; }

//! Inline setter with parameter validation.
inline void set_default_vid(const satcat5::eth::VlanTag& vtag)
    { m_default_vid.value = vtag.vid(); }
```

### Method Parameters
- Use const references for complex types: `const MacAddr& addr`
- Use value types for primitives: `unsigned count`, `u32 value`
- Use pointers for optional parameters or when null is meaningful
- Use default parameters when appropriate: `VlanTag vtag = VTAG_NONE`

### Control Flow Style
Always use braces for single-line statements where possible:
```cpp
// Preferred: Always use braces
if (m_dst) { m_dst->write_finalize(); }

// Also acceptable for simple cases
if (condition)
    { single_statement(); }

// Avoid braceless single lines (harder to maintain)
if (condition) single_statement();
```

### Function Closing Braces
Functions should be closed on the same line as the last statement:
```cpp
// Correct: Closing brace on same line
void function() {
    // Function body
    statement1();
    statement2();
}

// Correct: Single-line functions
inline u16 get_value() const { return m_value; }

// Correct: Constructor with initializer list (opening brace on new line)
MyClass::MyClass(int value)
    : m_value(value)
{
    // Constructor body
}
```

## Type Definitions and Constants

### Type Aliases
```cpp
//! Type alias for port mask (affects maximum ports)
typedef SATCAT5_PMASK_TYPE PortMask;

//! Conditional compilation for interface selection
#if SATCAT5_CFGBUS_DIRECT
    typedef volatile u32* Register;
    #define SATCAT5_NULL_REGISTER   0
#else
    typedef satcat5::cfg::WrappedRegisterPtr Register;
    #define SATCAT5_NULL_REGISTER   WrappedRegisterPtr(0,0)
#endif
```

### Constants and Enums
```cpp
//! Use constexpr for compile-time constants
constexpr unsigned REGS_PER_DEVICE = 1024;
constexpr SATCAT5_PMASK_TYPE PMASK_ALL(-1);

//! Use const for runtime constants
const unsigned DEVS_PER_CFGBUS = 256;

//! Scoped enums with clear type specification
enum class IoStatus {
    OK = 0,         // Always document enum values
    BUSERROR,       // Bus error condition
    CMDERROR,       // Invalid command
    TIMEOUT,        // Network timeout
};

//! Legacy compatibility constants (when needed)
constexpr auto IOSTATUS_OK = satcat5::cfg::IoStatus::OK;
```

### Template Functions
```cpp
//! Simple constexpr functions with clear type constraints
constexpr SATCAT5_PMASK_TYPE idx2mask(unsigned idx)
    { return (idx < 65536) ? (SATCAT5_PMASK_TYPE(1) << idx) : 0; }

constexpr unsigned PMASK_SIZE()
    { return 8 * sizeof(SATCAT5_PMASK_TYPE); }

//! Template functions for utility operations
template <typename T> inline constexpr T mask_lower(unsigned n) {
    return ((n >= 8*sizeof(T)) ? 0 : (T(1) << n)) - 1;
}

template <typename T> inline constexpr T div_round(T a, T b)
    { return divide<T>(a + b/2, b); }

template <typename T> inline constexpr T clamp(T x, T y) {
    return (x < y) ? x : y;
}
```

### Template Classes
```cpp
//! Template classes for static allocation (preferred over dynamic)
template <unsigned SIZE>
class ArrayWriteStatic : public satcat5::io::ArrayWrite {
public:
    constexpr ArrayWriteStatic()
        : ArrayWrite(m_buff, SIZE), m_buff{} {}
private:
    u8 m_buff[SIZE];
};

//! Template cache implementation
template <class T> class LruCache {
public:
    LruCache(T* array, unsigned count) : m_free(array), m_list(0) {
        // Initialize linked list of free elements
        for (unsigned a = 0 ; a < count-1 ; ++a) {
            array[a].m_next = array + a + 1;
        }
        // ... remainder of implementation
    }
    // ... methods
};
```

### Template Usage Guidelines
- **Prefer constexpr templates** for compile-time evaluation
- **Use template classes for static allocation** instead of dynamic memory
- **Document template parameters** clearly in Doxygen comments
- **Keep templates simple** - complex SFINAE discouraged for embedded compatibility

## Variable Naming Conventions

### Member Variables
- Member variables use `m_` prefix
- Const members use `const` qualifier appropriately
- Use descriptive names that indicate purpose

### Common Variable Names
Standard abbreviations used throughout the codebase:
```cpp
// ConfigBus interfaces
satcat5::cfg::ConfigBus* cfg        // Not m_cfg in parameters
satcat5::cfg::Register reg          // Register references

// Network interfaces
satcat5::eth::Dispatch* eth         // Ethernet dispatch
satcat5::ip::Dispatch* ip           // IP dispatch
satcat5::udp::Dispatch* udp         // UDP dispatch

// I/O interfaces
satcat5::io::Readable* src          // Data source
satcat5::io::Writeable* dst         // Data destination

// Address types
satcat5::eth::MacAddr addr          // MAC addresses
satcat5::ip::Addr addr              // IP addresses
```

### Member Variable Examples
```cpp
protected:
    // Configuration and interface objects
    satcat5::cfg::ConfigBus* const m_cfg;       // Parent interface
    const unsigned m_reg;                       // Device + register index

    // State tracking variables
    satcat5::eth::MacAddr m_addr;               // Local MAC address
    satcat5::eth::MacAddr m_reply_dstaddr;      // Reply destination MAC
    satcat5::eth::MacType m_reply_type;         // Reply EtherType

    // I/O interface objects
    satcat5::io::Writeable* const m_dst;        // Output destination
    satcat5::io::Readable* m_src;               // Input source

private:
    // Linked list support (when applicable)
    friend satcat5::util::ListCore;
    MyClass* m_next;                            // Next item in list
```

## Preprocessor and Compilation

### Conditional Compilation
```cpp
// Feature flags belong in HEADER files (.h) for user visibility
#ifndef SATCAT5_CFGBUS_DIRECT
#define SATCAT5_CFGBUS_DIRECT   0
#endif

#ifndef SATCAT5_ALLOW_DELETION
#define SATCAT5_ALLOW_DELETION 1
#endif
```

```cpp
// Conditional compilation typically belongs in IMPLEMENTATION files (.cc)
#if SATCAT5_ALLOW_DELETION
void MyClass::cleanup() {
    // Full cleanup implementation
}
#else
void MyClass::cleanup() {
    // Minimal or no-op implementation
}
#endif
```

**Rule**: Feature flags (`#ifndef`/`#define`/`#endif`) go in headers for user configuration.
Conditional implementations (`#if`/`#else`/`#endif`) go in source files, with rare exceptions.

## Include Ordering

**Header files (.h) must include:**
```cpp
#pragma once                    // Always use pragma once

// 1. Own header first (for .cc files only)
#include <satcat5/my_module.h>

// 2. SatCat5 headers in logical/alphabetical order
#include <satcat5/cfgbus_core.h>
#include <satcat5/interrupts.h>
#include <satcat5/list.h>
#include <satcat5/log.h>
#include <satcat5/types.h>

// 3. Minimal C standard library headers last (avoid STL)
#include <cinttypes>
#include <climits>
```

**Implementation files (.cc) pattern:**
```cpp
// 1. Own header first
#include <satcat5/my_module.h>

// 2. Related SatCat5 headers
#include <satcat5/log.h>
#include <satcat5/utils.h>

// 3. Using declarations and namespace aliases
using satcat5::cfg::ConfigBus;
using satcat5::log::Log;
namespace log = satcat5::log;
```

## Implementation File Style

### Using Declarations
Prefer using declarations at file scope for frequently used types:
```cpp
using satcat5::cfg::ConfigBus;
using satcat5::cfg::IoStatus;
using satcat5::ptp::Client;
using satcat5::ptp::ClientMode;
namespace log = satcat5::log;

// Local shortcuts for complex templates
#define div_round satcat5::util::div_round<unsigned>
```

### Method Implementation
```cpp
MyClass::MyClass(ConfigBus* cfg, unsigned reg)
    : m_cfg(cfg)
    , m_reg(reg)
{
    // Implementation with clear initialization list
}

IoStatus MyClass::read(unsigned regaddr, u32& rdval)
{
    // Method implementation with clear logic flow
    if (!validate_address(regaddr)) {
        return IoStatus::CMDERROR;
    }

    // Perform operation...
    return IoStatus::OK;
}
```

## Comment Style

### Single-line Comments
```cpp
// Brief explanatory comments for complex logic
// Use consistent formatting and spacing
```

### Multi-line Comments
```cpp
//! Doxygen comments for API documentation
//! Use exclamation mark for API docs
//! Continue with proper alignment

// Standard multi-line comments for implementation notes:
// First line of explanation
// Continuation with consistent indentation and format
```

## Error Handling and Validation

### Return Value Patterns
```cpp
//! Methods return status codes for error handling
virtual IoStatus operation(parameters) = 0;

//! Boolean methods for simple success/failure
bool is_valid() const;

//! Pointer returns (null indicates error/invalid)
satcat5::io::Writeable* open_connection();
```

### Validation Patterns
```cpp
//! Parameter validation at method entry
if (!cfg || reg >= MAX_REGISTERS) {
    return IoStatus::CMDERROR;
}

//! State validation before operations
if (m_state != State::READY) {
    log::Log(log::ERROR, "Invalid state for operation");
    return IoStatus::CMDERROR;
}
```

## Common Class Usage Patterns

### Logging (satcat5::log::Log)
```cpp
#include <satcat5/log.h>

// Using declaration for convenience
using satcat5::log::Log;

// Logging examples - message sent when Log object falls out of scope
void example_logging(u8 errcode, s8 temperature) {
    // Method 1: One-liner with hex output
    Log(satcat5::log::WARNING, "Connection failed").write(errcode);  // "Connection failed = 0x42"

    // Method 2: Decimal output
    Log(satcat5::log::ERROR, "Invalid temp").write10(temperature).write(" C");   // "Invalid temp = -15 C"

    // Method 3: Unsigned decimal with positive sign
    Log(satcat5::log::INFO, "Temperature").write10(25);          // "Temperature = +25"

    // Method 4: Chained writes
    Log(satcat5::log::DEBUG).write("State: ").write10(state).write(" -> ").write10(new_state);

    // Method 5: Multiple statements
    Log log(satcat5::log::INFO, "Processing packet from ");
    log.write(remote_addr);  // Uses MAC/IP-specific formatting
}

// Different write methods for numeric formatting:
void format_examples(u8 value) {
    Log(satcat5::log::DEBUG, "Hex format").write(value);      // " = 0x2A"
    Log(satcat5::log::DEBUG, "Dec format").write10(value);    // " = 42"
    Log(satcat5::log::DEBUG, "Signed dec").write10(s8(-10)); // " = -10"
}

// Objects with log_to() method can be logged directly
void log_objects() {
    satcat5::eth::MacAddr mac_addr = {...};
    satcat5::ip::Addr ip_addr = {...};

    // These use special log_to() formatting
    Log(satcat5::log::INFO, "MAC").write_obj(mac_addr);    // "MAC = 01:23:45:67:89:AB"
    Log(satcat5::log::INFO, "IP").write_obj(ip_addr);      // "IP = 192.168.1.42"
}

// Custom log formatting with LogBuffer
class CustomLoggable {
public:
    CustomLoggable(u16 id, const char* name) : m_id(id), m_name(name) {}

    //! Custom log_to() method for write_obj() support
    void log_to(satcat5::log::LogBuffer& wr) const {
        wr.wr_str(m_name);
        wr.wr_str(" (ID=");
        wr.wr_d32(m_id);      // Decimal format
        wr.wr_str(")");
    }

private:
    u16 m_id;
    const char* m_name;
};

void log_custom_objects() {
    CustomLoggable device(42, "Sensor");
    
    // Uses custom log_to() formatting
    Log(satcat5::log::INFO, "Device").write_obj(device);   // "Device = Sensor (ID=42)"
}

// LogBuffer methods for custom formatting:
void logbuffer_methods(satcat5::log::LogBuffer& wr, u32 value) {
    wr.wr_str("Fixed string");           // Write string literal
    wr.wr_h32(value, 8);                 // Hex format with 8 digits: "0x12345678"
    wr.wr_h32(value, 4);                 // Hex format with 4 digits: "0x5678"
    wr.wr_d32(value);                    // Decimal format: "305419896"
    wr.wr_d32(value, 9999);              // Zero-padded: "0042" (if value=42)
    wr.wr_s32(-123);                     // Signed decimal: "-123"
}

// Log levels (in order of severity)
satcat5::log::DEBUG     // Verbose debugging information
satcat5::log::INFO      // General information
satcat5::log::WARNING   // Warning conditions
satcat5::log::ERROR     // Error conditions
satcat5::log::CRITICAL  // Critical system errors

// Setting up log output to UART
satcat5::log::ToWriteable log_uart(&my_uart);

// Concise syntax (if SATCAT5_LOG_CONCISE enabled)
#if SATCAT5_LOG_CONCISE
void concise_example() {
    Log(LOG_ERROR, "Concise syntax").write10(error_code);
}
#endif
```

### Address Structures (MAC/IP/UDP)

```cpp
#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>
#include <satcat5/udp_core.h>

// MAC Address usage
satcat5::eth::MacAddr mac_broadcast = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
satcat5::eth::MacAddr mac_local = {0x02, 0x03, 0x04, 0x05, 0x06, 0x07};

// Check if multicast
if (mac_addr.is_multicast()) {
    // Handle multicast case
}

// IP Address usage
satcat5::ip::Addr ip_local = {192, 168, 1, 42};
satcat5::ip::Addr ip_gateway = satcat5::ip::ADDR_NONE;  // 0.0.0.0

// IP address comparison and utility
if (ip_addr == satcat5::ip::ADDR_BROADCAST) {
    // Handle broadcast
}

// UDP Port usage
constexpr u16 PORT_HTTP = 80;
constexpr u16 PORT_DHCP_SERVER = 67;
```

### Dispatch/Address Patterns for Network Communication
```cpp
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/udp_dispatch.h>

// Ethernet dispatch setup
satcat5::eth::Dispatch eth_dispatch(&my_eth_port);
eth_dispatch.set_macaddr(mac_local);

// Protocol registration for receiving frames
class MyProtocolHandler : public satcat5::net::Protocol {
public:
    MyProtocolHandler(satcat5::eth::Dispatch* eth)
        : m_eth(eth)
    {
        m_eth->add(this, my_ethertype);
    }

    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        // Handle received frame
    }

private:
    satcat5::eth::Dispatch* const m_eth;
};

// Sending frames
satcat5::eth::Address eth_addr(&eth_dispatch);
eth_addr.connect(dest_mac, my_ethertype);
if (auto wr = eth_addr.open_write(frame_length)) {
    wr->write_u32(my_data);
    wr->write_finalize();
}

// IP stack layering
satcat5::ip::Dispatch ip_dispatch(&eth_dispatch, ip_local, ip_gateway);
satcat5::udp::Dispatch udp_dispatch(&ip_dispatch);
```

### Readable and Writeable Interfaces
```cpp
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>

// Using Readable interface for data processing
void process_data(satcat5::io::Readable* src) {
    while (src->get_read_ready() > 0) {
        u32 value = src->read_u32();  // Read big-endian u32
        u16 count = src->read_u16();  // Read big-endian u16
        // Process data...
    }
    src->read_finalize();  // Mark packet as consumed
}

// Writeable interface usage
void send_data(satcat5::io::Writeable* dst, u32 value) {
    if (dst && dst->get_write_space() >= 4) {
        dst->write_u32(value);        // Write big-endian u32
        dst->write_finalize();        // Complete packet
    }
}

// Common Readable child classes:

// 1. LimitedRead - Restricts reading to a specific byte count
void handle_frame(satcat5::io::LimitedRead& src) {
    // Can only read up to the frame boundary
    while (src.get_read_ready() > 0) {
        u8 byte = src.read_u8();
        // Process byte...
    }
    // read_finalize() not needed - handled by LimitedRead
}

// 2. ArrayRead - Read from a static buffer
void read_from_array() {
    u8 buffer[64] = {...};
    satcat5::io::ArrayRead reader(buffer, sizeof(buffer));

    u32 header = reader.read_u32();
    u16 length = reader.read_u16();
    reader.read_finalize();
}

// Common Writeable child classes:

// 1. ArrayWrite - Write to a provided buffer
void write_to_array() {
    u8 buffer[64];
    satcat5::io::ArrayWrite writer(buffer, sizeof(buffer));

    writer.write_u32(0x12345678);
    writer.write_u16(100);
    writer.write_finalize();

    // Use buffer contents...
}

// 2. ArrayWriteStatic - Template for static allocation (PREFERRED)
void use_static_buffer() {
    // Template automatically provides 64-byte buffer
    satcat5::io::ArrayWriteStatic<64> writer;

    writer.write_u32(header_value);
    writer.write_bytes(data, data_len);
    writer.write_finalize();

    // Access internal buffer via get_buff_dtor() if needed
}

// 3. LimitedWrite - Restrict write count, doesn't forward finalize
void limited_writing(satcat5::io::Writeable* dst) {
    // Only allow writing 32 bytes to the destination
    satcat5::io::LimitedWrite limited(dst, 32);

    limited.write_u32(header);
    // ... can only write 28 more bytes
    // write_finalize() on limited does nothing

    // Must call finalize on original destination
    dst->write_finalize();
}
```

### Polling System (poll::Timer and poll::OnDemand)
```cpp
#include <satcat5/polling.h>

// Timer-based polling for delayed and periodic tasks
class MyTimerTask : public satcat5::poll::Timer {
public:
    MyTimerTask() {
        // Can schedule in constructor or later
        timer_once(1000);  // Execute timer_event() once after 1000ms
    }

    void start_periodic_check() {
        // Start periodic execution (every 5 seconds)
        timer_every(5000);  // Execute timer_event() every 5000ms
    }

    void schedule_timeout() {
        // Schedule one-time execution (e.g., timeout for reply)
        timer_once(1000);   // Check for reply after 1000ms
    }

protected:
    void timer_event() override {
        // This method is called by timer_once() or timer_every()
        if (waiting_for_reply()) {
            handle_timeout();
        } else {
            perform_periodic_task();
            // timer_every() will automatically reschedule next execution
        }
    }

private:
    bool waiting_for_reply() { return m_waiting; }
    void handle_timeout() { /* timeout handling */ }
    void perform_periodic_task() { /* periodic work */ }
    bool m_waiting = false;
};

// On-demand polling for event-driven tasks
class MyEventHandler : public satcat5::poll::OnDemand {
public:
    void trigger_work() {
        // Request polling at next service cycle
        request_poll();
    }

protected:
    void poll_demand() override {
        // Handle the event
        process_event();
    }

private:
    void process_event() {
        // Implementation...
    }
};

// Main service loop (must be called regularly)
int main() {
    MyTimerTask timer_task;
    MyEventHandler event_handler;

    while (true) {
        // Process all queued events
        satcat5::poll::service_all();

        // Brief delay or handle other system tasks
        system_delay();
    }
}
```

### Event-Driven Data Processing
```cpp
#include <satcat5/io_readable.h>

// EventListener pattern for data callbacks
class MyDataProcessor : public satcat5::io::EventListener {
public:
    MyDataProcessor(satcat5::io::Readable* src) : m_src(src) {
        src->set_callback(this);
    }

    ~MyDataProcessor() {
        if (m_src) { m_src->set_callback(nullptr); }
    }

    void data_rcvd(satcat5::io::Readable* src) override {
        // Process incoming data
        while (src->get_read_ready() > 0) {
            u8 byte = src->read_u8();
            // Handle byte...
        }
        src->read_finalize();
    }

private:
    satcat5::io::Readable* m_src;
};
```

## Lessons Learned from Implementation Experience

### Protocol Implementation Patterns
Based on actual DNS receiver implementation, key lessons for network protocol handlers:

#### Network Protocol Listeners (All Layers)
```cpp
// CORRECT: Inherit from satcat5::net::Protocol for all network protocols
// Pattern works for Ethernet (Layer 2), IP (Layer 3), and UDP (Layer 4)

// Layer 2 (Ethernet) Protocol Handler
class EthernetHandler : public satcat5::net::Protocol {
public:
    EthernetHandler(satcat5::eth::Dispatch* eth, satcat5::eth::MacType etype)
        : Protocol(satcat5::net::Type(etype.value))  // Pass type to base
        , m_eth(eth)
    {
        // Register with dispatcher (no additional parameters)
        m_eth->add(this);
    }

    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        // Process Ethernet frame payload
    }

protected:
    satcat5::eth::Dispatch* const m_eth;    //!< Ethernet dispatcher
};

// Layer 3 (IP) Protocol Handler
class IpProtocolHandler : public satcat5::net::Protocol {
public:
    IpProtocolHandler(satcat5::ip::Dispatch* ip, u8 protocol)
        : Protocol(satcat5::net::Type(protocol))     // Pass type to base
        , m_ip(ip)
    {
        // Register with dispatcher (no additional parameters)
        m_ip->add(this);
    }

    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        // Process IP packet payload
    }

protected:
    satcat5::ip::Dispatch* const m_ip;      //!< IP dispatcher
};

// Layer 4 (UDP) Protocol Handler
class UdpMessageReceiver : public satcat5::net::Protocol {
public:
    UdpMessageReceiver(satcat5::udp::Dispatch* udp, satcat5::udp::Port port)
        : Protocol(satcat5::net::Type(port.value))   // Pass type to base
        , m_udp(udp)
    {
        // Register with dispatcher (no additional parameters)
        m_udp->add(this);
    }

    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        // Process UDP message payload
    }

protected:
    satcat5::udp::Dispatch* const m_udp;    //!< UDP dispatcher
};

// AVOID: Don't use Address classes for listening (those are for sending)
// AVOID: Don't inherit from io::EventListener for network protocols
// AVOID: Different inheritance patterns across network layers
// AVOID: Passing extra parameters to add() - it only takes the Protocol*
```

#### Layer-Specific Constant Management
```cpp
// CORRECT: Centralize well-known identifiers in respective core headers

// Layer 2 (Ethernet) - EtherTypes in eth_header.h
namespace satcat5 {
    namespace eth {
        constexpr MacType ETYPE_ARP     = {0x0806};
        constexpr MacType ETYPE_IPV4    = {0x0800};    // Added alphabetically
        constexpr MacType ETYPE_IPV6    = {0x86DD};
    }
}

// Layer 3 (IP) - Protocol numbers in ip_core.h
namespace satcat5 {
    namespace ip {
        constexpr u8 PROTO_ICMP = 1;
        constexpr u8 PROTO_TCP  = 6;    // Added numerically
        constexpr u8 PROTO_UDP  = 17;
    }
}

// Layer 4 (UDP) - Port numbers in udp_core.h
namespace satcat5 {
    namespace udp {
        constexpr Port PORT_DHCP_CLIENT = {68};
        constexpr Port PORT_DNS         = {53};    // Added alphabetically
        constexpr Port PORT_HTTP        = {80};
    }
}

// CORRECT: Protocol-specific constants in protocol headers
struct MyProtocolHeader {
    static constexpr u16 STANDARD_QUERY = 0x0000;
    static constexpr u8  COMPRESSION_MASK = 0xC0;    // Move magic numbers to constants
    // Implementation...
};

// AVOID: Hardcoded magic numbers in implementation files
// AVOID: Duplicating protocol identifiers across multiple files
// AVOID: Mixing layer identifiers in wrong namespace/header files
```

### Type Conversion and Data Handling
```cpp

// CORRECT: Handle network byte order with read methods (all layers)
u16 ether_type = src.read_u16();      // Automatic big-endian conversion
u16 ip_length = src.read_u16();       // Works consistently across layers
u16 udp_port = src.read_u16();        // Same pattern for all protocols

// CORRECT: Address handling varies by layer but follows consistent patterns
satcat5::eth::MacAddr mac_addr;       // 6-byte MAC address
satcat5::ip::Addr ip_addr;            // 4-byte IP address
// UDP uses IP addresses + ports, no separate address type

// AVOID: Manual byte-order conversion when read_u16() handles it
// AVOID: Direct assignment to Type objects without .value member
// AVOID: Inconsistent address handling patterns across layers
```

### Error Handling and Validation
```cpp
// CORRECT: Early validation with clear error returns
void process_packet(satcat5::io::LimitedRead& src) {
    if (src.get_read_ready() < MIN_HEADER_SIZE) {
        Log(satcat5::log::WARNING, "DNS packet too short");
        return;
    }

    // Continue processing...
}

// CORRECT: Defensive programming for network data
if (question_count > MAX_REASONABLE_QUESTIONS) {
    Log(satcat5::log::WARNING, "Excessive question count").write10(question_count);
    return;  // Avoid processing malformed packets
}
```

### Constructor and Destructor Patterns
```cpp
// CORRECT: Constructor with proper member initialization (all network layers)

// Layer 2 (Ethernet) Constructor
EthernetHandler(satcat5::eth::Dispatch* eth, satcat5::eth::MacType etype)
    : Protocol(satcat5::net::Type(etype.value))  // Initialize base with type
    , m_eth(eth)    // Initialize const pointer members
{
    if (m_eth) {
        m_eth->add(this);    // Register after validation (no extra params)
    }
}

// Layer 3 (IP) Constructor
IpProtocolHandler(satcat5::ip::Dispatch* ip, u8 protocol)
    : Protocol(satcat5::net::Type(protocol))     // Initialize base with type
    , m_ip(ip)      // Initialize const pointer members
{
    if (m_ip) {
        m_ip->add(this);     // Register after validation (no extra params)
    }
}

// Layer 4 (UDP) Constructor
UdpMessageReceiver(satcat5::udp::Dispatch* udp, satcat5::udp::Port port)
    : Protocol(satcat5::net::Type(port.value))   // Initialize base with type
    , m_udp(udp)    // Initialize const pointer members
{
    if (m_udp) {
        m_udp->add(this);    // Register after validation (no extra params)
    }
}

// CORRECT: Defensive destructor pattern (consistent across all layers)
~NetworkProtocolHandler() SATCAT5_OPTIONAL_DTOR
#if SATCAT5_ALLOW_DELETION
{
    if (m_dispatcher) {
        m_dispatcher->remove(this);    // Clean unregister
    }
}
#endif

// KEY LESSONS:
// 1. Always validate dispatcher pointers before registration/unregistration
// 2. Use const pointer members for dispatchers (set once in constructor)
// 3. Registration syntax is consistent: dispatcher->add(this, identifier)
// 4. All layers follow the same constructor/destructor safety patterns
```

### Documentation and Code Organization
```cpp
//! DNS message receiver for logging and analysis.
//!
//! This class demonstrates proper SatCat5 patterns for UDP protocol
//! handlers, including registration with UDP dispatcher, packet parsing
//! with proper byte-order handling, and comprehensive logging.
//!
//! Example usage:
//! \code
//!   satcat5::udp::Dispatch udp_dispatch(&ip_dispatch);
//!   dns::MessageReceiver dns_receiver(&udp_dispatch);
//!   // DNS packets on port 53 will now be logged
//! \endcode
class MessageReceiver : public satcat5::net::Protocol {
    // Implementation follows...
};
```

**Critical Implementation Insights:**
1. **Protocol inheritance**: Use `satcat5::net::Protocol` for all network protocol handlers (Layers 2-4)
2. **Registration timing**: Always validate dispatcher pointers before registration across all layers
3. **Registration syntax**: Use `dispatcher->add(this)` with no additional parameters - type filtering handled by Protocol base constructor
4. **Type initialization**: Pass layer-specific identifier to Protocol base constructor via `satcat5::net::Type()`
5. **Constant organization**: Move magic numbers to appropriate layer-specific core headers for maintainability
6. **Layer identifier centralization**: Add well-known identifiers to respective core headers (`eth_header.h`, `ip_core.h`, `udp_core.h`)
7. **Type handling**: Use `.value` member for SatCat5 wrapper types across all network layers
8. **Logging patterns**: Chain related data in single Log statements for clarity
9. **Network validation**: Always validate packet sizes before parsing network data
10. **Consistent patterns**: All network layers follow identical Protocol inheritance and dispatcher registration patterns

## Summary

This style guide captures the essential patterns used throughout the SatCat5 codebase for consistent C++ development. Key principles:

1. **No STL** - Use SatCat5's own container and utility classes
2. **C++14 compatibility** - Target embedded bare-metal systems
3. **Resource conscious** - Minimal dynamic allocation, prefer stack allocation
4. **Consistent naming** - Follow established variable naming conventions
5. **Comprehensive documentation** - Use Doxygen-style comments extensively
6. **Proper inheritance** - Use virtual destructors and override specifiers correctly
7. **Network protocol patterns** - Follow established UDP listener and logging patterns
8. **Defensive validation** - Always validate network data and pointer parameters

Follow these conventions to maintain code quality and readability across the project.