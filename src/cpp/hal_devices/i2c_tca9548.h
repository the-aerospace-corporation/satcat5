//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Device driver for PCA9548A / TCA9548A I2C switches.

#pragma once

#include <satcat5/cfg_i2c.h>
#include <satcat5/utils.h>

#ifndef SATCAT5_I2C_MAXCMD
#define SATCAT5_I2C_MAXCMD  16      // Each queue up to N transactions
#endif

namespace satcat5 {
    namespace device {
        namespace i2c {
            //! Device driver for PCA9548A / TCA9548A I2C switches.
            //! The NXP Semiconductors PCA9548A and the Texas Instruments
            //! TCA9548A are pin-compatible devices that connect one I2C
            //! master to one of eight I2C channels.  This driver controls
            //! either device, allowing for channel selection and then
            //! presenting an I2C interface for downstream devices to use.
            //!
            //! Reference: https://www.nxp.com/docs/en/data-sheet/PCA9548A.pdf
            //! Reference: https://www.ti.com/product/TCA9548A
            class Tca9548
                : public satcat5::cfg::I2cGeneric
                , public satcat5::cfg::I2cEventListener
            {
            public:
                //! Constructor links to the specified I2C bus.
                Tca9548(
                    satcat5::cfg::I2cGeneric* i2c,          // Parent interface
                    const satcat5::util::I2cAddr& devaddr); // Device address

                //! Select a channel or channel(s).
                //! Due to limited buffer space, the caller is responsible for
                //! retrying commands that cannot be queued immediately.
                //! \return True on success, false for retry.
                bool select_mask(u8 mask);

                //! Shortcut for selecting a specific channel. \see select_mask
                inline bool select_channel(unsigned n)
                    {return select_mask((u8)(1u << n));}

                // Forward read/write calls to the parent.
                bool busy() override;
                bool read(const satcat5::util::I2cAddr& devaddr,
                    u8 regbytes, u32 regaddr, u8 nread,
                    satcat5::cfg::I2cEventListener* callback = 0) override;
                bool write(const satcat5::util::I2cAddr& devaddr,
                    u8 regbytes, u32 regaddr, u8 nwrite, const u8* data,
                    satcat5::cfg::I2cEventListener* callback = 0) override;

            protected:
                // Forward callbacks to the original caller.
                void i2c_done(
                    bool noack, const satcat5::util::I2cAddr& devaddr,
                    u32 regaddr, unsigned nread, const u8* rdata) override;

                // Calculate write-index for the circular buffer.
                inline unsigned cb_wridx() const
                    {return satcat5::util::modulo_add_uns(m_cb_rdidx + m_cb_count, SATCAT5_I2C_MAXCMD);}

                // Pointer to the parent interface.
                satcat5::cfg::I2cGeneric* const m_parent;
                const satcat5::util::I2cAddr m_devaddr;

                // Circular queue of pending callbacks.
                unsigned m_cb_count;
                unsigned m_cb_rdidx;
                satcat5::cfg::I2cEventListener* m_cb_queue[SATCAT5_I2C_MAXCMD];
            };

            //! Alias for PCA9548A, which has the same control API.
            //! \see device::i2c::Tca9548
            typedef satcat5::device::i2c::Tca9548 Pca9548;
        }
    }
}
