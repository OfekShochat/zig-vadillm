//! This is heavily inspired by Cranelift's regalloc2.

const std = @import("std");

pub const RegClass = enum(u2) {
    int,
    float,
    vector,
};

pub const VirtualReg = struct {
    class: RegClass,
    index: u32,
};

pub const PhysicalReg = struct {
    class: RegClass,
    /// the unique encoding of a register. should fit into 7 bits.
    encoding: u7,
};

pub const Register = union(enum) {
    preg: PhysicalReg,
    vreg: VirtualReg,
};

pub const LocationConstraint = union(enum) {
    none,
    phys_reg,
    stack,

    /// fixed physical register
    fixed_reg: PhysicalReg,

    /// simulates instructions such as `add` that only have two operands but modify one:
    /// add v2 [late def], v1 [early use], v0 [early use, reuse-reg(0)]
    reuse: u6,

    pub fn asBytes(self: LocationConstraint) u8 {
        return switch (self) {
            .none => 0b0,
            .phys_reg => 0b1,
            .stack => 0b10,
            .fixed_reg => |reg| 0b10000000 | @as(u8, reg.encoding),
            .reuse => |idx| 0b01000000 | @as(u8, idx),
        };
    }
};

pub const AccessType = enum(u1) {
    def = 0,
    use = 1,
};

pub const OperandUseTiming = enum(u1) {
    early = 0,
    late = 1,
};

pub const Operand = struct {
    //! # An Operand
    //!
    //! +-------------+-------------+-------------+-----------+------------+
    //! | 24-31       | 23          | 22          | 20-21     | 0-19       |
    //! +-------------+-------------+-------------+-----------+------------+
    //! | constraints | access type | operand use | reg class | vreg index |
    //! +-------------+-------------+-------------+-----------+------------+
    //! # constraints' encoding:
    //! 00000000 => none
    //! 00000001 => phys_reg
    //! 00000010 => stack
    //! 1xxxxxxx => fixed_reg{xxxxxxx}
    //! 01xxxxxx => reuse{xxxxxx}
    bits: u32,

    pub fn init(vreg: VirtualReg, access_type: AccessType, constraints: LocationConstraint, operand_use: OperandUseTiming) Operand {
        std.debug.assert(vreg.index < (1 << 20));

        return Operand{
            .bits = vreg.index |
                (@as(u32, @intFromEnum(vreg.class)) << 20) |
                (@as(u32, @intFromEnum(operand_use)) << 22) |
                (@as(u32, @intFromEnum(access_type)) << 23) |
                (@as(u32, constraints.asBytes()) << 24),
        };
    }

    pub fn locationConstraints(self: Operand) LocationConstraint {
        const constraints = (self.bits >> 24) & 0xFF;

        if (constraints & 0b10000000 != 0) {
            return LocationConstraint{ .fixed_reg = .{
                .class = self.regclass(),
                .encoding = @intCast(constraints & 0b01111111),
            } };
        } else if (constraints & 0b01000000 != 0) {
            return LocationConstraint{ .reuse = @intCast(constraints & 0b00111111) };
        }

        return switch (constraints) {
            0 => .none,
            1 => .phys_reg,
            2 => .stack,
            else => @panic("invalid encoding"),
        };
    }

    pub fn regclass(self: Operand) RegClass {
        return @enumFromInt((self.bits >> 20) & 0b11);
    }

    pub fn operandUse(self: Operand) OperandUseTiming {
        return @enumFromInt((self.bits >> 22) & 0b1);
    }

    pub fn accessType(self: Operand) AccessType {
        return @enumFromInt((self.bits >> 23) & 0b1);
    }

    pub fn vregIndex(self: Operand) u32 {
        return self.bits & 0x3FF;
    }
};

pub const Stitch = struct {
    from: PhysicalReg,
    to: PhysicalReg,
};

test "regalloc.Operand" {
    // use constants and also make a test that should panic (index too high?)
    const operand = Operand.init(VirtualReg{ .class = .int, .index = 5 }, .use, .phys_reg, .early);
    try std.testing.expectEqual(@as(u32, 5), operand.vregIndex());
    try std.testing.expectEqual(LocationConstraint.phys_reg, operand.locationConstraints());
    try std.testing.expectEqual(AccessType.use, operand.accessType());
    try std.testing.expectEqual(RegClass.int, operand.regclass());
    try std.testing.expectEqual(OperandUseTiming.early, operand.operandUse());
}
