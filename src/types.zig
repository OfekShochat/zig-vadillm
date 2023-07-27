const std = @import("std");

const SIZE_MASK = 0b111;
const INVALID_MASK = 0xFFFF;
const IS_INT_MASK = 1 << 3;
const IS_FLOAT_MASK = 1 << 4;
const IS_PTR_MASK = 1 << 5;
const IS_VECTOR_MASK = 1 << 6;
const LANES_MASK = 0b111 << 7;

/// Type; can you guess what this is?
/// Encoded in a bitset (0x0 is void, 0xFFFF is invalid):
/// +---------------+-----+-------+-----+--------+-------------+
/// | 0-2           | 3   | 4     | 5   | 6      | 7-9         |
/// +---------------+-----+-------+-----+--------+-------------+
/// | log2(bitsize) | int | float | ptr | vector | log2(lanes) |
/// +---------------+-----+-------+-----+--------+-------------+
pub const Type = struct {
    val: u16,

    pub fn from(comptime T: type) Type {
        var val: u16 = 0;

        const type_info = @typeInfo(T);
        switch (type_info) {
            .Float => |float| {
                comptime if (!std.math.isPowerOfTwo(float.bits)) {
                    @compileError("float bits have to be powers of two.");
                };
                val |= IS_FLOAT_MASK;
                val |= @ctz(float.bits);
            },
            .Int => |int| {
                comptime if (!std.math.isPowerOfTwo(int.bits)) {
                    @compileError("int bits have to be powers of two.");
                };
                val |= IS_INT_MASK;
                val |= @ctz(int.bits);
            },
            .Vector => |vec| {
                comptime if (!std.math.isPowerOfTwo(vec.len)) {
                    @compileError("vector lengths have to be powers of two.");
                };
                val |= Type.from(vec.child).val;
                val |= IS_VECTOR_MASK;

                const size: u16 = @ctz(@as(u16, vec.len));
                val |= size << 7;
            },
            .Pointer => val |= IS_PTR_MASK,
            else => {}, // void is 0x0 anyway
        }

        return Type{ .val = val };
    }

    pub fn invalid_type() Type {
        return Type{ .val = INVALID_MASK };
    }

    pub fn log2_bits(self: Type) u3 {
        return @truncate(self.val & SIZE_MASK);
    }

    pub fn bits(self: Type) u16 {
        return @as(u16, 1) << self.log2_bits();
    }

    pub fn bytes(self: Type) u16 {
        return (self.bits() + 7) / 8;
    }

    pub fn log2_lanes(self: Type) u3 {
        return @intCast((self.val & LANES_MASK) >> 7);
    }

    pub fn lanes(self: Type) u16 {
        return @as(u16, 1) << self.log2_lanes();
    }

    pub fn is_int(self: Type) bool {
        return self.val & IS_INT_MASK != 0;
    }

    pub fn is_void(self: Type) bool {
        return self.val == 0;
    }

    pub fn is_float(self: Type) bool {
        return self.val & IS_FLOAT_MASK != 0;
    }

    pub fn is_ptr(self: Type) bool {
        return self.val & IS_PTR_MASK != 0;
    }

    pub fn is_vector(self: Type) bool {
        return self.val & IS_VECTOR_MASK != 0;
    }

    pub fn is_valid(self: Type) bool {
        return self.val != INVALID_MASK;
    }
};

pub const PTR = Type.from(*i8);
pub const I8 = Type.from(i8);
pub const I16 = Type.from(i16);
pub const I32 = Type.from(i32);
pub const I64 = Type.from(i64);

pub const F32 = Type.from(f32);
pub const F64 = Type.from(f64);

pub const VOID = Type.from(void);

test "types" {
    const iv = Type.from(@Vector(4, i32));
    try std.testing.expect(iv.is_valid());
    try std.testing.expect(iv.is_vector());
    try std.testing.expectEqual(@as(u16, 4), iv.lanes());
    try std.testing.expectEqual(@as(u16, 32), iv.bits());
    try std.testing.expectEqual(@as(u16, 4), iv.bytes());
    try std.testing.expect(!iv.is_ptr());
    try std.testing.expect(!iv.is_float());

    const f = F64;
    try std.testing.expect(f.is_valid());
    try std.testing.expect(f.is_float());
    try std.testing.expect(!f.is_vector());
    try std.testing.expect(!f.is_ptr());
    try std.testing.expectEqual(@as(u16, 64), f.bits());
    try std.testing.expectEqual(@as(u16, 8), f.bytes());

    const v = VOID;
    try std.testing.expect(v.is_valid());
    try std.testing.expect(v.is_void());
    try std.testing.expect(!v.is_vector());
    try std.testing.expect(!v.is_ptr());
    try std.testing.expect(!v.is_ptr());
    try std.testing.expectEqual(@as(u16, 1), v.bits());
    try std.testing.expectEqual(@as(u16, 1), v.bytes());
}
