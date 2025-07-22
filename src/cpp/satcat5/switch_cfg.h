//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Configuration for a managed SatCat5 switch.
//!
//!\details
//! SatCat5 switches can operate autonomously.  However, an optional
//! management interface allows runtime changes to the configuration,
//! such as prioritizing frames with certain EtherType(s) or marking
//! specific ports as "promiscuous" so they can monitor global traffic.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/ethernet.h>

namespace satcat5 {
    namespace eth {
        //! Define VLAN policy modes for a given switch port.
        //!  ADMIT_ALL: Default, suitable for most network endpoints.
        //!      Rx: Accept any frame, tagged or untagged.
        //!      Tx: Never emit tagged frames.
        //!  RESTRICTED: Suitable for locking devices to a single VID.
        //!      Rx: Accept tagged frames with VID = 0, or untagged frames.
        //!      Tx: Never emit tagged frames.
        //!  PRIORITY: Suitable for VLAN-aware devices with a single VID.
        //!      Rx: Accept tagged frames with VID = 0, or untagged frames.
        //!      Tx: Always emit tagged frames with VID = 0.
        //!  MANDATORY: Recommended for crosslinks to another VLAN-aware switch.
        //!      Rx: Accept tagged frames only, with any VID.
        //!      Tx: Always emit tagged frames with VID > 0.
        //!@{
        constexpr u32 VTAG_ADMIT_ALL    = 0x00000000u;
        constexpr u32 VTAG_RESTRICT     = 0x00010000u;
        constexpr u32 VTAG_PRIORITY     = 0x00110000u;
        constexpr u32 VTAG_MANDATORY    = 0x00220000u;
        //!@}

        //! Define VLAN rate-limiter modes for each VID.
        //!  UNLIMITED: Default, rate-limits are ignored.
        //!  DEMOTE: Excess packets are low-priority.
        //!  STRICT: Excess packets are dropped immediately.
        //!  AUTO: Excess packet policy set by DEI flag.
        //!      If the VLAN header sets the "drop eligible indicator" (DEI)
        //!      flag, use the STRICT policy, otherwise use the DEMOTE policy.
        //!@{
        constexpr u32 VPOL_UNLIMITED    = 0x80000000u;
        constexpr u32 VPOL_DEMOTE       = 0x90000000u;
        constexpr u32 VPOL_STRICT       = 0xA0000000u;
        constexpr u32 VPOL_AUTO         = 0xB0000000u;
        //!@}

        // Define unit scaling for VLAN rate-limiter configuration.
        constexpr u32 VRATE_SCALE_1X    = 0x00000000u;  // 1 LSB = 8 kbps
        constexpr u32 VRATE_SCALE_256X  = 0x08000000u;  // 1 LSB = 2 Mbps
        constexpr u64 VRATE_THRESHOLD   = 100000000;

        //! Common port-connection masks.
        //! \see `SwitchConfig::vlan_set_mask`.
        //!@{
        constexpr u32 VLAN_CONNECT_ALL  = (u32)(-1);
        constexpr u32 VLAN_CONNECT_NONE = 0;
        //!@}

        //! Data structure for configuring VLAN tagging policy of each port.
        struct VtagPolicy {
            //! Packed value holds the tag policy, port number, and default VID.
            //! (Format matches "eth_frame_vstrip.vhd" configuration register.)
            u32 value;

            //! Accessors for each individual field.
            //!@{
            inline u32 policy() const
                { return u32(value & 0x00FF0000); }
            inline unsigned port() const
                { return unsigned(value >> 24); }
            inline satcat5::eth::VlanTag vtag() const
                { return VlanTag{u16(value & 0x0000FFFF)}; }
            //!@}

            //! Each constructors creates a packed configuration word.
            //!  Bits 31..24 = Port index (0 - 255)
            //!  Bits 23..16 = Tagging policy (e.g., VTAG_ADMIT_ALL)
            //!  Bits 15..00 = Default tag value (VID + DEI + PCP)
            //!@{
            constexpr VtagPolicy(u32 port, u32 policy, VlanTag vtag = VTAG_DEFAULT)
                : value(policy | vtag.value | ((port & 0xFF) << 24)) {}
            constexpr VtagPolicy()
                : value(0) {}
            explicit constexpr VtagPolicy(u32 other)
                : value(other) {}
            constexpr VtagPolicy(const VtagPolicy& other)
                : value(other.value) {}
            VtagPolicy& operator=(const VtagPolicy& other)
                { value = other.value; return *this; }
            //!@}
        };

