const std = @import("std");

const Index = @import("ir.zig").Index;

pub const BinOp = struct { lhs: Index, rhs: Index };

pub const BlockCall = struct {
    block: Index,
    args: std.ArrayListUnmanaged(Index),
};

pub const CondCode = enum {
    /// `==`
    Equal,
    /// `!=`
    NotEqual,
    /// signed `<`
    SignedLessThan,
    /// signed `>=`
    SignedGreaterThanOrEqual,
    /// signed `>`
    SignedGreaterThan,
    /// signed `<=`
    SignedLessThanOrEqual,
    /// unsigned `<`
    UnsignedLessThan,
    /// unsigned `>=`
    UnsignedGreaterThanOrEqual,
    /// unsigned `>`
    UnsignedGreaterThan,
    /// unsigned `<=`
    UnsignedLessThanOrEqual,
};

pub const Instruction = union(enum) {
    add: BinOp,
    sub: BinOp,
    mul: BinOp,
    shl: BinOp,
    shr: BinOp,

    imm64: i64,
    imm32: i32,

    icmp: struct { cond_code: CondCode, lhs: Index, rhs: Index },

    alloca: struct { size: usize, alignment: usize },

    call: struct {
        func: Index,
        args: std.ArrayListUnmanaged(Index),
    },

    brif: struct {
        cond: Index,
        cond_true: BlockCall,
        cond_false: BlockCall,
    },

    jump: BlockCall,

    ret: ?Index,
};
