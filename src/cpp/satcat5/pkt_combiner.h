//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Combine packets
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/polling.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        //! The PacketCombiner class combines packets written to it into a
        //! single packet, and forwards it to a Writeable destination. The
        //! write is finalized when the destination is full.
        //!
        //! An optional timeout can be enabled using `set_timeout()` to force
        //! the data to be forwarded after a period of time regardless of
        //! whether the destination is full.
        class PacketCombiner
            : public satcat5::io::WriteableRedirect
            , public satcat5::io::EventListener
            , public satcat5::poll::Timer
        {
        public:
            //! Create an object that combines packets.
            PacketCombiner(satcat5::io::Writeable* dst,
                          u8* buff, unsigned buffbytes);
            ~PacketCombiner() {}

            //! Send the buffer now.
            void send_now();

            //! Set a timeout for automatic data forwarding after a period, if
            //! the buffer is not yet full. A timeout of zero disables this
            //! function.
            void set_timeout(unsigned msec);
        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            void timer_event() override;

            satcat5::io::Writeable* m_dst;
            satcat5::io::PacketBuffer m_buff;
            unsigned m_timeout;
        };

        //! PacketCombiner with statically-allocated working memory.
        //!
        //! Optional template parameter specifies buffer size.  If user does
        //! not specify a size, use SATCAT5_DEFAULT_PKTBUFF = 1600 bytes.
        template<unsigned SIZE = SATCAT5_DEFAULT_PKTBUFF>
        class PacketCombinerStatic final : public satcat5::io::PacketCombiner {
        public:
            //! Link parent object to the statically allocated buffer.
            PacketCombinerStatic(satcat5::io::Writeable* dst)
                : PacketCombiner(dst, m_raw, SIZE), m_raw{} {}
        private:
            u8 m_raw[SIZE];
        };
    }
}