        //! Default VLAN tagging policy.
        constexpr satcat5::eth::VtagPolicy
            VCFG_DEFAULT(0, VTAG_ADMIT_ALL, VTAG_DEFAULT);

        //! Data structure for configuring VLAN rate-limiter parameters.
        //! See "mac_vlan_rate.vhd" for details on the token-bucket algorithm.
        struct VlanRate {
            u32 tok_policy;             //!< Policy and scaling
            u32 tok_rate;               //!< Tokens per millisecond
            u32 tok_max;                //!< Maximum accumulated tokens

            //! Convert bits-per-second to internal configuration word.
            static constexpr u32 bps2rate(u64 rate_bps) {
                return (rate_bps < VRATE_THRESHOLD)
                    ? u32(rate_bps / 8000)
                    : u32(rate_bps / 2000000);
            }

            //! Constructof for the default unlimited policy.
            constexpr VlanRate()        // Default constructor
                : tok_policy(VPOL_UNLIMITED)
                , tok_rate(0)
                , tok_max(0) {}
            //! Constructor for any other policy.
            constexpr VlanRate(
                u32 policy,             // Policy (e.g., VPOL_STRICT)
                u64 rate_bps,           // Rate limit (bits per second)
                u32 burst_msec=1)       // Burst duration in milliseconds
                : tok_policy(
                    rate_bps < VRATE_THRESHOLD
                    ? (policy | VRATE_SCALE_1X)
                    : (policy | VRATE_SCALE_256X))
                , tok_rate(bps2rate(rate_bps))
                , tok_max(burst_msec * bps2rate(rate_bps))
            {
                // Nothing else to initialize.
            }
        };

        //! Define some commonly-used rate-limiter configurations.
        //! Note: For moderate rates, it is safe to increase "burst_msec"
        //!  without requiring large buffers. Default target is ~4 kiB.
        //!@{
        constexpr satcat5::eth::VlanRate
            VRATE_ZERO          (VPOL_STRICT, 0, 0),
            VRATE_8KBPS         (VPOL_STRICT,        8000ull, 4096),
            VRATE_16KBPS        (VPOL_STRICT,       16000ull, 2048),
            VRATE_32KBPS        (VPOL_STRICT,       32000ull, 1024),
            VRATE_64KBPS        (VPOL_STRICT,       64000ull,  512),
            VRATE_128KBPS       (VPOL_STRICT,      128000ull,  256),
            VRATE_256KBPS       (VPOL_STRICT,      256000ull,  128),
            VRATE_512KBPS       (VPOL_STRICT,      512000ull,   64),
            VRATE_1MBPS         (VPOL_STRICT,     1000000ull,   32),
            VRATE_2MBPS         (VPOL_STRICT,     2000000ull,   16),
            VRATE_4MBPS         (VPOL_STRICT,     4000000ull,    8),
            VRATE_8MBPS         (VPOL_STRICT,     8000000ull,    4),
            VRATE_10MBPS        (VPOL_STRICT,    10000000ull,    3),
            VRATE_16MBPS        (VPOL_STRICT,    16000000ull,    2),
            VRATE_100MBPS       (VPOL_STRICT,   100000000ull),
            VRATE_1GBPS         (VPOL_STRICT,  1000000000ull),
            VRATE_10GBPS        (VPOL_STRICT, 10000000000ull),
            VRATE_UNLIMITED     (VPOL_UNLIMITED, 0, 0);
        //!@}

