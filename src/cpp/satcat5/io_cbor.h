//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! CBOR (IETF RFC8949) Readable/Writeable interface
//!
//! This file provides an API for reading and writing messages encoded
//! using the Concise Binary Object Representation (CBOR), defined in
//! [IETF RFC8949](https://www.rfc-editor.org/rfc/rfc8949).  The API
//! is backed by calls to the QCBOR library.
//!
//! When decoding a CBOR message, the most commonly-used classes are
//! cbor::ListReaderStatic (if the top-level is a list or array) and
//! cbor::MapReaderStatic (if the top-level is a key/value dictionary).
//! Given a data source, these automatically create the required QCBOR
//! objects and working buffer. For lists, items are read sequentially.
//! For key/value maps, items are requested by key. Templates indicate
//! whether the keys integers (s64) or strings (const char*).
//!
//! When encoding a CBOR message, the most commonly-used clases are
//! cbor::ListWriterStatic and cbor::MapWriterStatic.
//!
//! When reading or writing complex CBOR messages with nested data structures
//! (e.g., a dictionary containing a list of sub-dictionaries), use the
//! open_list or open_map methods to access the inner QCBOR object. Then,
//! create a cbor::ListReader, cbor::MapReader, cbor::ListWriter, or
//! cbor::MapWriter to continue parsing the inner list or map. Finally,
//! call close_list or close_map to resume parsing of the outer message.
//! These objects do not use the "static" classes because they share the
//! same working buffer, so no additional allocation is required.
//!
//! \see cbor::ListReader, cbor::ListReaderStatic
//! \see cbor::ListWriter, cbor::ListWriterStatic
//! \see cbor::MapReader,  cbor::MapReaderStatic
//! \see cbor::MapWriter,  cbor::MapWriterStatic
//!

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_encode.h>
#include <qcbor/qcbor_spiffy_decode.h>

//! Set the default size for the QCBOR buffer
#ifndef SATCAT5_QCBOR_BUFFER
#define SATCAT5_QCBOR_BUFFER 1500
#endif

namespace satcat5 {
    namespace cbor {
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
        //! cbor::MapWriter or other future wrappers. However, the QCBOR
        //! encode context `cbor` is a public member variable that may be used
        //! for calls to `QCBOREncode_*` functions for complex use-cases outside
        //! the scope of given wrapper classes.
        //!
        //! Usage:
        //!  * Create a CborWriter object attached to any io::Writeable sink.
        //!  * Use member functions of a child class such as cbor::ListWriter
        //!    or cbor::MapWriter to write a valid CBOR Map object.
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
        //! \see satcat5::cbor::ListWriter, satcat5::cbor::MapWriter.
        class CborWriter {
        public:
            //! Close the QCBOR encoder by calling `QCBOREncode_Finish` and copy
            //! the resulting bytes to `m_dst`, if one was provided.
            bool close();

            //! Calls `close()` then `m_dst.write_finalize()`.
            inline bool close_and_finalize()
                { return close() && m_dst && m_dst->write_finalize(); }

            //! Get encoded data as a UsefulBuf, useful if no `dst` was given.
            //! Automatically calls `close()` if the buffer is still open.
            UsefulBufC get_encoded();

            //! Get encoded data as a Readable, useful if no `dst` was given.
            //! Automatically calls `close()` if the buffer is still open.
            satcat5::io::Readable* get_buffer();

            //! Finish writing a list to the List.
            //! When closing a List, the caller may use the original object that
            //! opened it or another CborWriter derived from the same context.
            //! \see ListWriter::open_list, MapWriter::open_list.
            inline void close_list()
                { QCBOREncode_CloseArray(cbor); }

            //! Finish writing a nested dictionary to the Map.
            //! When closing a Map, the caller may use the original object that
            //! opened it or another CborWriter derived from the same context.
            //! \see ListWriter::open_map, MapWriter::open_map.
            inline void close_map()
                { QCBOREncode_CloseMap(cbor); }

            // Member variables
            QCBOREncodeContext* const cbor;         //!< QCBOR context pointer

