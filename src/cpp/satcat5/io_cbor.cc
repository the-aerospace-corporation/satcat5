//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_cbor.h>

#if SATCAT5_CBOR_ENABLE

using satcat5::io::CborWriter;
using satcat5::io::CborMapWriter;
using satcat5::io::Writeable;

CborWriter::CborWriter(Writeable* dst, u8* buff, unsigned size, bool automap)
    : cbor(&m_cbor_alloc)
    , m_dst(dst)
    , m_encoded(nullptr)
    , m_encoded_len(0)
    , m_automap(automap)
{
    // Initialize the encoder state, QCBOR saves buffer location and size.
    QCBOREncode_Init(cbor, {buff, size});
    if (m_automap) { QCBOREncode_OpenMap(cbor); } // Open a Map
}

bool CborWriter::close()
{
    // Finish the CBOR object, validate, and write if successful.
    if (m_automap) { QCBOREncode_CloseMap(cbor); }
    UsefulBufC encoded; // Should be const pointer to m_buff
    QCBORError error = QCBOREncode_Finish(cbor, &encoded);
    if (error != QCBOR_SUCCESS) { return false; }
    m_encoded = (const u8*) encoded.ptr;
    m_encoded_len = encoded.len;
    if (m_dst) { m_dst->write_bytes(encoded.len, encoded.ptr); }
    return true;
}

// Template specialization for key writing
template <>
inline void CborMapWriter<s64>::add_key(s64 key) const {
    QCBOREncode_AddInt64(cbor, key);
}

// Template specialization for key writing
template <>
inline void CborMapWriter<const char*>::add_key(const char* key) const {
    QCBOREncode_AddSZString(cbor, key);
}

// Write a bool array
template <typename KEYTYPE>
void CborMapWriter<KEYTYPE>::add_array(
    KEYTYPE key, u32 len, const bool* value) const {
    add_key(key);
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0; a < len; ++a)
        { QCBOREncode_AddBool(cbor, value[a]); }
    QCBOREncode_CloseArray(cbor);
}

// Template for writing types handled by QCBOREncode_AddUInt64
template <typename KEYTYPE>
template <typename T>
void CborMapWriter<KEYTYPE>::add_unsigned_array(
    unsigned len, const T* value) const {
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0; a < len; ++a)
        { QCBOREncode_AddUInt64(cbor, value[a]); }
    QCBOREncode_CloseArray(cbor);
}

// Template for writing types handled by QCBOREncode_AddInt64
template <typename KEYTYPE>
template <typename T>
void CborMapWriter<KEYTYPE>::add_signed_array(
    unsigned len, const T* value) const {
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0; a < len; ++a)
        { QCBOREncode_AddInt64(cbor, value[a]); }
    QCBOREncode_CloseArray(cbor);
}

// Write a float array
template <typename KEYTYPE>
void CborMapWriter<KEYTYPE>::add_array(
    KEYTYPE key, u32 len, const float* value) const {
    add_key(key);
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0; a < len; ++a)
        { QCBOREncode_AddFloat(cbor, value[a]); }
    QCBOREncode_CloseArray(cbor);
}

// Write a double array
template <typename KEYTYPE>
void CborMapWriter<KEYTYPE>::add_array(
    KEYTYPE key, u32 len, const double* value) const {
    add_key(key);
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0; a < len; ++a)
        { QCBOREncode_AddDouble(cbor, value[a]); }
    QCBOREncode_CloseArray(cbor);
}

// Template instantiations for QCBOR's supported key types (s64, const char*).
template class CborMapWriter<s64>;
template class CborMapWriter<const char*>;

#endif // SATCAT5_CBOR_ENABLE
