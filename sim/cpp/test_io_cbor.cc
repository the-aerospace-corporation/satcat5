//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for satcat5::io::CborMapWriterStatic.
//

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/io_cbor.h>

using satcat5::io::CborMapWriterStatic;
using satcat5::io::PacketBufferHeap;

TEST_CASE("cbor_writer") {
    // Simulation infrastructure
    SATCAT5_TEST_START;
    PacketBufferHeap buf;

    // Test open/close without writing any data.
    // https://cbor.me/?diag={}
    SECTION("empty") {
        // Write and confirm an empty map is logged. 
        CborMapWriterStatic<> w(&buf);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8() == 0xA0); // map(0)
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing of all signed int types.
    // https://cbor.me/?diag={1:1,2:2,3:3,4:4}
    SECTION("uint") {
        CborMapWriterStatic<s64> w(&buf);
        w.add_item(1, (u8) 1);
        w.add_item(2, (u16) 2);
        w.add_item(3, (u32) 3);
        w.add_item(4, (u64) 4);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA4);
        CHECK(buf.read_u16()    == 0x0101);
        CHECK(buf.read_u16()    == 0x0202);
        CHECK(buf.read_u16()    == 0x0303);
        CHECK(buf.read_u16()    == 0x0404);
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing of all unsigned int types.
    // https://cbor.me/?diag={-1:-1,-2:-2,-3:-3,-4:-4}
    SECTION("int") {
        CborMapWriterStatic<s64> w(&buf);
        w.add_item(-1, (s8) -1);
        w.add_item(-2, (s16) -2);
        w.add_item(-3, (s32) -3);
        w.add_item(-4, (s64) -4);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA4);
        CHECK(buf.read_u16()    == 0x2020);
        CHECK(buf.read_u16()    == 0x2121);
        CHECK(buf.read_u16()    == 0x2222);
        CHECK(buf.read_u16()    == 0x2323);
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing of floats with IEEE754 bit width auto-reduction enabled.
    // https://cbor.me/?diag={"n":NaN,"s":1.0,"d":42.42}
    SECTION("float") {
        CborMapWriterStatic<const char*> w(&buf);
        w.add_item("n", NAN);
        w.add_item("s", 1.0f);
        w.add_item("d", 42.42);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA3);
        CHECK(buf.read_u16()    == 0x616E); // text(1) = "n"
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x7E00); // NaN
        CHECK(buf.read_u16()    == 0x6173); // text(1) = "s"
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x3C00); // 1.0
        CHECK(buf.read_u16()    == 0x6164); // text(1) = "d"
        CHECK(buf.read_u8()     == 0xFB); // primitive
        CHECK((buf.read_f64() - 42.42) < 1e-9); // Float near 42.42
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing of other core types.
    // https://cbor.me?diag={0:null,1:h'0102',2:"cbor",3:true}
    SECTION("other_types") {
        CborMapWriterStatic<s64> w(&buf);
        w.add_null(0);
        const u8 bytes[] = {0x01, 0x02};
        w.add_bytes(1, sizeof(bytes), bytes);
        w.add_string(2, "cbor");
        w.add_bool(3, true);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA4);
        CHECK(buf.read_u16()    == 0x00F6); // 0: null
        CHECK(buf.read_u32()    == 0x01420102); // 1: h'0102'
        CHECK(buf.read_u16()    == 0x0264); // 2: text(4)
        CHECK(buf.read_u32()    == 0x63626F72); // "cbor"
        CHECK(buf.read_u16()    == 0x03F5); // 3: true
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing boolean arrays.
    // https://cbor.me/?diag={0:[true,false]}
    SECTION("arrays_bool") {
        CborMapWriterStatic<s64> w(&buf);
        bool bool_vals[] = { true, false };
        w.add_array(0, 2, bool_vals);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA1);
        CHECK(buf.read_u32()    == 0x0082F5F4); // 0: [true, false]
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing signed integer arrays.
    // https://cbor.me/?diag={0:[-1,-2],1:[-1,-2],2:[-1,-2],3:[-1,-2]}
    SECTION("arrays_int") {
        CborMapWriterStatic<s64> w(&buf);
        s8 s8_vals[] = { -1, -2 };
        s16 s16_vals[] = { -1, -2 };
        s32 s32_vals[] = { -1, -2 };
        s64 s64_vals[] = { -1, -2 };
        w.add_array(0, 2, s8_vals);
        w.add_array(1, 2, s16_vals);
        w.add_array(2, 2, s32_vals);
        w.add_array(3, 2, s64_vals);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA4);
        CHECK(buf.read_u32()    == 0x00822021); // 0: [-1,-2]
        CHECK(buf.read_u32()    == 0x01822021); // 1: [-1,-2]
        CHECK(buf.read_u32()    == 0x02822021); // 2: [-1,-2]
        CHECK(buf.read_u32()    == 0x03822021); // 3: [-1,-2]
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing unsigned integer arrays.
    // https://cbor.me/?diag={0:[1,2],1:[1,2],2:[1,2],3:[1,2]}
    SECTION("arrays_uint") {
        CborMapWriterStatic<s64> w(&buf);
        u8 u8_vals[] = { 1, 2 };
        u16 u16_vals[] = { 1, 2 };
        u32 u32_vals[] = { 1, 2 };
        u64 u64_vals[] = { 1, 2 };
        w.add_array(0, 2, u8_vals);
        w.add_array(1, 2, u16_vals);
        w.add_array(2, 2, u32_vals);
        w.add_array(3, 2, u64_vals);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA4);
        CHECK(buf.read_u32()    == 0x00820102); // 0: [1,2]
        CHECK(buf.read_u32()    == 0x01820102); // 1: [1,2]
        CHECK(buf.read_u32()    == 0x02820102); // 2: [1,2]
        CHECK(buf.read_u32()    == 0x03820102); // 3: [1,2]
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing arrays of floating point values.
    // https://cbor.me/?diag={0:[1.0,2.0],1:[3.0,4.0]}
    SECTION("arrays_float") {
        CborMapWriterStatic<s64> w(&buf);
        float float_vals[] = { 1.0f, 2.0f };
        double double_vals[] = { 3.0, 4.0 };
        w.add_array(0, 2, float_vals);
        w.add_array(1, 2, double_vals);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8()     == 0xA2);
        CHECK(buf.read_u16()    == 0x0082); // 0: array(2)
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x3C00); // 1.0
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x4000); // 2.0
        CHECK(buf.read_u16()    == 0x0182); // 1: array(2)
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x4200); // 3.0
        CHECK(buf.read_u8()     == 0xF9); // primitive
        CHECK(buf.read_u16()    == 0x4400); // 4.0
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }
}
