const std = @import("std");

const PhysicalReg = @import("regalloc.zig").PhysicalReg;
const RegClass = @import("regalloc.zig").RegClass;

const Abi = @This();

int_pregs: ?[]const PhysicalReg,
float_pregs: ?[]const PhysicalReg,
vector_pregs: ?[]const PhysicalReg,

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
