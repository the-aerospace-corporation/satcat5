//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for "io_cbor.h":
//  * satcat5::cbor::ListReaderStatic
//  * satcat5::cbor::ListWriterStatic
//  * satcat5::cbor::MapReaderStatic
//  * satcat5::cbor::MapWriterStatic
//  * satcat5::cbor::Logger
//

#include <string>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/io_cbor.h>
#include <satcat5/utils.h>

using satcat5::cbor::CborReader;
using satcat5::cbor::ListReader;
using satcat5::cbor::ListWriter;
using satcat5::cbor::ListReaderStatic;
using satcat5::cbor::ListWriterStatic;
using satcat5::cbor::MapReader;
using satcat5::cbor::MapReaderStatic;
using satcat5::cbor::MapWriter;
using satcat5::cbor::MapWriterStatic;
using satcat5::io::ArrayRead;
using satcat5::io::ArrayWriteStatic;
using satcat5::io::PacketBufferHeap;
using satcat5::util::optional;

TEST_CASE("cbor_writer") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    PacketBufferHeap buf;

    // Test open/close without writing any data.
    // https://cbor.me/?diag={}
    SECTION("empty") {
        // Write and confirm an empty map is logged.
        MapWriterStatic<> w(&buf);
        CHECK(w.close_and_finalize());
        CHECK(buf.read_u8() == 0xA0); // map(0)
        CHECK(buf.get_read_ready() == 0);
        buf.read_finalize();
    }

    // Test writing of all signed int types.
    // https://cbor.me/?diag={1:1,2:2,3:3,4:4}
    SECTION("uint") {
        MapWriterStatic<s64> w(&buf);
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
        MapWriterStatic<s64> w(&buf);
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
        MapWriterStatic<const char*> w(&buf);
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
        MapWriterStatic<s64> w(&buf);
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
        MapWriterStatic<s64> w(&buf);
        const bool bool_vals[] = { true, false };
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
        MapWriterStatic<s64> w(&buf);
        const s8 s8_vals[] = { -1, -2 };
        const s16 s16_vals[] = { -1, -2 };
        const s32 s32_vals[] = { -1, -2 };
        const s64 s64_vals[] = { -1, -2 };
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
        MapWriterStatic<s64> w(&buf);
        const u8 u8_vals[] = { 1, 2 };
        const u16 u16_vals[] = { 1, 2 };
        const u32 u32_vals[] = { 1, 2 };
        const u64 u64_vals[] = { 1, 2 };
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
        MapWriterStatic<s64> w(&buf);
        const float float_vals[] = { 1.0f, 2.0f };
        const double double_vals[] = { 3.0, 4.0 };
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

TEST_CASE("cbor_reader") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Test error handling with a duplicate key.
    // https://cbor.me/?diag={1:true,1:1}
    SECTION("errors") {
        MapWriterStatic<s64> w;
        w.add_bool(1, true);
        w.add_item(1, (u64) 1);
        CHECK(w.close());
        MapReaderStatic<s64> r(w.get_buffer());
        CHECK(r.ok());
        CHECK_FALSE(r.get_bool(1));
        CHECK_FALSE(r.ok());
        CHECK(r.get_error() == QCBOR_ERR_DUPLICATE_LABEL);
    }

    // Test error handling if provided decode buffer is too small.
    SECTION("small_buff") {
        MapWriterStatic<s64> w;
        w.add_bool(1, true);
        CHECK(w.close());
        MapReaderStatic<s64, 2> r(w.get_buffer());
        CHECK_FALSE(r.ok());
        CHECK(r.get_error() == QCBOR_ERR_BUFFER_TOO_SMALL);
    }

    // Test lookup for basic types with int keys.
    // https://cbor.me/?diag={1:true,2:2,3:+3,4:4.0,5:null}
    SECTION("basic_int") {
        MapWriterStatic<s64> w;
        w.add_bool(1, true);
        w.add_item(2, (u64) 2);
        w.add_item(3, (s64) 3);
        w.add_item(4, 4.0);
        w.add_null(5);
        CHECK(w.close());
        MapReaderStatic<s64> r(w.get_buffer());
        CHECK(r.ok());
        CHECK_FALSE(r.get_bool(0));
        CHECK(r.get_bool(1));
        CHECK(r.get_bool(1).value()     == true);
        CHECK(r.get_uint(2));
        CHECK(r.get_uint(2).value()     == 2);
        CHECK(r.get_int(3));
        CHECK(r.get_int(3).value()      == +3);
        CHECK(r.get_double(4));
        CHECK(r.get_double(4).value()   == 4.0);
        CHECK(r.is_null(5));
        CHECK_FALSE(r.is_null(6));
    }

    // Test lookup for basic types with string keys.
    // https://cbor.me/?diag={"1":true,"2":2,"3":+3,"4":4.0,"5":null}
    SECTION("basic_str") {
        MapWriterStatic<const char*> w;
        w.add_bool("1", true);
        w.add_item("2", (u64) 2);
        w.add_item("3", (s64) 3);
        w.add_item("4", 4.0);
        w.add_null("5");
        CHECK(w.close());
        MapReaderStatic<const char*> r(w.get_buffer());
        CHECK(r.ok());
        CHECK_FALSE(r.get_bool("0"));
        CHECK(r.get_bool("1"));
        CHECK(r.get_bool("1").value()     == true);
        CHECK(r.get_uint("2"));
        CHECK(r.get_uint("2").value()     == 2);
        CHECK(r.get_int("3"));
        CHECK(r.get_int("3").value()      == +3);
        CHECK(r.get_double("4"));
        CHECK(r.get_double("4").value()   == 4.0);
        CHECK(r.is_null("5"));
        CHECK_FALSE(r.is_null("6"));
    }

    // Test lookup for string types with int keys.
    // https://cbor.me/?diag={1:"one",2:h'0102'}
    SECTION("strings_int") {
        MapWriterStatic<s64> w;
        const u8 bytes[] = {0x01, 0x02};
        w.add_string(1, "one");
        w.add_bytes(2, bytes, sizeof(bytes));
        CHECK(w.close());
        MapReaderStatic<s64> r(w.get_buffer());
        CHECK(r.ok());
        optional<ArrayRead> r1 = r.get_string(1);
        CHECK(r1);
        satcat5::io::ArrayRead r1r = r1.value();
        CHECK(satcat5::test::read(&r1r, "one"));
        optional<ArrayRead> r2 = r.get_bytes(2);
        CHECK(r2);
        satcat5::io::ArrayRead r2r = r2.value();
        CHECK(satcat5::test::read(&r2r, sizeof(bytes), bytes));
        optional<ArrayRead> r3 = r.get_bytes(3);
        CHECK_FALSE(r3);
    }

    // Test lookup for string types with string keys.
    // https://cbor.me/?diag={"1":"one","2":h'0102'}
    SECTION("strings_str") {
        MapWriterStatic<const char*> w;
        const u8 bytes[] = {0x01, 0x02};
        w.add_string("1", "one");
        w.add_bytes("2", sizeof(bytes), bytes);
        CHECK(w.close());
        MapReaderStatic<const char*> r(w.get_buffer());
        CHECK(r.ok());
        optional<ArrayRead> r1 = r.get_string("1");
        CHECK(r1);
        satcat5::io::ArrayRead r1r = r1.value();
        CHECK(satcat5::test::read(&r1r, "one"));
        optional<ArrayRead> r2 = r.get_bytes("2");
        CHECK(r2);
        satcat5::io::ArrayRead r2r = r2.value();
        CHECK(satcat5::test::read(&r2r, sizeof(bytes), bytes));
        optional<ArrayRead> r3 = r.get_bytes("3");
        CHECK_FALSE(r3);
    }

    // Test lookup for array types with int keys.
    // https://cbor.me/?diag={0:[true,false],1:[1,2],2:[3.0,4.0]}
    SECTION("arrays_int") {
        MapWriterStatic<s64> w;
        const bool bool_vals[] = { true, false };
        const u64 u64_vals[] = { 1, 2 };
        const double double_vals[] = { 3.0, 4.0 };
        w.add_array(0, 2, bool_vals);
        w.add_array(1, 2, u64_vals);
        w.add_array(2, 2, double_vals);
        CHECK(w.close());
        MapReaderStatic<s64> r(w.get_buffer());
        CHECK(r.ok());
        PacketBufferHeap dst;
        int r1 = r.get_bool_array(0, dst);
        CHECK(r1 == 2);
        CHECK(satcat5::test::read(&dst, sizeof(bool_vals), (u8*) bool_vals));
        CHECK(dst.get_read_ready() == 0);
        int r2 = r.get_s64_array(1, dst);
        CHECK(r2 == 2);
        CHECK(satcat5::test::read(&dst, sizeof(u64_vals), (u8*) u64_vals));
        CHECK(dst.get_read_ready() == 0);
        int r3 = r.get_double_array(2, dst);
        CHECK(r3 == 2);
        CHECK(satcat5::test::read(&dst,
            sizeof(double_vals), (u8*) double_vals));
        CHECK(dst.get_read_ready() == 0);
    }

    // Test lookup for array types with string keys.
    // https://cbor.me/?diag={"0":[true,false],"1":[1,2],"2":[3.0,4.0]}
    SECTION("arrays_str") {
        MapWriterStatic<const char*> w;
        const bool bool_vals[] = { true, false };
        const u64 u64_vals[] = { 1, 2 };
        const double double_vals[] = { 3.0, 4.0 };
        w.add_array("0", 2, bool_vals);
        w.add_array("1", 2, u64_vals);
        w.add_array("2", 2, double_vals);
        CHECK(w.close());
        MapReaderStatic<const char*> r(w.get_buffer());
        CHECK(r.ok());
        u8 bool_dst[2];
        int r1 = r.get_bool_array("0", bool_dst, 2);
        CHECK(r1 == 2);
        CHECK((bool) bool_dst[0] == bool_vals[0]);
        CHECK((bool) bool_dst[1] == bool_vals[1]);
        u64 u64_dst[2];
        int r2 = r.get_s64_array("1", (s64*) u64_dst, 2);
        CHECK(r2 == 2);
        CHECK(u64_dst[0] == u64_vals[0]);
        CHECK(u64_dst[1] == u64_vals[1]);
        double double_dst[2];
        int r3 = r.get_double_array("2", double_dst, 2);
        CHECK(r3 == 2);
        CHECK(double_dst[0] == double_vals[0]);
        CHECK(double_dst[1] == double_vals[1]);
    }

    // Test array error handling.
    // https://cbor.me/?diag={0:[true,false]}
    SECTION("arrays_err") {
        MapWriterStatic<s64> w;
        const bool bool_vals[] = { true, false };
        w.add_array(0, 2, bool_vals);
        CHECK(w.close());
        MapReaderStatic<s64> r(w.get_buffer());
        CHECK(r.ok());
        PacketBufferHeap dst;
        int f1 = r.get_s64_array(0, dst);
        CHECK(f1 == CborReader::ERR_BAD_TYPE);
        ArrayWriteStatic<1> tiny_arr;
        int f2 = r.get_bool_array(0, tiny_arr);
        CHECK(f2 == CborReader::ERR_OVERFLOW);
        int f3 = r.get_bool_array(1, dst);
        CHECK(f3 == CborReader::ERR_NOT_FOUND);
        int r1 = r.get_bool_array(0, dst); // Should work now.
        CHECK(r1 == 2);
        CHECK(satcat5::test::read(&dst, sizeof(bool_vals), (u8*) bool_vals));
        CHECK(dst.get_read_ready() == 0);
    }

    // Test list-within-map with integer keys.
    SECTION("list_int") {
        const s8 int_vals[] = { 1, 1, 2, 3, 5, 8 };
        MapWriterStatic<s64> w;
        ListWriter wi1(w.open_list(1234));
        wi1.add_item(s32(123));
        wi1.add_bool(true);
        wi1.add_string("Test123");
        wi1.add_array(sizeof(int_vals), int_vals);
        wi1.close_list();   // Confirm open/close from different objects.
        w.add_item(2345, s32(-234));
        CHECK(w.close());
        MapReaderStatic<s64> outer(w.get_buffer());
        CHECK(outer.ok());
        CHECK(outer.get_int(2345).value() == -234);
        // Scan through the list using generic "get_item".
        ListReader inner1(outer.open_list(1234));
        QCBORItem i1 = inner1.get_item().value();
        QCBORItem i2 = inner1.get_item().value();
        QCBORItem i3 = inner1.get_item().value();
        QCBORItem i4 = inner1.get_item().value();
        inner1.close_list();
        CHECK(i1.uDataType == QCBOR_TYPE_INT64);
        CHECK(i2.uDataType == QCBOR_TYPE_TRUE);
        CHECK(i3.uDataType == QCBOR_TYPE_TEXT_STRING);
        CHECK(i4.uDataType == QCBOR_TYPE_ARRAY);
        // Scan through the same list using specific types.
        ListReader inner2(outer.open_list(1234));
        CHECK(inner2.get_uint().value() == 123);
        CHECK(inner2.get_bool().value());
        ArrayRead tmp_rd = inner2.get_string().value();
        CHECK(satcat5::test::read(&tmp_rd, "Test123"));
        s64 tmp_int[6];
        CHECK(inner2.get_s64_array(tmp_int, 6) == 6);
        CHECK(tmp_int[0] == 1);
        CHECK(tmp_int[1] == 1);
        CHECK(tmp_int[2] == 2);
        CHECK(tmp_int[3] == 3);
        CHECK(tmp_int[4] == 5);
        CHECK(tmp_int[5] == 8);
        inner2.close_list();
        // Read another value from the outer map, to
        // confirm we haven't mangled the QCBOR state.
        CHECK(outer.get_int(2345).value() == -234);
    }

    // Test list-within-map with string keys.
    SECTION("list_str") {
        MapWriterStatic<const char*> w;
        ListWriter wi(w.open_list("1234"));
        const bool bool_vals[] = { true, false };
        const float float_vals[] = { 42.0f, 43.0f, 44.0f };
        const double double_vals[] = { 45.0, 46.0, 47.0, 48.0 };
        const u8 byte_vals[] = { 51, 52, 53 };
        wi.add_array(2, bool_vals);
        wi.add_array(3, float_vals);
        wi.add_array(4, double_vals);
        ListWriter wi2(wi.open_list());
        wi2.add_item(s8(49));
        wi2.add_item(s8(50));
        wi2.close_list();
        wi.add_bytes(byte_vals, 3);
        wi.close_list();
        w.add_item("2345", s32(-234));
        CHECK(w.close());
        MapReaderStatic<const char*> outer(w.get_buffer());
        CHECK(outer.ok());
        ListReader inner(outer.open_list("1234"));
        u8 rcvd_bool[2];
        double rcvd_float[3];
        CHECK(inner.get_bool_array(rcvd_bool, 2));
        CHECK(inner.get_double_array(rcvd_float, 3));
        // Note: Read "double_vals" as a list instead of an array.
        ListReader inner2(inner.open_list());
        CHECK(inner2.get_double().value() == 45.0);
        CHECK(inner2.get_double().value() == 46.0);
        CHECK(inner2.get_double().value() == 47.0);
        inner2.close_list();    // Skip over 4th value
        ListReader inner3(inner.open_list());
        CHECK(inner3.get_int().value() == 49);
        CHECK(inner3.get_int().value() == 50);
        inner3.close_list();
        ArrayRead rcvd_bytes = inner.get_bytes().value();
        CHECK(rcvd_bytes.read_u8() == 51);
        CHECK(rcvd_bytes.read_u8() == 52);
        CHECK(rcvd_bytes.read_u8() == 53);
        inner.close_list();
        CHECK(outer.get_int("2345").value() == -234);
    }

    // Test creation of a top-level list.
    SECTION("list_top") {
        ListWriterStatic<> wr;
        wr.add_item(s16(123));
        wr.add_bool(true);
        wr.add_bool(false);
        wr.add_string("Test123");
        u8* wr_buf = (u8*) wr.get_encoded().ptr;
        CHECK(wr_buf[0] == 0x84); // array(4)
        ListReaderStatic<> rd(wr.get_buffer());
        CHECK(rd.ok());
        CHECK(rd.get_int().value() == 123);
        CHECK(rd.get_bool().value());
        CHECK_FALSE(rd.get_bool().value());
        ArrayRead tmp = rd.get_string().value();
        CHECK(satcat5::test::read(&tmp, "Test123"));
    }

    // Test map-within-map with integer keys.
    SECTION("nesting_int") {
        // Form the nested data structure.
        MapWriterStatic<s64> w;
        w.open_map(1234);
        w.add_item(42, s32(123));
        w.add_string(43, "Test123");
        w.close_map();
        w.add_item(2345, s32(-234));
        w.add_item(5, s32(345));
        CHECK(w.close());
        // Parse the nested data structure.
        MapReaderStatic<s64> outer(w.get_buffer());
        CHECK(outer.ok());
        CHECK(outer.get_int(5));
        CHECK(outer.get_int(5).value() == 345);
        CHECK(outer.get_int(2345).value() == -234);
        MapReader<s64> inner(outer.open_map(1234));
        CHECK(inner.ok());
        CHECK(inner.get_int(42));
        CHECK(inner.get_int(42).value() == 123);
        CHECK(inner.get_string(43));
        ArrayRead r43 = inner.get_string(43).value();
        CHECK(satcat5::test::read(&r43, "Test123"));
        inner.close_map();
        CHECK(outer.get_int(2345).value() == -234);
        // Make an item-for-item copy.
        MapReaderStatic<s64> r2(w.get_buffer());
        MapWriterStatic<s64> w2;
        r2.copy_all(w2.cbor);
        CHECK(satcat5::test::read_equal(w.get_buffer(), w2.get_buffer()));
    }

    // Test map-within-map with string keys.
    SECTION("nesting_str") {
        // Form the nested data structure.
        MapWriterStatic<const char*> w;
        w.open_map("1234");
        w.add_item("42", s32(123));
        w.add_string("43", "Test123");
        w.close_map();
        w.add_item("2345", s32(-234));
        CHECK(w.close());
        MapReaderStatic<const char*> outer(w.get_buffer());
        CHECK(outer.ok());
        CHECK(outer.get_int("2345").value() == -234);
        // Parse the nested data structure.
        MapReader<const char*> inner(outer.open_map("1234"));
        CHECK(inner.ok());
        CHECK(inner.get_int("42"));
        CHECK(inner.get_int("42").value() == 123);
        CHECK(inner.get_string("43"));
        ArrayRead r43 = inner.get_string("43").value();
        CHECK(satcat5::test::read(&r43, "Test123"));
        inner.close_map();
        CHECK(outer.get_int("2345").value() == -234);
        // Make an item-for-item copy.
        MapReaderStatic<const char*> r2(w.get_buffer());
        MapWriterStatic<const char*> w2;
        r2.copy_all(w2.cbor);
        CHECK(satcat5::test::read_equal(w.get_buffer(), w2.get_buffer()));
    }

    // List in a map in a list in a map.
    SECTION("inception") {
        MapWriterStatic<s64>    wr0;
        ListWriter              wr1(wr0.open_list(1));
        MapWriter<s64>          wr2(wr1.open_map());
        ListWriter              wr3(wr2.open_list(3));
        wr3.add_string("We need to go deeper.");
        wr2.close_list();
        wr1.close_map();
        wr0.close_list();
        MapReaderStatic<s64>    rd0(wr0.get_buffer());
        ListReader              rd1(rd0.open_list(1));
        MapReader<s64>          rd2(rd1.open_map());
        ListReader              rd3(rd2.open_list(3));
        ArrayRead str = rd3.get_string().value();
        rd2.close_list();
        rd1.close_map();
        rd0.close_list();
        CHECK(satcat5::test::read(&str, "We need to go deeper."));
    }

    // Test handling of two parsers sharing a working buffer.
    // https://cbor.me/?diag={1:true,2:2,3:+3,4:4.0}
    SECTION("shared_buffer") {
        MapWriterStatic<s64> w;
        w.add_bool(1, true);
        w.add_item(2, (u64) 2);
        w.add_item(3, (s64) 3);
        w.add_item(4, 4.0);
        MapReaderStatic<s64> r1(w.get_buffer());
        MapReader<s64> r2(r1.cbor);
        CHECK(r2.get_bool(1).value()     == true);
        CHECK(r1.get_double(4).value()   == 4.0);
        CHECK(r2.get_uint(2).value()     == 2);
        CHECK(r1.get_int(3).value()      == +3);
        CHECK(r2.get_int(3).value()      == +3);
        CHECK(r1.get_uint(2).value()     == 2);
        CHECK(r2.get_double(4).value()   == 4.0);
        CHECK(r1.get_bool(1).value()     == true);
    }
}

