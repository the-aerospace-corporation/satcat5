//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_cbor.h>
#include <satcat5/log.h>

#if SATCAT5_CBOR_ENABLE

using satcat5::io::ArrayRead;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::util::optional;

// Required due to G++ bug: https://stackoverflow.com/questions/25594644
namespace satcat5 {
    namespace cbor {
        CborWriter::CborWriter(
                Writeable* dst, QCBOREncodeContext* encode,
                u8* buff, unsigned size, bool automap)
            : cbor(encode)
            , m_dst(dst)
            , m_encoded(nullptr)
            , m_encoded_len(0)
            , m_auto_close(automap ? QCBOR_TYPE_MAP : QCBOR_TYPE_NONE)
            , m_read(buff, 0)
        {
            // Initialize the encoder state, QCBOR saves buffer ptr and size.
            QCBOREncode_Init(cbor, {buff, size});
            if (automap) { QCBOREncode_OpenMap(cbor); } // Open a Map
        }

        bool CborWriter::close() {
            // Finish the CBOR object, validate, and write if successful.
            // Note: This only applies to automap, so it's always a Map.
            switch (m_auto_close) {
            case QCBOR_TYPE_MAP:    QCBOREncode_CloseMap(cbor);     break;
            case QCBOR_TYPE_ARRAY:  QCBOREncode_CloseArray(cbor);   break;
            }
            UsefulBufC encoded; // Should be const pointer to m_buff
            QCBORError error = QCBOREncode_Finish(cbor, &encoded);
            if (error != QCBOR_SUCCESS) { return false; }
            m_encoded = (const u8*) encoded.ptr;
            m_encoded_len = encoded.len;
            if (m_dst) { m_dst->write_bytes(encoded.len, encoded.ptr); }
            m_read.read_reset(encoded.len);
            return true;
        }

        UsefulBufC CborWriter::get_encoded() {
            if (!m_encoded) close();
            return { m_encoded, m_encoded_len };
        }

        Readable* CborWriter::get_buffer() {
            if (!m_encoded) close();
            return &m_read;
        }

        // Template specialization for key writing
        template <>
        void MapWriter<s64>::add_key(s64 key) const {
            QCBOREncode_AddInt64(cbor, key);
        }

        // Template specialization for key writing
        template <>
        void MapWriter<const char*>::add_key(const char* key) const {
            QCBOREncode_AddSZString(cbor, key);
        }

