const std = @import("std");
const regalloc = @import("codegen/regalloc.zig");

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

    pub fn format(
        value: Type,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (value.is_float()) {
            try writer.print("f{}", .{value.size_bits()});
        } else if (value.is_int()) {
            try writer.print("i{}", .{value.size_bits()});
        } else if (value.is_ptr()) {
            try writer.print("ptr", .{});
        } else if (value.is_void()) {
            try writer.print("void", .{});
        }

        if (value.is_vector()) {
            try writer.print("x{}", .{value.lanes()});
        }
    }

    pub fn containingRegisterSize(self: Type) regalloc.RegisterSize {
        return @enumFromInt(@ctz(self.sizeBytes()));
    }

    pub fn invalidType() Type {
        return Type{ .val = INVALID_MASK };
    }

    pub fn log2Bits(self: Type) u3 {
        return @truncate(self.val & SIZE_MASK);
    }

    pub fn sizeBits(self: Type) u16 {
        return @as(u16, 1) << self.log2Bits();
    }

    pub fn sizeBytes(self: Type) u16 {
        return (self.sizeBits() + 7) / 8;
    }

    pub fn log2Lanes(self: Type) u3 {
        return @intCast((self.val & LANES_MASK) >> 7);
    }

    pub fn lanes(self: Type) u16 {
        return @as(u16, 1) << self.log2Lanes();
    }

    pub fn isInt(self: Type) bool {
        return self.val & (IS_INT_MASK | IS_PTR_MASK) != 0;
    }

    pub fn isVoid(self: Type) bool {
        return self.val == 0;
    }

    pub fn isFloat(self: Type) bool {
        return self.val & IS_FLOAT_MASK != 0;
    }

    pub fn isPtr(self: Type) bool {
        return self.val & IS_PTR_MASK != 0;
    }

    pub fn isVector(self: Type) bool {
        return self.val & IS_VECTOR_MASK != 0;
    }

    pub fn isValid(self: Type) bool {
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
    try std.testing.expect(iv.isValid());
    try std.testing.expect(iv.isVector());
    try std.testing.expectEqual(@as(u16, 4), iv.lanes());
    try std.testing.expectEqual(@as(u16, 32), iv.sizeBits());
    try std.testing.expectEqual(@as(u16, 4), iv.sizeBytes());
    try std.testing.expect(!iv.isPtr());
    try std.testing.expect(!iv.isFloat());

    const f = F64;
    try std.testing.expect(f.isValid());
    try std.testing.expect(f.isFloat());
    try std.testing.expect(!f.isVector());
    try std.testing.expect(!f.isPtr());
    try std.testing.expectEqual(@as(u16, 64), f.sizeBits());
    try std.testing.expectEqual(@as(u16, 8), f.sizeBytes());

    const v = VOID;
    try std.testing.expect(v.isValid());
    try std.testing.expect(v.isVoid());
    try std.testing.expect(!v.isVector());
    try std.testing.expect(!v.isPtr());
    try std.testing.expectEqual(@as(u16, 1), v.sizeBits());
    try std.testing.expectEqual(@as(u16, 1), v.sizeBytes());
}
