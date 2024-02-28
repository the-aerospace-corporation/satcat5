//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_checksum.h>

using satcat5::eth::ChecksumTx;
using satcat5::eth::ChecksumRx;
using satcat5::eth::SlipCodec;

// Set default table size.
#ifndef SATCAT5_CRC_TABLE_BITS
#define SATCAT5_CRC_TABLE_BITS 8
#endif

// Ethernet CRC32:
//  * Set initial state = 0xFFFFFFFF
//  * For each byte or nybble, incremental update using lookup table
//  * Invert output and write in little-endian order
static const u32 CRC_INIT = 0xFFFFFFFFu;

// Table for nybble-by-nybble CRC updates (64 bytes)
#if SATCAT5_CRC_TABLE_BITS == 4
static const u32 CRC_TABLE[16] = {
    0x00000000u, 0x1DB71064u, 0x3B6E20C8u, 0x26D930ACu,
    0x76DC4190u, 0x6B6B51F4u, 0x4DB26158u, 0x5005713Cu,
    0xEDB88320u, 0xF00F9344u, 0xD6D6A3E8u, 0xCB61B38Cu,
    0x9B64C2B0u, 0x86D3D2D4u, 0xA00AE278u, 0xBDBDF21Cu,
};

inline void crc_update(u32& crc, u8 next)
{
    u32 next1 = next >> 0;                  // First nybble
    u32 next2 = next >> 4;                  // Second nybble
    u8 index1 = (crc ^ next1) & 0x0Ful;     // Table index
    crc = (crc >> 4) ^ CRC_TABLE[index1];   // XOR with table
    u8 index2 = (crc ^ next2) & 0x0Ful;     // Table index
    crc = (crc >> 4) ^ CRC_TABLE[index2];   // XOR with table
}
#endif  // SATCAT5_CRC_TABLE_BITS == 4

