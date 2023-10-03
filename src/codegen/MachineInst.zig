const std = @import("std");

const regalloc = @import("regalloc.zig");
const types = @import("../types.zig");

const MachineInst = @This();

const InstructionType = enum(u32) {
    Assign,
    BinOp,
    Branch,
    Return
};

vptr: *anyopaque,
vtable: VTable,

// constants

/// in bytes
worst_case_size: u32,

pub const VTable = struct {
    getAllocatableOperands: *const fn (self: *anyopaque, *std.ArrayList(regalloc.Operand)) std.mem.Allocator.Error!void,
    regTypeForClass: *const fn (regalloc.RegClass) types.Type,
    getBranches: *const fn (self: *anyopaque) *std.ArrayListUnmanaged,
    getInstType: *const fn (self: *anyopaque) InstructionType
};

pub fn getAllocatableOperands(self: MachineInst, operands_out: *std.ArrayList(regalloc.Operand)) !void {
    return self.vtable.getAllocatableOperands(self.vptr, operands_out);
}

pub fn regTypeForClass(self: MachineInst, class: regalloc.RegClass) types.Type {
    return self.vtable.regTypeForClass(class);
}

pub fn getBranches(self: MachineInst) *std.ArrayListUnmanaged {
    return self.vtable.getBranches();
}

pub fn getInstType(self: MachineInst) InstructionType {
    return self.vtable
}