        protected:
            //! Constructor requires child class to provide a working buffer.
            //! This constructor is protected for use by child objects only.
            //! \see ListWriterStatic, MapWriterStatic.
            //!
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            //! \param encode Pointer to an uninitialized QCBOR encoder object.
            //! \param buff Backing buffer for QCBOR.
            //! \param size Backing buffer size for QCBOR.
            //! \param automap Open/close a top-level Map automatically.
            //!
            //! Note: automap is necessary in the base class due to the
            //! potential existence of multiple templated MapWriter classes.
            CborWriter(
                satcat5::io::Writeable* dst,
                QCBOREncodeContext* encode,
                u8* buff, unsigned size,
                bool automap=false);

            //! Create a CborWriter from an existing encoder context.
            //! This constructor is protected for use by child objects only.
            //! \see ListWriter, MapWriter.
            explicit constexpr CborWriter(QCBOREncodeContext* encode)
                : cbor(encode)
                , m_dst(nullptr)
                , m_encoded(nullptr)
                , m_encoded_len(0)
                , m_auto_close(QCBOR_TYPE_NONE)
                , m_read(encode->OutBuf.UB.ptr, 0)
                {} // Nothing else to initialize.

            // Prohibit unsafe copy constructor and assignment operator.
            CborWriter(const CborWriter& other) = delete;
            CborWriter& operator=(const CborWriter& other) = delete;

            //! Templated function to add an array of unsigned values.
            template <typename T>
            void add_unsigned_array(unsigned len, const T* value) const;

            //! Templated function to add an array of signed values.
            template <typename T>
            void add_signed_array(unsigned len, const T* value) const;

            // Member variables
            satcat5::io::Writeable* const m_dst;    //!< Writeable sink
            const u8* m_encoded;                    //!< Encoded data
            unsigned m_encoded_len;                 //!< Encoded length
            u8 m_auto_close;                        //!< Auto-close QCBOR Type
            satcat5::io::ArrayRead m_read;          //!< Reads working buffer
        };

        //! Write a series of consecutive items to a CBOR message.
        //! \see satcat5::ListWriterStatic, satcat5::cbor::MapWriter
        //! \copydoc satcat5::cbor::CborWriter
        class ListWriter : public CborWriter {
        public:
            //! Create a ListWriter from an existing encoder context.
            explicit constexpr ListWriter(QCBOREncodeContext* encode)
                : CborWriter(encode) {}