// Table for byte-by-byte CRC updates (1 kiB)
#if SATCAT5_CRC_TABLE_BITS == 8
static const u32 CRC_TABLE[256] = {
    0x00000000u, 0x77073096u, 0xEE0E612Cu, 0x990951BAu,
    0x076DC419u, 0x706AF48Fu, 0xE963A535u, 0x9E6495A3u,
    0x0EDB8832u, 0x79DCB8A4u, 0xE0D5E91Eu, 0x97D2D988u,
    0x09B64C2Bu, 0x7EB17CBDu, 0xE7B82D07u, 0x90BF1D91u,
    0x1DB71064u, 0x6AB020F2u, 0xF3B97148u, 0x84BE41DEu,
    0x1ADAD47Du, 0x6DDDE4EBu, 0xF4D4B551u, 0x83D385C7u,
    0x136C9856u, 0x646BA8C0u, 0xFD62F97Au, 0x8A65C9ECu,
    0x14015C4Fu, 0x63066CD9u, 0xFA0F3D63u, 0x8D080DF5u,
    0x3B6E20C8u, 0x4C69105Eu, 0xD56041E4u, 0xA2677172u,
    0x3C03E4D1u, 0x4B04D447u, 0xD20D85FDu, 0xA50AB56Bu,
    0x35B5A8FAu, 0x42B2986Cu, 0xDBBBC9D6u, 0xACBCF940u,
    0x32D86CE3u, 0x45DF5C75u, 0xDCD60DCFu, 0xABD13D59u,
    0x26D930ACu, 0x51DE003Au, 0xC8D75180u, 0xBFD06116u,
    0x21B4F4B5u, 0x56B3C423u, 0xCFBA9599u, 0xB8BDA50Fu,
    0x2802B89Eu, 0x5F058808u, 0xC60CD9B2u, 0xB10BE924u,
    0x2F6F7C87u, 0x58684C11u, 0xC1611DABu, 0xB6662D3Du,
    0x76DC4190u, 0x01DB7106u, 0x98D220BCu, 0xEFD5102Au,
    0x71B18589u, 0x06B6B51Fu, 0x9FBFE4A5u, 0xE8B8D433u,
    0x7807C9A2u, 0x0F00F934u, 0x9609A88Eu, 0xE10E9818u,
    0x7F6A0DBBu, 0x086D3D2Du, 0x91646C97u, 0xE6635C01u,
    0x6B6B51F4u, 0x1C6C6162u, 0x856530D8u, 0xF262004Eu,
    0x6C0695EDu, 0x1B01A57Bu, 0x8208F4C1u, 0xF50FC457u,
    0x65B0D9C6u, 0x12B7E950u, 0x8BBEB8EAu, 0xFCB9887Cu,
    0x62DD1DDFu, 0x15DA2D49u, 0x8CD37CF3u, 0xFBD44C65u,
    0x4DB26158u, 0x3AB551CEu, 0xA3BC0074u, 0xD4BB30E2u,
    0x4ADFA541u, 0x3DD895D7u, 0xA4D1C46Du, 0xD3D6F4FBu,
    0x4369E96Au, 0x346ED9FCu, 0xAD678846u, 0xDA60B8D0u,
    0x44042D73u, 0x33031DE5u, 0xAA0A4C5Fu, 0xDD0D7CC9u,
    0x5005713Cu, 0x270241AAu, 0xBE0B1010u, 0xC90C2086u,
    0x5768B525u, 0x206F85B3u, 0xB966D409u, 0xCE61E49Fu,
    0x5EDEF90Eu, 0x29D9C998u, 0xB0D09822u, 0xC7D7A8B4u,
    0x59B33D17u, 0x2EB40D81u, 0xB7BD5C3Bu, 0xC0BA6CADu,
    0xEDB88320u, 0x9ABFB3B6u, 0x03B6E20Cu, 0x74B1D29Au,
    0xEAD54739u, 0x9DD277AFu, 0x04DB2615u, 0x73DC1683u,
    0xE3630B12u, 0x94643B84u, 0x0D6D6A3Eu, 0x7A6A5AA8u,
    0xE40ECF0Bu, 0x9309FF9Du, 0x0A00AE27u, 0x7D079EB1u,
    0xF00F9344u, 0x8708A3D2u, 0x1E01F268u, 0x6906C2FEu,
    0xF762575Du, 0x806567CBu, 0x196C3671u, 0x6E6B06E7u,
    0xFED41B76u, 0x89D32BE0u, 0x10DA7A5Au, 0x67DD4ACCu,
    0xF9B9DF6Fu, 0x8EBEEFF9u, 0x17B7BE43u, 0x60B08ED5u,
    0xD6D6A3E8u, 0xA1D1937Eu, 0x38D8C2C4u, 0x4FDFF252u,
    0xD1BB67F1u, 0xA6BC5767u, 0x3FB506DDu, 0x48B2364Bu,
    0xD80D2BDAu, 0xAF0A1B4Cu, 0x36034AF6u, 0x41047A60u,
    0xDF60EFC3u, 0xA867DF55u, 0x316E8EEFu, 0x4669BE79u,
    0xCB61B38Cu, 0xBC66831Au, 0x256FD2A0u, 0x5268E236u,
    0xCC0C7795u, 0xBB0B4703u, 0x220216B9u, 0x5505262Fu,
    0xC5BA3BBEu, 0xB2BD0B28u, 0x2BB45A92u, 0x5CB36A04u,
    0xC2D7FFA7u, 0xB5D0CF31u, 0x2CD99E8Bu, 0x5BDEAE1Du,
    0x9B64C2B0u, 0xEC63F226u, 0x756AA39Cu, 0x026D930Au,
    0x9C0906A9u, 0xEB0E363Fu, 0x72076785u, 0x05005713u,
    0x95BF4A82u, 0xE2B87A14u, 0x7BB12BAEu, 0x0CB61B38u,
    0x92D28E9Bu, 0xE5D5BE0Du, 0x7CDCEFB7u, 0x0BDBDF21u,
    0x86D3D2D4u, 0xF1D4E242u, 0x68DDB3F8u, 0x1FDA836Eu,
    0x81BE16CDu, 0xF6B9265Bu, 0x6FB077E1u, 0x18B74777u,
    0x88085AE6u, 0xFF0F6A70u, 0x66063BCAu, 0x11010B5Cu,
    0x8F659EFFu, 0xF862AE69u, 0x616BFFD3u, 0x166CCF45u,
    0xA00AE278u, 0xD70DD2EEu, 0x4E048354u, 0x3903B3C2u,
    0xA7672661u, 0xD06016F7u, 0x4969474Du, 0x3E6E77DBu,
    0xAED16A4Au, 0xD9D65ADCu, 0x40DF0B66u, 0x37D83BF0u,
    0xA9BCAE53u, 0xDEBB9EC5u, 0x47B2CF7Fu, 0x30B5FFE9u,
    0xBDBDF21Cu, 0xCABAC28Au, 0x53B39330u, 0x24B4A3A6u,
    0xBAD03605u, 0xCDD70693u, 0x54DE5729u, 0x23D967BFu,
    0xB3667A2Eu, 0xC4614AB8u, 0x5D681B02u, 0x2A6F2B94u,
    0xB40BBE37u, 0xC30C8EA1u, 0x5A05DF1Bu, 0x2D02EF8Du
};

