//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! CBOR (IETF RFC8949) Readable/Writeable interface
//!

#pragma once

#include <satcat5/io_writeable.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_encode.h>

//! Set the default size for the QCBOR buffer
#ifndef SATCAT5_QCBOR_BUFFER
#define SATCAT5_QCBOR_BUFFER 1500
#endif

namespace satcat5 {
    namespace io {
        //! Creates an ephemeral writer for the Concise Binary Object
        //! Representation (CBOR, IETF RFC8949), holding underlying objects and
        //! adapting output to an io::Writeable destination.
        //!
        //! This writer wraps the QCBOR library into a more familiar interface
        //! that performs stack buffer allocation and io::Writeable handling
        //! automatically. Since CBOR key/value pairs and arrays require a
        //! length prefix, QCBOR requires a working buffer to hold the
        //! in-progress object, which is stack-allocated with size
        //! `SATCAT5_QCBOR_BUFFER`.
        //!
        //! Most users should be able to hit target functionality with usage of
        //! io::CborMapWriter or other future wrappers. However, the QCBOR
        //! encode context `cbor` is a public member variable that may be used
        //! for calls to `QCBOREncode_*` functions for complex use-cases outside
        //! the scope of given wrapper classes.
        //!
        //! Usage:
        //!  * Create a CborMapWriter object attached to any io::Writeable sink.
        //!  * Use member functions of a child class such as io::CborMapWriter
        //!    to write a valid CBOR Map object.
        //!  * For any edge cases, use `QCBOREncode_*` functions with the given
        //!    QCBOR context `cbor`.
        //!  * Call `close()` or `close_and_finalize()` to validate the CBOR
        //!    object and optionally write it to the io::Writeable sink if
        //!    valid.
        //!  * If `close()` was called instead of `close_and_finalize()`, write
        //!    any remaining bytes (not typical) and call
        //!    `io::Writeable::write_finalize()`.
        //!
        //! Most users should instantiate CborMapWriterStatic instead of this to
        //! perform all stack buffer allocation.
        //!
        //! \see satcat5::io::CborMapWriter
        class CborWriter {
        public:
            //! Close the QCBOR encoder by calling `QCBOREncode_Finish` and copy
            //! the resulting bytes to `m_dst`.
            bool close();

            //! Calls `close()` then `m_dst.write_finalize()`.
            inline bool close_and_finalize()
                { return close() && m_dst->write_finalize(); }

            //! Get the encoded data, useful if no `dst` was given.
            UsefulBufC get_encoded() { return { m_encoded, m_encoded_len }; }

            // Member variables
            QCBOREncodeContext* const cbor;         //!< QCBOR context pointer

        protected:
            //! Constructor requires child class to provide a working buffer.
            //!
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            //! \param buff Backing buffer for QCBOR.
            //! \param size Backing buffer size for QCBOR.
            //! \param automap Open/close a top-level Map automatically.
            //!
            //! Note: automap is necessary in the base class due to the
            //! potential existence of multiple templated CborMapWriter classes.
            CborWriter(satcat5::io::Writeable* dst, u8* buff, unsigned size,
                bool automap=false);

            // Member variables
            satcat5::io::Writeable* const m_dst;    //!< Writeable sink
            const u8* m_encoded;                    //!< Encoded data
            unsigned m_encoded_len;                 //!< Encoded length
            bool m_automap;                         //!< Auto-open/close a Map?

        private:
            QCBOREncodeContext m_cbor_alloc;        //!< QCBOR context
        };

        //! CborWriter variant with a statically-allocated buffer; most users
        //! should instantiate this instead of CborWriter.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::io::CborWriter
        template <unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class CborWriterStatic : public CborWriter {
        public:
            //! Create this object and set the destination.
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            explicit CborWriterStatic(satcat5::io::Writeable* dst)
                : CborWriter(dst, m_raw, SIZE) {}

        private:
            u8 m_raw[SIZE];
        };