            //! Write a scalar value to the List.
            //! @{
            inline void add_bool(bool value) const
                { QCBOREncode_AddBool(cbor, value); }
            inline void add_item(s8 value) const
                { QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(s16 value) const
                { QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(s32 value) const
                { QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(s64 value) const
                { QCBOREncode_AddInt64(cbor, value); }
            inline void add_item(u8 value) const
                { QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(u16 value) const
                { QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(u32 value) const
                { QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(u64 value) const
                { QCBOREncode_AddUInt64(cbor, value); }
            inline void add_item(float value) const
                { QCBOREncode_AddFloat(cbor, value); }
            inline void add_item(double value) const
                { QCBOREncode_AddDouble(cbor, value); }
            //! @}

            //! Write an array of scalar values to the List.
            //! @{
            void add_array(u32 len, const bool* value) const;
            inline void add_array(u32 len, const s8* value) const
                { add_signed_array<s8>(len, value); }
            inline void add_array(u32 len, const s16* value) const
                { add_signed_array<s16>(len, value); }
            inline void add_array(u32 len, const s32* value) const
                { add_signed_array<s32>(len, value); }
            inline void add_array(u32 len, const s64* value) const
                { add_signed_array<s64>(len, value); }
            inline void add_array(u32 len, const u8* value) const
                { add_unsigned_array<u8>(len, value); }
            inline void add_array(u32 len, const u16* value) const
                { add_unsigned_array<u16>(len, value); }
            inline void add_array(u32 len, const u32* value) const
                { add_unsigned_array<u32>(len, value); }
            inline void add_array(u32 len, const u64* value) const
                { add_unsigned_array<u64>(len, value); }
            void add_array(u32 len, const float* value) const;
            void add_array(u32 len, const double* value) const;
            //! @}

            //! Write a byte sequence to the List.
            //!@{
            inline void add_bytes(u32 len, const u8* value) const
                { QCBOREncode_AddBytes(cbor, {value, len}); }
            inline void add_bytes(const u8* value, u32 len) const
                { QCBOREncode_AddBytes(cbor, {value, len}); }
            //!@}

            //! Add a nested list to the List. \see close_list.
            //! This allows creation of a sub-item containing an array or list
            //! of items with various type(s). The user should call open_list(),
            //! write value(s) as desired, then call close_map().
            QCBOREncodeContext* open_list();

            //! Add a nested dictionary to the List. \see close_map.
            //! Append a self-contained key/value dictionary. The user should
            //! call open_map(), write key/value pairs, then call close_map().
            QCBOREncodeContext* open_map();

            //! Write a null-terminated string to the Map.
            inline void add_string(const char* value) const
                { QCBOREncode_AddSZString(cbor, value); }

            //! Write a key with a null value to the Map.
            inline void add_null() const
                { QCBOREncode_AddNULL(cbor); }

        protected:
            //! Constructor requires child class to provide a working buffer.
            //! This constructor is protected for use by child objects only.
            //! \see ListWriterStatic.
            //! \copydoc satcat5::cbor::CborWriter::CborWriter()
            ListWriter(
                    satcat5::io::Writeable* dst,
                    QCBOREncodeContext* encode,
                    u8* buff, unsigned size)
                : CborWriter(dst, encode, buff, size, false)
                {
                    // Open the top-level list and trigger array auto-close.
                    QCBOREncode_OpenArray(cbor);
                    m_auto_close = QCBOR_TYPE_ARRAY;
                }
        };

        //! Write a series of key-value pairs to a CBOR Map.
        //!
        //! A common CBOR use case is to have a single Map at the top level with
        //! several keys of the same type (string, uint, etc.). Appending
        //! multiple of these together is out of the CBOR specification and is a
        //! CBOR Sequence (CBORSEQ) defined in a separate specification, so only
        //! one map may be written with this class. A template parameter is
        //! provided for the key type to be written to the map - QCBOR currently
        //! only supports usage of string (`const char*`) and integer (`s64`)
        //! keys.
        //!
        //! Note: Virtual inheritance is used here to allow APIs with mixed
        //! integer and string keys, such as net::TelemetryCbor.
        //!
        //! \see satcat5::cbor::MapWriterStatic, satcat5::cbor::ListWriter
        //! \copydoc satcat5::cbor::CborWriter
        template <typename KEYTYPE = const char*>
        class MapWriter : virtual public CborWriter {
        public:
            //! Create a MapWriter from an existing encoder context.
            explicit constexpr MapWriter(QCBOREncodeContext* encode)
                : CborWriter(encode) {}

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
            //!@{
            inline void add_bytes(KEYTYPE key, u32 len, const u8* value) const
                { add_key(key); QCBOREncode_AddBytes(cbor, {value, len}); }
            inline void add_bytes(KEYTYPE key, const u8* value, u32 len) const
                { add_key(key); QCBOREncode_AddBytes(cbor, {value, len}); }
            //!@}

            //! Add a list to the Map. \see CborWriter::close_list.
            //! This allows creation of a key where the associated value is
            //! is an array or list of items with various type(s). The user
            //! should call open_list(), write values, then call close_map().
            QCBOREncodeContext* open_list(KEYTYPE key);

            //! Add a nested dictionary to the Map. \see CborWriter::close_map.
            //! This allows creation of a key where the associated value is
            //! is a self-contained key/value dictionary. The user should call
            //! open_map(), write key/value pairs, then call close_map().
            QCBOREncodeContext* open_map(KEYTYPE key);

            //! Write a null-terminated string to the Map.
            inline void add_string(KEYTYPE key, const char* value) const
                { add_key(key); QCBOREncode_AddSZString(cbor, value); }

            //! Write a key with a null value to the Map.
            inline void add_null(KEYTYPE key) const
                { add_key(key); QCBOREncode_AddNULL(cbor); }

        protected:
            //! Placeholder constructor with no side-effects.
            //! This method should be used for virtual inheritance ONLY.
            //! Since this class has no internal members, it requires no
            //! arguments. Due to virtual inheritance, the placeholder call to
            //! the parent constructor (CborWriter) is never actually used.
            //! The child class should create CborWriter with automap = true.
            MapWriter() : CborWriter(0, 0, 0, 0, 0) {}

            //! Templated function to write the correct key type to the Map.
            void add_key(KEYTYPE key) const;
        };

        //! ListWriter variant with a statically-allocated buffer.
        //! Most users should instantiate this instead of ListWriter.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::cbor::ListWriter
        template <unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class ListWriterStatic : public ListWriter {
        public:
            //! Create this object and set the destination.
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            explicit ListWriterStatic(satcat5::io::Writeable* dst = nullptr)
                : ListWriter(dst, &m_cbor, m_raw, SIZE) {}

        private:
            QCBOREncodeContext m_cbor;
            u8 m_raw[SIZE];
        };

        //! MapWriter variant with a statically-allocated buffer.
        //! Most users should instantiate this instead of MapWriter.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::cbor::MapWriter
        template <
            typename KEYTYPE = const char*,
            unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class MapWriterStatic : public MapWriter<KEYTYPE> {
        public:
            //! Create this object and set the destination.
            //! \param dst Writeable destination, or NULL if child classes will
            //!            access the buffer directly after `close()`.
            explicit MapWriterStatic(satcat5::io::Writeable* dst = nullptr)
                : CborWriter(dst, &m_cbor, m_raw, SIZE, true) {}

        private:
            QCBOREncodeContext m_cbor;
            u8 m_raw[SIZE];
        };

        //! Creates an ephemeral reader for the Concise Binary Object
        //! Representation (CBOR, IETF RFC8949), holding underlying objects and
        //! providing more concise member functions.
        //!
        //! This reader wraps the QCBOR library into a more familiar interface
        //! that performs stack buffer allocation and io::Readable handling
        //! automatically. QCBOR decode requires a working buffer to hold the
        //! in-progress object, which should be allocated by a child class,
        //! typically cbor::ListReaderStatic or cbor::MapReaderStatic.
        //!
        //! Most users should be able to hit target functionality with usage of
        //! cbor::ListReader cbor::MapReader or other future wrappers. However,
        //! the QCBOR decode context `cbor` is a public member variable that may
        //! be used for calls to `QCBORDecode_*` functions for complex use-cases
        //! outside the scope of provided wrapper classes.
        //!
        //! Usage:
        //!  * Create a CborReader object, which copies from any io::Readable
        //!    sink and calls read_finalize(). If no io::Readable is passed, the
        //!    given buffer is assumed to be populated with a CBOR payload.
        //!  * Use member functions of a child class such as cbor::ListReader
        //!    or cbor::MapReader to read a valid CBOR list or map, respectively.
        //!  * For any edge cases, use `QCBORDecode_*` functions with the given
        //!    QCBOR context `cbor`.
        //!
        //! Most users should instantiate ListReaderStatic or MapReaderStatic
        //! instead of this to perform all stack buffer allocation.
        //!
        //! \see satcat5::cbor::ListReader, satcat5::cbor::MapReader
        class CborReader {
        public:
            //! Check if any errors have been encountered yet during decoding.
            inline bool ok() const
                { return (get_error() == QCBOR_SUCCESS); }

            //! Get the QCBOR decoding error, if any.
            inline QCBORError get_error() const
                { return QCBORDecode_GetError(cbor); }

            //! Resume parsing at the end of a nested list.
            //! \see ListReader::open_list, MapReader::open_list.
            inline void close_list() const
                { QCBORDecode_ExitArray(cbor); }

            //! Resume parsing at the end of a nested dictionary.
            //! \see ListReader::open_map, MapReader::open_map.
            inline void close_map() const
                { QCBORDecode_ExitMap(cbor); }

            //! Copy the next CBOR item to the specified destination.
            //! If the next item is a nested data structure, this copies
            //! the entire data structure to the destination object.
            //! \returns True if an item was copied successfully.
            bool copy_item(QCBOREncodeContext* dst);

            //! Copy all remaining CBOR item(s) to the specified destination.
            //! \returns The number of items copied.
            unsigned copy_all(QCBOREncodeContext* dst);

            // Error return codes for array reading, values in io_cbor.cc.
            static const int ERR_NOT_FOUND;     //!< Key not found.
            static const int ERR_OVERFLOW;      //!< Overflowed user array.
            static const int ERR_BAD_TYPE;      //!< Non-matching type.
            static const int ERR_QCBOR_INT;     //!< Misc QCBOR error.

            // TODO: Below fails to link?
            // Get a string representing the QCBOR decoding error, if any.
            // inline const char* get_error_str() const
            //     { return qcbor_err_to_str(QCBORDecode_GetError(cbor)); }

            // Member variables
            QCBORDecodeContext* const cbor;         //!< QCBOR context pointer

        protected:
            //! Opens a QCBOR Decode Context from an io::Readable.
            //! Constructor requires child class to provide a working buffer.
            //!
            //! \param src Readable source to decode, or NULL if buffers are
            //!            already populated.
            //! \param decode Pointer to an uninitialized QCBOR encoder object.
            //! \param buff Backing buffer for QCBOR.
            //! \param size Backing buffer size for QCBOR.
            CborReader(
                satcat5::io::Readable* src,
                QCBORDecodeContext* decode,
                u8* buff, unsigned size);

            //! Create a CborReader from an existing decoder context.
            explicit constexpr CborReader(QCBORDecodeContext* decode)
                : cbor(decode), m_item{} {}

            // Prohibit unsafe copy constructor and assignment operator.
            CborReader(const CborReader& other) = delete;
            CborReader& operator=(const CborReader& other) = delete;

            //! Internal function for shared array logic.
            //! This function is called by all other "get_array" variants.
            int get_array_internal(
                satcat5::io::Writeable& dst, u8 qcbor_type, u8 type_size) const;

            //! Predict the length of the next integer value.
            //! Standard integers may be 1, 2, 3, 5, or 9 bytes.
            //! \returns Length in bytes, or zero on error.
            unsigned peek_integer_len(const u8* rdptr) const;

            // Member variables
            QCBORItem m_item;                       //!< QCBOR Decoder item
        };

        //! Read consecutive values from a CBOR Array/List.
        //! CBOR makes no formal distinction between arrays and lists; they are
        //! simply consecutive values that may have different underlying types.
        //! \see satcat5::cbor::MapReaderStatic
        //! \copydoc satcat5::cbor::CborReader
        class ListReader : public CborReader {
        public:
            //! Create a ListReader from an existing decoder context.
            //! The caller MUST have already entered the array/list in question.
            //! \see QCBORDecode_EnterArray (item-by-item parsing, next is list)
            //! \see QCBORDecode_EnterArrayFromMapN (list within an integer-keyed map)
            //! \see QCBORDecode_EnterArrayFromMapSZ (list within an string-keyed map)
            explicit constexpr ListReader(QCBORDecodeContext* decode)
                : CborReader(decode) {}

            //! Read the next scalar value from the List.
            //! @{
            satcat5::util::optional<QCBORItem> get_item() const;
            satcat5::util::optional<bool> get_bool() const;
            satcat5::util::optional<s64> get_int() const;
            satcat5::util::optional<u64> get_uint() const;
            satcat5::util::optional<double> get_double() const;
            //! @}

            //! Read a string from the List.
            //! \returns An io::ArrayRead containing the unterminated string in
            //! the working buffer - valid for the lifetime of this class.
            satcat5::util::optional<satcat5::io::ArrayRead> get_string() const;

            //! Read a byte sequence from the List.
            //! \returns An io::ArrayRead containing the bytes in the working
            //! buffer - valid for the lifetime of this class.
            satcat5::util::optional<satcat5::io::ArrayRead> get_bytes() const;

            //! Read a nested list from the List.
            //! Allows parsing of keys where the value is a list of items,
            //! which may have various type(s).  Once finished, the caller
            //! MUST then call CborReader::close_list.
            //! \returns Pointer to the decoder if found, otherwise null.
            //! (This pointer is suitable for creating another ListReader.)
            QCBORDecodeContext* open_list() const;

            //! Read a nested dictionary from the List.
            //! Allows parsing of keys where the value is another self-contained
            //! key/value dictionary.  Once finished, the caller MUST then call
            //! CborReader::close_map.
            //! \returns Pointer to the decoder if found, otherwise null.
            //! (This pointer is suitable for creating another MapReader.)
            QCBORDecodeContext* open_map() const;

            //! Read an array of boolean values from the List.
            //! This method always writes true/false values as single bytes
            //! (u8 per boolean value), regardless of platform `sizeof(bool)`.
            //!
            //! Template parameter is the type of elements to write to the
            //! array. Two interfaces are provided - one takes a pointer to an
            //! array and the other uses io::Writeable. All values are always
            //! written in CPU-native endian order.
            //!
            //! Example usage to directly populate an array:
            //! ```
            //! MapReaderStatic<const char*> r(&buf);
            //! s64 buffer[10];
            //! if (r.get_s64_array("int_arr_key", buffer, 10) < 0) {
            //!     return false; // Error!
            //! }
            //! s8 val = (s8) buffer[2]; // Example cast down to 8-bit type
            //! ```
            //!
            //! \param arr Destination array for read values.
            //! \param arr_len Length of `arr`.
            //! \param dst Writeable destination for array elements.
            //! \returns Number of elements written to `dst`.
            //! If there was not enough space in `dst`, this returns -1.
            //! If the read element was not of type `T`, this return -2.
            //! @{
            int get_bool_array(satcat5::io::Writeable& dst) const;
            int get_bool_array(u8* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(u8));
                return get_bool_array(dst);
            }
            //! @}

            //! Read an array of integer values from the List, always written as
            //! 64-bit length signed values (s64) to cover any size in the List.
            //! \copydetails get_bool_array()
            //! @{
            int get_s64_array(satcat5::io::Writeable& dst) const;
            int get_s64_array(s64* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(s64));
                return get_s64_array(dst);
            }
            //! @}

            //! Read an array of floating-point values from the List, always
            //! written as doubles to cover any precision in the List.
            //! \copydetails get_bool_array()
            //! @{
            int get_double_array(satcat5::io::Writeable& dst) const;
            int get_double_array(double* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(double));
                return get_double_array(dst);
            }
            //! @}

        protected:
            //! Opens a QCBOR Decode Context from an io::Readable.
            //! This constructor assumes the first element is an array and
            //! automatically enters that array.
            //! \copydoc satcat5::cbor::CborReader::CborReader()
            ListReader(
                satcat5::io::Readable* src,
                QCBORDecodeContext* decode,
                u8* buff, unsigned size);
        };

        //! Reads a series of key-value pairs from a CBOR Map.
        //!
        //! A common CBOR use case is to have a single Map at the top level with
        //! several keys of the same type (string, uint, etc.). This class
        //! assumes this CBOR payload structure and provides readers for these,
        //! templated by supported QCBOR key types. Most return their value
        //! wrapped by util::optional<> to indicate whether the value was found
        //! in the Map. This silently clears errors with the code
        //! `QCBOR_ERR_LABEL_NOT_FOUND` to allow trivial recovery from this
        //! class of decoder errors. Array reading functions can have more
        //! complex errors and therefore have their own return codes defined. A
        //! template parameter is provided for the key type to be written to the
        //! map - QCBOR currently only supports usage of string (`const char*`)
        //! and integer (`s64`) keys.
        //!
        //! \see satcat5::cbor::MapReaderStatic
        //! \copydoc satcat5::cbor::CborReader
        template <typename KEYTYPE = const char*>
        class MapReader : public CborReader {
        public:
            //! Create a MapReader from an existing decoder context.
            //! The caller MUST have already entered the map in question.
            //! \see QCBORDecode_EnterMap (item-by-item parsing, next is map)
            //! \see QCBORDecode_EnterMapFromMapN (map within an integer-keyed map)
            //! \see QCBORDecode_EnterMapFromMapSZ (map within a string-keyed map)
            explicit constexpr MapReader(QCBORDecodeContext* decode)
                : CborReader(decode) {}

            //! Read a scalar value from the Map.
            //! @{
            satcat5::util::optional<bool> get_bool(KEYTYPE key) const;
            satcat5::util::optional<s64> get_int(KEYTYPE key) const;
            satcat5::util::optional<u64> get_uint(KEYTYPE key) const;
            satcat5::util::optional<double> get_double(KEYTYPE key) const;
            //! @}

            //! Check if a key in the Map exists and is NULL.
            bool is_null(KEYTYPE key) const;

            //! Read a string from the Map.
            //! \returns An io::ArrayRead containing the unterminated string in
            //! the working buffer - valid for the lifetime of this class.
            satcat5::util::optional<satcat5::io::ArrayRead> get_string(KEYTYPE key) const;

            //! Read a byte sequence from the Map.
            //! \returns An io::ArrayRead containing the bytes in the working
            //! buffer - valid for the lifetime of this class.
            satcat5::util::optional<satcat5::io::ArrayRead> get_bytes(KEYTYPE key) const;

            //! Read a nested list from the Map. \see close_list.
            //! Allows parsing of keys where the value is a list of items,
            //! which may have different types.  Once finished, the caller
            //! must then call `CborReader::close_list`.
            //! \returns Pointer to the decoder if found, otherwise null.
            //! (This pointer is suitable for creating another ListReader.)
            QCBORDecodeContext* open_list(KEYTYPE key) const;

            //! Read a nested dictionary from the Map.
            //! Allows parsing of keys where the value is another self-contained
            //! key/value dictionary.  Once finished, the caller MUST then call
            //! `CborReader::close_map`.
            //! \returns Pointer to the decoder if found, otherwise null.
            //! (This pointer is suitable for creating another MapReader.)
            QCBORDecodeContext* open_map(KEYTYPE key) const;

            //! Read an array of boolean values from the Map, always
            //! written as u8 values regardless of platform `sizeof(bool)`.
            //!
            //! Template parameter is the type of elements to write to the
            //! array. Two interfaces are provided - one takes a pointer to an
            //! array and the other uses io::Writeable. All values are always
            //! written in CPU-native endian order.
            //!
            //! Example usage to directly populate an array:
            //! ```
            //! MapReaderStatic<const char*> r(&buf);
            //! s64 buffer[10];
            //! if (r.get_s64_array("int_arr_key", buffer, 10) < 0) {
            //!     return false; // Error!
            //! }
            //! s8 val = (s8) buffer[2]; // Example cast down to 8-bit type
            //! ```
            //!
            //! \param arr Destination array for read values.
            //! \param arr_len Length of `arr`.
            //! \param dst Writeable destination for array elements.
            //! \returns Number of elements written to `dst`.
            //! If there was not enough space in `dst`, this returns -1.
            //! If the read element was not of type `T`, this return -2.
            //! @{
            int get_bool_array(KEYTYPE key, satcat5::io::Writeable& dst) const;
            int get_bool_array(KEYTYPE key, u8* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(u8));
                return get_bool_array(key, dst);
            }
            //! @}

            //! Read an array of integer values from the Map, always written as
            //! 64-bit length signed values (s64) to cover any size in the Map.
            //! \copydetails get_bool_array()
            //! @{
            int get_s64_array(KEYTYPE key, satcat5::io::Writeable& dst) const;
            int get_s64_array(KEYTYPE key, s64* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(s64));
                return get_s64_array(key, dst);
            }
            //! @}

            //! Read an array of floating-point values from the Map, always
            //! written as doubles to cover any precision in the Map.
            //! \copydetails get_bool_array()
            //! @{
            int get_double_array(KEYTYPE key, satcat5::io::Writeable& dst) const;
            int get_double_array(KEYTYPE key, double* arr, unsigned arr_len) const {
                satcat5::io::ArrayWrite dst(arr, arr_len * sizeof(double));
                return get_double_array(key, dst);
            }
            //! @}

        protected:
            //! Opens a QCBOR Decode Context from an io::Readable.
            //! This constructor assumes the first element is a map (i.e.,
            //! a key/value dictionary) and automatically enters that map.
            //! \copydoc satcat5::cbor::CborReader::CborReader()
            MapReader(
                satcat5::io::Readable* src,
                QCBORDecodeContext* decode,
                u8* buff, unsigned size);
        };

