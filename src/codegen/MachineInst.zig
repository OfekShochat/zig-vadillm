const std = @import("std");

const regalloc = @import("regalloc.zig");
const types = @import("../types.zig");

const MachineInst = @This();

vptr: *anyopaque,
vtable: VTable,

// constants

/// in bytes
worst_case_size: u32,

pub const VTable = struct {
    getAllocatableOperands: *const fn (self: *anyopaque, *std.ArrayList(regalloc.Operand)) std.mem.Allocator.Error!void,
    regTypeForClass: *const fn (regalloc.RegClass) types.Type,
    // fromBytes: *const fn (allocator: std.mem.Allocator, []const u8) error.ParseError!MachineInst,
    // deinit: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn getAllocatableOperands(self: MachineInst, operands_out: *std.ArrayList(regalloc.Operand)) !void {
    return self.vtable.getAllocatableOperands(self.vptr, operands_out);
}

pub fn regTypeForClass(self: MachineInst, class: regalloc.RegClass) types.Type {
    return self.vtable.regTypeForClass(class);
}

// pub fn getTerminatorDataOrNull(self: MachineInst, ) {

// }