static void log_cbor_keys(const UsefulBufC& msg) {
    QCBORDecodeContext cbor;
    QCBORItem item;
    QCBORDecode_Init(&cbor, msg, QCBOR_DECODE_MODE_NORMAL);
    QCBORDecode_EnterMap(&cbor, nullptr);
    while (QCBORDecode_GetNext(&cbor, &item) == QCBOR_SUCCESS) {
        satcat5::io::CborLogger item_fmt(item);
        satcat5::log::Log(satcat5::log::INFO, "Test").write_obj(item_fmt);
    }
}

TEST_CASE("cbor_logger") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    log.suppress("Test = ");

    // Test various value formats with integer keys.
    SECTION("int_keys") {
        const u8 TEST_BYTES[] = {0xDE, 0xAD, 0xBE, 0xEF};
        MapWriterStatic<s64> w;
        w.add_bool(1, true);
        w.add_item(2, u64(9876543210987654321ull));
        w.add_bytes(3, TEST_BYTES, sizeof(TEST_BYTES));
        w.add_null(4);
        log_cbor_keys(w.get_encoded());
    }

    // Test various value formats with string keys.
    SECTION("str_keys") {
        MapWriterStatic<const char*> w;
        w.add_bool("test_bool", false);
        w.add_item("test_s16", s16(1234));
        w.add_string("test_str", "Lorem ipsum");
        w.add_item("test_float", 3.14159f);
        log_cbor_keys(w.get_encoded());
    }
}