        //! Management functions for a SatCat5 Ethernet switch.
        class SwitchConfig {
        public:
            //! Attach to the designated ConfigBus address.
            SwitchConfig(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            //! Log some basic info about this switch.
            void log_info(const char* label);

            //! Number of ports on this switch.
            u32 port_count();

            //! Clear all EtherType-based priority settings.
            void priority_reset();

            //! Designate specific EtherType range(s) as high-priority.
            //! Each range is specified with a CIDR-style prefix-length:
            //!  * 0x1234/16 = EtherType 0x1234 only
            //!  * 0x1230/12 = EtherType 0x1230 through 0x123F
            bool priority_set(u16 etype, unsigned plen = 16);

            //! Enable or disable "miss-as-broadcast" flag on the specified port.
            //! Frames with an unknown destination (i.e., destination MAC not
            //! found in cache) are sent to every port with this flag.
            void set_miss_bcast(unsigned port_idx, bool enable);

            //! Identify which ports are currently in "miss-as-broadcast" mode.
            u32 get_miss_mask();

            //! Enable or disable "promiscuous" flag on the specified port index.
            //! For as long as the flag is set, those port(s) will receive ALL
            //! switch traffic regardless of the desitnation address.
            void set_promiscuous(unsigned port_idx, bool enable);

            //! Identify which ports are currently promiscuous.
            u32 get_promiscuous_mask();

            //! Set EtherType filter for traffic reporting. (0 = Any type)
            void set_traffic_filter(u16 etype = 0);
            //! Query the current traffic filter setting.
            inline u16 get_traffic_filter() const {return m_stats_filter;}

            //! Report matching frames since last call to get_traffic_count().
            u32 get_traffic_count();

            //! Get the minimum allowed frame size, in bytes.
            u16 get_frame_min();
            //! Get the maximum allowed frame size, in bytes.
            u16 get_frame_max();

            //! Get packet-logging register. \see eth_sw_log.h.
            //! Do not call this method unless LOG_CFGBUS is enabled.
            satcat5::cfg::Register get_log_register();

            //! PTP configuration for each port.
            //! Time units are in sub-nanoseconds (see ptp_time.h)
            //!@{
            s32  ptp_get_offset_rx(unsigned port_idx);
            s32  ptp_get_offset_tx(unsigned port_idx);
            u32  ptp_get_2step_mask();
            void ptp_set_offset_rx(unsigned port_idx, s32 subns);
            void ptp_set_offset_tx(unsigned port_idx, s32 subns);
            void ptp_set_2step(unsigned port_idx, bool enable);
            //!@}

            //! Revert all VLAN settings to default.
            void vlan_reset(bool lockdown = false);
            //! Get connected port-mask for the designated VLAN.
            u32 vlan_get_mask(u16 vid);
            //! Set connected port-mask for the designated VLAN.
            void vlan_set_mask(u16 vid, u32 mask);
            //! Set tag policy and other per-port settings.
            void vlan_set_port(const VtagPolicy& cfg);
            //! Join a given port to the designated VLAN.
            void vlan_join(u16 vid, unsigned port);
            //! Remote a given port from the designated VLAN.
            void vlan_leave(u16 vid, unsigned port);
            //! Set the maximum aggregated throughput for a given VID.
            void vlan_set_rate(u16 vid, const satcat5::eth::VlanRate& cfg);

            //! Read the maximum size of the MAC-address table.
            unsigned mactbl_size();
            //! Read the Nth entry from the MAC-address table.
            //! \return True if successful, false otherwise.
            bool mactbl_read(
                unsigned tbl_idx,                       // Table index to be read
                unsigned& port_idx,                     // Resulting port index
                satcat5::eth::MacAddr& mac_addr);       // Resulting MAC address
            //! Write a new entry to the MAC-address table.
            //! Note: When writing, FPGA logic chooses the next available table
            //!       index; this parameter is not under software control.
            bool mactbl_write(
                unsigned port_idx,                      // New port index
                const satcat5::eth::MacAddr& mac_addr); // New MAC address
            //! Clear MAC-address table contents.
            bool mactbl_clear();
            //! Enable automatic learning of new MAC addresses?
            bool mactbl_learn(bool enable);
            //! Log the contents of the MAC-address table.
            void mactbl_log(const char* label);

        protected:
            bool mactbl_wait_idle();                    // Wait for MAC-table access

            satcat5::cfg::Register m_reg;               // ConfigBus register space
            u32 m_pri_wridx;                            // Next index in priority table
            u16 m_stats_filter;                         // Filter stats by EtherType
        };
    }
}