        //! Adds functions to write a series of key-value pairs to a top-level
        //! CBOR Map.
        //!
        //! A common CBOR use case is to have a single Map at the top level with
        //! several keys of the same type (string, uint, etc.). Appending
        //! multiple of these together is out of the CBOR specification and is a
        //! CBOR Sequence (CBORSEQ) defined in a separate specification, so only
        //! one map may be written with this class.
        //!
        //! \see satcat5::io::CborMapWriterStatic
        //! \copydoc satcat5::io::CborWriter
        template <typename KEYTYPE = const char*>
        class CborMapWriter : virtual public CborWriter {
        public:
            //! Write a scalar value to the Map.
            //! @{
            inline void add_bool(KEYTYPE key, bool value) const
                { add_key(key); QCBOREncode_AddBool(cbor, value); }
            inline void add_item(KEYTYPE key, s8 value) const
                { add_key(key); QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(KEYTYPE key, s16 value) const
                { add_key(key); QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(KEYTYPE key, s32 value) const
                { add_key(key); QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(KEYTYPE key, s64 value) const
                { add_key(key); QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(KEYTYPE key, u8 value) const
                { add_key(key); QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(KEYTYPE key, u16 value) const
                { add_key(key); QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(KEYTYPE key, u32 value) const
                { add_key(key); QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(KEYTYPE key, u64 value) const
                { add_key(key); QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(KEYTYPE key, float value) const
                { add_key(key); QCBOREncode_AddFloat(cbor, value); }
            inline void add_item(KEYTYPE key, double value) const
                { add_key(key); QCBOREncode_AddDouble(cbor, value); }
            //! @}

            //! Write an array of scalar values to the Map.
            //! @{
            void add_array(KEYTYPE key, u32 len, const bool* value) const;
            inline void add_array(KEYTYPE key, u32 len, const s8* value) const
                { add_key(key); add_signed_array<s8>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const s16* value) const
                { add_key(key); add_signed_array<s16>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const s32* value) const
                { add_key(key); add_signed_array<s32>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const s64* value) const
                { add_key(key); add_signed_array<s64>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const u8* value) const
                { add_key(key); add_unsigned_array<u8>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const u16* value) const
                { add_key(key); add_unsigned_array<u16>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const u32* value) const
                { add_key(key); add_unsigned_array<u32>(len, value); }
            inline void add_array(KEYTYPE key, u32 len, const u64* value) const
                { add_key(key); add_unsigned_array<u64>(len, value); }
            void add_array(KEYTYPE key, u32 len, const float* value) const;
            void add_array(KEYTYPE key, u32 len, const double* value) const;
            //! @}

            //! Write a byte sequence to the Map.
            inline void add_bytes(KEYTYPE key, u32 len, const u8* value) const
                { add_key(key); QCBOREncode_AddBytes(cbor, {value, len}); }

            //! Write a null-terminated string to the Map.
            inline void add_string(KEYTYPE key, const char* value) const
                { add_key(key); QCBOREncode_AddSZString(cbor, value); }

            //! Write a key with a null value to the Map.
            inline void add_null(KEYTYPE key) const
                { add_key(key); QCBOREncode_AddNULL(cbor); }

        protected:
            //! \copydoc satcat5::io::CborWriter::CborWriter()
            CborMapWriter(satcat5::io::Writeable* dst, u8* buff, unsigned size)
                : CborWriter(dst, buff, size, true) {} // Auto-map enabled

            //! Templated function to write the correct key type to the Map.
            void add_key(KEYTYPE key) const;

            //! Templated function to add an array of unsigned values.
            template <typename T>
            void add_unsigned_array(unsigned len, const T* value) const;

            //! Templated function to add an array of signed values.
            template <typename T>
            void add_signed_array(unsigned len, const T* value) const;
        };

        //! CborMapWriter variant with a statically-allocated buffer; most users
        //! should instantiate this instead of CborMapWriter.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::io::CborMapWriter
        template <
            typename KEYTYPE = const char*,
            unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class CborMapWriterStatic : public CborMapWriter<KEYTYPE> {
        public:
            //! Create this object and set the destination.
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            explicit CborMapWriterStatic(satcat5::io::Writeable* dst)
                : CborWriter(dst, m_raw, SIZE, true)
                , CborMapWriter<KEYTYPE>(dst, m_raw, SIZE) {}

        private:
            u8 m_raw[SIZE];
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