inline void crc_update(u32& crc, u8 next)
{
    u8 index = (crc ^ (u32)next) & 0xFFul;  // Table index
    crc = (crc >> 8) ^ CRC_TABLE[index];    // XOR with table
}
#endif  // SATCAT5_CRC_TABLE_BITS == 8

inline u32 crc_format(u32 crc)
{
    return __builtin_bswap32(~crc);
}

u32 satcat5::eth::crc32(unsigned nbytes, const void* data)
{
    // Byte-by-byte CRC32 calculation.
    const u8* data8 = (const u8*)data;
    u32 crc = CRC_INIT;
    for (unsigned a = 0 ; a < nbytes ; ++a)
        crc_update(crc, data8[a]);
    // Format result per Ethernet specification.
    return crc_format(crc);
}

u32 satcat5::eth::crc32(satcat5::io::Readable* src)
{
    // Byte-by-byte CRC32 calculation.
    u32 crc = CRC_INIT;
    while (src->get_read_ready())
        crc_update(crc, src->read_u8());
    src->read_finalize();
    // Format result per Ethernet specification.
    return crc_format(crc);
}

ChecksumTx::ChecksumTx(satcat5::io::Writeable* dst)
    : satcat5::io::ChecksumTx<u32,4>(dst, CRC_INIT)
{
    // Nothing else to initialize
}

bool ChecksumTx::write_finalize()
{
    // Format and append CRC32 per Ethernet specification.
    m_dst->write_u32(crc_format(m_chk));
    return chk_finalize() && m_dst->write_finalize();
}

void ChecksumTx::write_next(u8 data)
{
    crc_update(m_chk, data);            // Update internal state
    m_dst->write_u8(data);              // Forward new data
}

ChecksumRx::ChecksumRx(satcat5::io::Writeable* dst)
    : satcat5::io::ChecksumRx<u32,4>(dst, CRC_INIT)
{
    // Nothing else to initialize
}

bool ChecksumRx::write_finalize()
{
    return sreg_match(crc_format(m_chk));
}

void ChecksumRx::write_next(u8 data)
{
    if (sreg_push(data)) crc_update(m_chk, data);
}

SlipCodec::SlipCodec(
        satcat5::io::Writeable* dst,
        satcat5::io::Readable* src)
    : satcat5::io::ReadableRedirect(&m_rx)  // Reads pull from Rx buffer
    , satcat5::eth::ChecksumTx(&m_tx_slip)  // CRC append (self) -> SLIP encoder
    , m_tx_slip(dst)                        // Connect SLIP encoder -> output
    , m_rx_copy(src, &m_rx_slip)            // Connect source -> SLIP decoder
    , m_rx_slip(&m_rx_fcs)                  // Connect SLIP decoder -> FCS check
    , m_rx_fcs(&m_rx)                       // Connect FCS check -> Rx buffer
    , m_rx(m_rxbuff, SATCAT5_SLIP_BUFFSIZE, SATCAT5_SLIP_PACKETS)
{
    // Nothing else to initialize
}
