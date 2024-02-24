const std = @import("std");

const PhysicalReg = @import("regalloc.zig").PhysicalReg;
const RegClass = @import("regalloc.zig").RegClass;

const Abi = @This();

pub const CallConv = struct {
    /// Callee saved registers are saved at the prologue.
    callee_saved: []const PhysicalReg,

    /// The rest are on the stack
    params: []const PhysicalReg,

    /// Are stack params in reverse?
    stack_params_reverse: bool = true,
};

// TODO: why optional here?
int_pregs: ?[]const PhysicalReg,
float_pregs: ?[]const PhysicalReg,
vector_pregs: ?[]const PhysicalReg,
call_conv: CallConv,

pub fn getPregsByRegClass(self: Abi, class: RegClass) ?[]const PhysicalReg {
    return switch (class) {
        .int => self.int_pregs,
        .float => self.float_pregs,
        .vector => self.vector_pregs,
    };
}

pub fn getAllPregs(self: Abi, allocator: std.mem.Allocator) ![]const PhysicalReg {
    var all_pregs = std.ArrayList(PhysicalReg).init(allocator);

    if (self.int_pregs) |pregs| {
        try all_pregs.appendSlice(pregs);
    }

    if (self.float_pregs) |pregs| {
        try all_pregs.appendSlice(pregs);
    }

    if (self.vector_pregs) |pregs| {
        try all_pregs.appendSlice(pregs);
    }

    return all_pregs.toOwnedSlice();
}