        //! ListReader variant with a statically-allocated buffer.
        //! Most users should instantiate this instead of ListReader.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::cbor::ListReader
        template <unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class ListReaderStatic : public ListReader {
        public:
            //! Create this object and copy from a source io::Readable.
            //! \param src Readable source to decode.
            explicit ListReaderStatic(satcat5::io::Readable* src)
                : ListReader(src, &m_cbor, m_raw, SIZE) {}

        private:
            QCBORDecodeContext m_cbor;
            u8 m_raw[SIZE];
        };

        //! MapReader variant with a statically-allocated buffer.
        //! Most users should instantiate this instead of MapReader.
        //! Optional template parameter specifies buffer size.
        //! \copydoc satcat5::cbor::MapReader
        template <
            typename KEYTYPE = const char*,
            unsigned SIZE = SATCAT5_QCBOR_BUFFER>
        class MapReaderStatic : public MapReader<KEYTYPE> {
        public:
            //! Create this object and copy from a source io::Readable.
            //! \param src Readable source to decode.
            explicit MapReaderStatic(satcat5::io::Readable* src)
                : MapReader<KEYTYPE>(src, &m_cbor, m_raw, SIZE) {}

        private:
            QCBORDecodeContext m_cbor;
            u8 m_raw[SIZE];
        };