        // Write a bool array
        void ListWriter::add_array(u32 len, const bool* value) const {
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddBool(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        template <typename KEYTYPE>
        void MapWriter<KEYTYPE>::add_array(KEYTYPE key, u32 len, const bool* value) const {
            add_key(key);
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddBool(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        // Template for writing types handled by QCBOREncode_AddUInt64
        template <typename T>
        void CborWriter::add_unsigned_array(unsigned len, const T* value) const {
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddUInt64(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        // Template for writing types handled by QCBOREncode_AddInt64
        template <typename T>
        void CborWriter::add_signed_array(unsigned len, const T* value) const {
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddInt64(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        // Write a float array
        void ListWriter::add_array(u32 len, const float* value) const {
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddFloat(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        template <typename KEYTYPE>
        void MapWriter<KEYTYPE>::add_array(KEYTYPE key, u32 len, const float* value) const {
            add_key(key);
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddFloat(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        // Write a double array
        void ListWriter::add_array(u32 len, const double* value) const {
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddFloat(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        template <typename KEYTYPE>
        void MapWriter<KEYTYPE>::add_array(KEYTYPE key, u32 len, const double* value) const {
            add_key(key);
            QCBOREncode_OpenArray(cbor);
            for (unsigned a = 0; a < len; ++a)
                { QCBOREncode_AddDouble(cbor, value[a]); }
            QCBOREncode_CloseArray(cbor);
        }

        // Write a nested array/list
        QCBOREncodeContext* ListWriter::open_list() {
            QCBOREncode_OpenArray(cbor);
            return cbor;
        }

        template <>
        QCBOREncodeContext* MapWriter<s64>::open_list(s64 key) {
            QCBOREncode_OpenArrayInMapN(cbor, key);
            return cbor;
        }

        template <>
        QCBOREncodeContext* MapWriter<const char*>::open_list(const char* key) {
            QCBOREncode_OpenArrayInMap(cbor, key);
            return cbor;
        }

        // Write a nested dictionary
        QCBOREncodeContext* ListWriter::open_map() {
            QCBOREncode_OpenMap(cbor);
            return cbor;
        }

        template <>
        QCBOREncodeContext* MapWriter<s64>::open_map(s64 key) {
            QCBOREncode_OpenMapInMapN(cbor, key);
            return cbor;
        }

        template <>
        QCBOREncodeContext* MapWriter<const char*>::open_map(const char* key) {
            QCBOREncode_OpenMapInMap(cbor, key);
            return cbor;
        }

        // Open the Decoder from a Readable and copy into the qcbor buff
        CborReader::CborReader(
                Readable* src, QCBORDecodeContext* decode,
                u8* buff, unsigned size)
            : cbor(decode)
        {
            unsigned src_len = size;
            if (src) {
                src_len = src->get_read_ready();
                if (src_len > size || !src->read_bytes(src_len, buff))
                    { cbor->uLastError = QCBOR_ERR_BUFFER_TOO_SMALL; return; }
                src->read_finalize();
            }
            QCBORDecode_Init(cbor, {buff, src_len}, QCBOR_DECODE_MODE_NORMAL);
        }

        bool CborReader::copy_item(QCBOREncodeContext* dst) {
            // Consume the next item, noting before/after parsing position.
            // (For arrays and maps, this method consumes the entire structure.)
            QCBORItem item;
            size_t idx_dat = UsefulInputBuf_Tell(&cbor->InBuf);
            QCBORDecode_VGetNextConsume(cbor, &item);
            if (QCBORDecode_GetError(cbor) != QCBOR_SUCCESS) return false;
            size_t idx_end = UsefulInputBuf_Tell(&cbor->InBuf);
            // Convert offsets to start/end pointers.
            const u8* ptr_dat = (const u8*)cbor->InBuf.UB.ptr + idx_dat;
            const u8* ptr_end = (const u8*)cbor->InBuf.UB.ptr + idx_end;
            // If a label is present, consume that information first.
            // (QCBOR labels can only have integer or string types.)
            if (item.uLabelType == QCBOR_TYPE_INT64 ||
                item.uLabelType == QCBOR_TYPE_UINT64) {
                size_t len_key = peek_integer_len(ptr_dat);
                QCBOREncode_AddEncoded(dst, UsefulBufC{ptr_dat, len_key});
                ptr_dat += len_key;
            } else if (item.uLabelType == QCBOR_TYPE_TEXT_STRING) {
                const u8* ptr_mid = (const u8*)item.label.string.ptr + item.label.string.len;
                QCBOREncode_AddEncoded(dst, UsefulBufC{ptr_dat, size_t(ptr_mid - ptr_dat)});
                ptr_dat = ptr_mid;
            }
            // Copy remaining data as a single "item", potentially nested.
            QCBOREncode_AddEncoded(dst, UsefulBufC{ptr_dat, size_t(ptr_end - ptr_dat)});
            return true;
        }

        unsigned CborReader::copy_all(QCBOREncodeContext* dst) {
            unsigned count = 0;
            while (copy_item(dst)) {
                ++count;
            }
            return count;
        }

        unsigned CborReader::peek_integer_len(const u8* rdptr) const {
            // See IETF RFC8949, Appendix B: Jump Table for Initial Byte.
            // https://www.rfc-editor.org/rfc/rfc8949.html#name-jump-table-for-initial-byte
            const u8 tmp = (*rdptr) & 0xDF;     // Ignore sign bit
            if (tmp >= 0x1C) return 0;          // Not a valid integer
            if (tmp == 0x1B) return 9;          // Header + u64/s64
            if (tmp == 0x1A) return 5;          // Header + u32/s32
            if (tmp == 0x19) return 3;          // Header + u16/s16
            if (tmp == 0x18) return 2;          // Header + u8/s8
            return 1;                           // Header only
        }

        // Templates for detecting if a key was found in a map.
        //  * If the value was successfully decoded, return it.
        //  * If the value was not found or the requested type was incorrect,
        //    clear the error and return empty.
        //  * If another error was thrown, return empty and leave the error.
        bool key_found(QCBORDecodeContext* cbor) {
            switch (QCBORDecode_GetError(cbor)) {
                case QCBOR_SUCCESS:
                    return true;
                case QCBOR_ERR_LABEL_NOT_FOUND:
                case QCBOR_ERR_UNEXPECTED_TYPE:
                    QCBORDecode_GetAndResetError(cbor);
                    return false;
                default:
                    return false;
            }
        }

        template <typename T>
        inline optional<T> val_if_found(QCBORDecodeContext* cbor, T val) {
            return key_found(cbor) ? val : optional<T>();
        }

        // Constructor
        ListReader::ListReader(
                Readable* src, QCBORDecodeContext* decode,
                u8* buff, unsigned size)
            : CborReader(src, decode, buff, size)
        {
            QCBORDecode_EnterArray(cbor, &m_item);
        }

        // Constructor
        template <typename KEYTYPE>
        MapReader<KEYTYPE>::MapReader(
                Readable* src, QCBORDecodeContext* decode,
                u8* buff, unsigned size)
            : CborReader(src, decode, buff, size)
        {
            QCBORDecode_EnterMap(cbor, &m_item);
        }

        // Get a single item (polymorphic)
        satcat5::util::optional<QCBORItem> ListReader::get_item() const {
            QCBORItem item;
            QCBORDecode_GetNext(cbor, &item);
            return val_if_found(cbor, item);
        }

        // Get bool by key.
        optional<bool> ListReader::get_bool() const {
            bool val;
            QCBORDecode_GetBool(cbor, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<bool> MapReader<s64>::get_bool(s64 key) const {
            bool val;
            QCBORDecode_GetBoolInMapN(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<bool> MapReader<const char*>::get_bool(const char* key) const {
            bool val;
            QCBORDecode_GetBoolInMapSZ(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        // Get signed/unsigned ints by key.
        optional<s64> ListReader::get_int() const {
            s64 val;
            QCBORDecode_GetInt64(cbor, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<s64> MapReader<s64>::get_int(s64 key) const {
            s64 val;
            QCBORDecode_GetInt64InMapN(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<s64> MapReader<const char*>::get_int(const char* key) const {
            s64 val;
            QCBORDecode_GetInt64InMapSZ(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        optional<u64> ListReader::get_uint() const {
            u64 val;
            QCBORDecode_GetUInt64(cbor, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<u64> MapReader<s64>::get_uint(s64 key) const {
            u64 val;
            QCBORDecode_GetUInt64InMapN(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<u64> MapReader<const char*>::get_uint(const char* key) const {
            u64 val;
            QCBORDecode_GetUInt64InMapSZ(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        // Get floating point value by key, returned as a double.
        optional<double> ListReader::get_double() const {
            double val;
            QCBORDecode_GetDouble(cbor, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<double> MapReader<s64>::get_double(s64 key) const {
            double val;
            QCBORDecode_GetDoubleInMapN(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        template <>
        optional<double> MapReader<const char*>::get_double(const char* key) const {
            double val;
            QCBORDecode_GetDoubleInMapSZ(cbor, key, &val);
            return val_if_found(cbor, val);
        }

        // Check if a value exists and is NULL.
        template <>
        bool MapReader<s64>::is_null(s64 key) const {
            QCBORDecode_GetNullInMapN(cbor, key);
            return val_if_found(cbor, true).has_value();
        }

        template <>
        bool MapReader<const char*>::is_null(const char* key) const {
            QCBORDecode_GetNullInMapSZ(cbor, key);
            return val_if_found(cbor, true).has_value();
        }

        // Copy a sequence of bytes or a text string.
        optional<ArrayRead> ListReader::get_string() const {
            UsefulBufC buf;
            QCBORDecode_GetTextString(cbor, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        template <>
        optional<ArrayRead> MapReader<s64>::get_string(s64 key) const {
            UsefulBufC buf;
            QCBORDecode_GetTextStringInMapN(cbor, key, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        template <>
        optional<ArrayRead> MapReader<const char*>::get_string(const char* key) const {
            UsefulBufC buf;
            QCBORDecode_GetTextStringInMapSZ(cbor, key, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        optional<ArrayRead> ListReader::get_bytes() const {
            UsefulBufC buf;
            QCBORDecode_GetByteString(cbor, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        template <>
        optional<ArrayRead> MapReader<s64>::get_bytes(s64 key) const {
            UsefulBufC buf;
            QCBORDecode_GetByteStringInMapN(cbor, key, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        template <>
        optional<ArrayRead> MapReader<const char*>::get_bytes(const char* key) const {
            UsefulBufC buf;
            QCBORDecode_GetByteStringInMapSZ(cbor, key, &buf);
            return val_if_found(cbor, ArrayRead(buf.ptr, buf.len));
        }

        QCBORDecodeContext* ListReader::open_list() const {
            QCBORDecode_EnterArray(cbor, nullptr);
            return key_found(cbor) ? cbor : nullptr;
        }

        template <>
        QCBORDecodeContext* MapReader<s64>::open_list(s64 key) const {
            QCBORDecode_EnterArrayFromMapN(cbor, key);
            return key_found(cbor) ? cbor : nullptr;
        }

        template <>
        QCBORDecodeContext* MapReader<const char*>::open_list(const char* key) const {
            QCBORDecode_EnterArrayFromMapSZ(cbor, key);
            return key_found(cbor) ? cbor : nullptr;
        }

        QCBORDecodeContext* ListReader::open_map() const {
            QCBORDecode_EnterMap(cbor, nullptr);
            return key_found(cbor) ? cbor : nullptr;
        }

        template <>
        QCBORDecodeContext* MapReader<s64>::open_map(s64 key) const {
            QCBORDecode_EnterMapFromMapN(cbor, key);
            return key_found(cbor) ? cbor : nullptr;
        }

        template <>
        QCBORDecodeContext* MapReader<const char*>::open_map(const char* key) const {
            QCBORDecode_EnterMapFromMapSZ(cbor, key);
            return key_found(cbor) ? cbor : nullptr;
        }

        int ListReader::get_bool_array(Writeable& dst) const {
            QCBORDecode_EnterArray(cbor, nullptr);
            return get_array_internal(dst, QCBOR_TYPE_FALSE, 1);
        }

        template <>
        int MapReader<s64>::get_bool_array(s64 key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapN(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_FALSE, 1);
        }

        template <>
        int MapReader<const char*>::get_bool_array(const char* key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapSZ(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_FALSE, 1);
        }

        int ListReader::get_s64_array(Writeable& dst) const {
            QCBORDecode_EnterArray(cbor, nullptr);
            return get_array_internal(dst, QCBOR_TYPE_INT64, sizeof(u64));
        }

        template <>
        int MapReader<s64>::get_s64_array(s64 key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapN(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_INT64, sizeof(u64));
        }

        template <>
        int MapReader<const char*>::get_s64_array(const char* key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapSZ(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_INT64, sizeof(u64));
        }

        int ListReader::get_double_array(Writeable& dst) const {
            QCBORDecode_EnterArray(cbor, nullptr);
            return get_array_internal(dst, QCBOR_TYPE_FLOAT, sizeof(double));
        }

        template <>
        int MapReader<s64>::get_double_array(s64 key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapN(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_FLOAT, sizeof(double));
        }

        template <>
        int MapReader<const char*>::get_double_array(const char* key, Writeable& dst) const {
            QCBORDecode_EnterArrayFromMapSZ(cbor, key);
            return get_array_internal(dst, QCBOR_TYPE_FLOAT, sizeof(double));
        }

        int CborReader::get_array_internal(Writeable& dst, u8 qcbor_type, u8 type_size) const {
            // Check key lookup was successful and decoder is not errored.
            QCBORError err = QCBORDecode_GetError(cbor);
            if (err == QCBOR_ERR_LABEL_NOT_FOUND)
                { QCBORDecode_GetAndResetError(cbor); return ERR_NOT_FOUND; }
            if (err != QCBOR_SUCCESS) { return ERR_QCBOR_INT; } // Unknown.

            // Many QCBOR types are "paired" and have adjacent numbers. Ex:
            // Int: 2, UInt: 3, True: 20, False: 21, Float: 26, Double: 27
            // Since these decode to the same types, leverage this and bitmask
            // out the LSB for currently supported decoder types.
            // Note: This WILL be a problem for other future types (date).
            const u8 type_mask = 0xFE; // Paired types (true = 20, false = 21).
            qcbor_type &= type_mask;

            // In-order array traversal until it is out of items.
            QCBORItem item;
            QCBORDecode_GetNext(cbor, &item);
            int num_elems = 0;
            while (QCBORDecode_GetError(cbor) == QCBOR_SUCCESS &&
                item.uDataType != QCBOR_TYPE_NONE) {

                // Check for destination buffer and type errors.
                if (dst.get_write_space() < type_size) {
                    dst.write_abort();
                    QCBORDecode_ExitArray(cbor);
                    return ERR_OVERFLOW;
                }
                if ((item.uDataType & type_mask) != qcbor_type) {
                    dst.write_abort();
                    QCBORDecode_ExitArray(cbor);
                    return ERR_BAD_TYPE;
                }

                // Booleans - Write true/false indicated by type.
                // All others: Write blindly to the destination.
                if (qcbor_type == QCBOR_TYPE_FALSE) {
                    dst.write_u8(item.uDataType == QCBOR_TYPE_TRUE ? true : false);
                } else {
                    dst.write_bytes(type_size, &item.val);
                }

                // Advance to next element and log number of elements.
                num_elems++;
                QCBORDecode_GetNext(cbor, &item);
            }

            // If reached the end of the array - exit and reset error state.
            QCBORDecode_ExitArray(cbor);
            if (!dst.write_finalize()) { return ERR_OVERFLOW; }
            return (QCBORDecode_GetError(cbor) == QCBOR_SUCCESS) ?
                num_elems : ERR_QCBOR_INT;
        }

        // Array return types - these need to be in .cc due to template.
        const int CborReader::ERR_NOT_FOUND = -1;
        const int CborReader::ERR_OVERFLOW  = -2;
        const int CborReader::ERR_BAD_TYPE  = -3;
        const int CborReader::ERR_QCBOR_INT = -4;

        // Template instantiations for QCBOR's supported key types.
        template class MapWriter<s64>;
        template class MapWriter<const char*>;
        template class MapReader<s64>;
        template class MapReader<const char*>;
        template void CborWriter::add_unsigned_array<u8>(unsigned len, const u8* value) const;
        template void CborWriter::add_unsigned_array<u16>(unsigned len, const u16* value) const;
        template void CborWriter::add_unsigned_array<u32>(unsigned len, const u32* value) const;
        template void CborWriter::add_unsigned_array<u64>(unsigned len, const u64* value) const;
        template void CborWriter::add_signed_array<s8>(unsigned len, const s8* value) const;
        template void CborWriter::add_signed_array<s16>(unsigned len, const s16* value) const;
        template void CborWriter::add_signed_array<s32>(unsigned len, const s32* value) const;
        template void CborWriter::add_signed_array<s64>(unsigned len, const s64* value) const;

        void Logger::log_to(satcat5::log::LogBuffer& wr) const {
            // Always lead with prefix.
            wr.wr_str(" = ");

            // Print label if applicable.
            if (m_item.uLabelType == QCBOR_TYPE_INT64) {
                wr.wr_s64(m_item.label.int64);
                wr.wr_str(" / ");
            } else if (m_item.uLabelType == QCBOR_TYPE_BYTE_STRING
                    || m_item.uLabelType == QCBOR_TYPE_TEXT_STRING) {
                wr.wr_fix((const char*)m_item.label.string.ptr, m_item.label.string.len);
                wr.wr_str(" / ");
            }

            // Print primary value, if we understand the format.
            if (m_item.uDataType == QCBOR_TYPE_INT64) {
                wr.wr_s64(m_item.val.int64);
            } else if (m_item.uDataType == QCBOR_TYPE_UINT64) {
                wr.wr_d64(m_item.val.uint64);
            } else if (m_item.uDataType == QCBOR_TYPE_ARRAY) {
                wr.wr_str("[Array]");
            } else if (m_item.uDataType == QCBOR_TYPE_MAP) {
                wr.wr_str("[Map]");
            } else if (m_item.uDataType == QCBOR_TYPE_BYTE_STRING) {
                const u8* data = (const u8*)m_item.val.string.ptr;
                wr.wr_str("0x");
                for (unsigned a = 0 ; a < m_item.val.string.len ; ++a) {
                    wr.wr_h32(data[a], 2);
                }
            } else if (m_item.uDataType == QCBOR_TYPE_TEXT_STRING
                    || m_item.uDataType == QCBOR_TYPE_URI) {
                wr.wr_str("\"");
                wr.wr_fix((const char*)m_item.val.string.ptr, m_item.val.string.len);
                wr.wr_str("\"");
            } else if (m_item.uDataType == QCBOR_TYPE_FALSE) {
                wr.wr_str("False");
            } else if (m_item.uDataType == QCBOR_TYPE_TRUE) {
                wr.wr_str("True");
            } else if (m_item.uDataType == QCBOR_TYPE_NULL) {
                wr.wr_str("Null");
            } else {
                wr.wr_str("[Unknown]");
            }
        }
    } // namespace io
} // namespace satcat5

#endif // SATCAT5_CBOR_ENABLE
