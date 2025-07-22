//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! "Icon" API for small monochrome images
//!
//!\details
//! This file defines an API for monochrome images, intended for
//! rendering text, icons, or simple animations in a graphical user
//! interface.  It also defines some useful examples in each format.
//!
//! For utility functions that convert general-purpose image files
//! into the format required here, please refer to the Python tool
//! located under "/sim/python/pixel_art.py".

#pragma once
#include <satcat5/types.h>

namespace satcat5 {
    namespace gui {
        //! Plain-old-data struct for an 8x8 monochrome image.
        //! \see gui_icons.h, gui::Icon16x16, gui::Icon32x32.
        //! Coordinates: Top row is index 0, left column is LSB.
        struct Icon8x8 {
            u8 data[8];     //!< 8 x 8 pixels = 8 bytes

            //! Get pixel value at designated row and column.
            //! Note: Plain-old-data requirement means we cannot
            //! use virtual methods to implement accessor methods.
            inline bool rc(u16 r, u16 c) const
                { return !!(data[r] & (1 << c)); }

            inline u16 h() const { return 8; }  //!< Width of this icon
            inline u16 w() const { return 8; }  //!< Height of this icon
        };

        //! Plain-old-data struct for a 16x16 monochrome image.
        //! \see gui_icons.h, gui::Icon8x8, gui::Icon32x32.
        //! Coordinates: Top row is index 0, left column is LSB.
        struct Icon16x16 {
            u16 data[16];   //!< 16 x 16 pixels = 32 bytes

            //! Get pixel value at designated row and column.
            inline bool rc(u16 r, u16 c) const
                { return !!(data[r] & (1 << c)); }

            inline u16 h() const { return 16; }  //!< Width of this icon
            inline u16 w() const { return 16; }  //!< Height of this icon
        };

        //! Plain-old-data struct for a 32x32 monochrome image.
        //! \see gui_icons.h, gui::Icon8x8, gui::Icon16x16.
        //! Coordinates: Top row is index 0, left column is LSB.
        struct Icon32x32 {
            u32 data[32];   //!< 32 x 32 pixels = 128 bytes

            //! Get pixel value at designated row and column.
            inline bool rc(u16 r, u16 c) const
                { return !!(data[r] & (1 << c)); }

            inline u16 h() const { return 32; }  //!< Width of this icon
            inline u16 w() const { return 32; }  //!< Height of this icon
        };

        //! The Font class maps characters to fixed-size icons.
        //! \see gui_icons.h, gui::Icon8x8, gui::Icon16x16, gui::Icon32x32.
        //! The Font-class template can be specialized for Icon8x8, Icon16x16,
        //! or Icon32x32. For now,only ASCII printable characters 0x20 through
        //! 0x7E are supported. (UTF-8 tokens outside this range return NULL.)
        template <class T> class Font {
        public:
            //! Link the Font to an array of icon objects in ASCII order.
            explicit constexpr Font(const T* data)
                : m_data(data) {}

            //! Fetch the icon associated with a given character.
            const T* icon(char c) const {
                if (c < 0x20 || c > 0x7E) return 0;
                return m_data + unsigned(c - 0x20);
            }

        protected:
            const T* const m_data;
        };

        typedef Font<Icon8x8>   Font8x8;    //!< Font for 8x8 icons.
        typedef Font<Icon16x16> Font16x16;  //!< Font for 16x16 icons.
        typedef Font<Icon32x32> Font32x32;  //!< Font for 32x32 icons.

        //! A data structure for storing a looping sequence of icons.
        template <class T> struct Animation {
            const T* icons;                 //! An array of icons.
            unsigned count;                 //! Number of icon frames.
            unsigned msec;                  //! Milliseconds per frame.
        };

        //! A basic fixed-width 8x8 font.
        extern const Font8x8    BASIC_FONT;

        //! The Aerospace Corporation logo in various sizes.
        //!@{
        extern const Icon16x16  AEROLOGO_ICON16;
        extern const Icon32x32  AEROLOGO_ICON32;
        //!@}

        //! A cat's paw or footprint.
        extern const Icon8x8    PAW_ICON8;

        //! The SatCat5 mascot in various sizes.
        //!@{
        extern const Icon8x8    SATCAT5_ICON8;
        extern const Icon16x16  SATCAT5_ICON16;
        //!@}

        //! Animations of a cat performing various activities.
        //! Each animation defines a loop.  Best viewed at ~125 ms per frame,
        //!  except for SIT and SLEEP, which should use ~250 ms per frame.
        //!@{
        extern const Icon16x16
            CAT_GROOM[8], CAT_HISS[8], CAT_PAW[8], CAT_POUNCE[8],
            CAT_RUN[8], CAT_SIT[8], CAT_SLEEP[8], CAT_WALK[8];
        constexpr Animation<Icon16x16>
            ANIM_CAT_GROOM  {satcat5::gui::CAT_GROOM,  8, 125},
            ANIM_CAT_HISS   {satcat5::gui::CAT_HISS,   8, 125},
            ANIM_CAT_PAW    {satcat5::gui::CAT_PAW,    8, 125},
            ANIM_CAT_POUNCE {satcat5::gui::CAT_POUNCE, 8, 125},
            ANIM_CAT_RUN    {satcat5::gui::CAT_RUN,    8, 125},
            ANIM_CAT_SIT    {satcat5::gui::CAT_SIT,    8, 250},
            ANIM_CAT_SLEEP  {satcat5::gui::CAT_SLEEP,  8, 250},
            ANIM_CAT_WALK   {satcat5::gui::CAT_WALK,   8, 125};
        //!@}
    }
}