        //! Helper object for logging contents a QCBOR item.
        //! Output includes the key/value pair, if applicable.
        struct Logger {
            const QCBORItem& m_item;
            constexpr explicit Logger(const QCBORItem& item)
                : m_item(item) {}
            void log_to(satcat5::log::LogBuffer& wr) const;
        };
    }

    namespace io {
        //! Legacy alias for backwards compatibility.
        //! These are deprecated and may be removed in a later release.
        //!@{
        typedef satcat5::cbor::ListReader   CborListReader;
        typedef satcat5::cbor::ListWriter   CborListWriter;
        typedef satcat5::cbor::Logger       CborLogger;
        template <unsigned SIZE = SATCAT5_QCBOR_BUFFER>
            using CborListReaderStatic = satcat5::cbor::ListReaderStatic<SIZE>;
        template <unsigned SIZE = SATCAT5_QCBOR_BUFFER>
            using CborListWriterStatic = satcat5::cbor::ListWriterStatic<SIZE>;
        template <typename KEYTYPE = const char*>
            using CborMapReader = satcat5::cbor::MapReader<KEYTYPE>;
        template <typename KEYTYPE = const char*>
            using CborMapWriter = satcat5::cbor::MapReader<KEYTYPE>;
        template <
            typename KEYTYPE = const char*,
            unsigned SIZE = SATCAT5_QCBOR_BUFFER>
            using CborMapReaderStatic = satcat5::cbor::MapReaderStatic<KEYTYPE, SIZE>;
        template <
            typename KEYTYPE = const char*,
            unsigned SIZE = SATCAT5_QCBOR_BUFFER>
            using CborMapWriterStatic = satcat5::cbor::MapWriterStatic<KEYTYPE, SIZE>;
        //!@}
    }
}

#endif // SATCAT5_CBOR_ENABLE
