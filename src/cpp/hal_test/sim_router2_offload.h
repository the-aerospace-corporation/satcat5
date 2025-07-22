//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simulate the router2::Offload port's ConfigBus interface.

#pragma once

#include <hal_test/sim_utils.h>
#include <vector>

namespace satcat5 {
    namespace test {
        //! Simulate the router2::Offload port's ConfigBus interface.
        class MockOffload
            : public satcat5::test::MockConfigBusMmap
            , satcat5::poll::Always {
        public:
            //! Create the mock interface and set ConfigBus device address.
            explicit MockOffload(unsigned devaddr);
            ~MockOffload();

            //! Link the next hardware port to a destination and source.
            void add_port(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

            //! Update the reported port-status flags.
            void port_shdn(u32 mask_shdn);

        private:
            // Helper class representing a single port.
            class Port final : public satcat5::io::EventListener {
            public:
                Port(unsigned index, MockOffload* parent,
                    satcat5::io::Writeable* dst,
                    satcat5::io::Readable* src);
                ~Port();

                void data_rcvd(satcat5::io::Readable* src) override;
                void data_unlink(satcat5::io::Readable* src) override;
                inline u32 port_mask() const {return 1u << m_index;}

                const unsigned m_index;
                MockOffload* const m_parent;
                satcat5::io::Writeable* const m_dst;
                satcat5::io::Readable* m_src;
            };

            // Copy data from the hardware buffer to the designated port(s).
            void poll_always() override;

            // If the hardware receive buffer is empty, copy incoming data.
            bool copy_to_hwbuf(unsigned idx, satcat5::io::Readable* src);

            friend Port;
            u32* const m_dev;
            std::vector<Port*> m_ports;
        };
    }
}
