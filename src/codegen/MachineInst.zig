const std = @import("std");

const regalloc = @import("regalloc.zig");
// const types = @import("../types.zig");

const Abi = @import("Abi.zig");

const MachineInst = @This();

vptr: *const anyopaque,
vtable: VTable,

pub const VTable = struct {
    getAllocatableOperands: *const fn (self: *const anyopaque, Abi, *std.ArrayList(regalloc.Operand)) std.mem.Allocator.Error!void,
    // TODO:
    // regTypeForClass: *const fn (regalloc.RegClass) types.Type,
    emit: *const fn (self: *const anyopaque, *std.io.AnyWriter, *const std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation)) anyerror!void,
    getStackDelta: *const fn (self: *const anyopaque) isize,
    clobbers: *const fn (self: *const anyopaque, preg: regalloc.PhysicalReg) bool,
    // fromBytes: *const fn (allocator: std.mem.Allocator, []const u8) error.ParseError!MachineInst,
    // deinit: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn getAllocatableOperands(self: MachineInst, abi: Abi, operands_out: *std.ArrayList(regalloc.Operand)) !void {
    return self.vtable.getAllocatableOperands(self.vptr, abi, operands_out);
}

pub fn getStackDelta(self: MachineInst) isize {
    return self.vtable.getStackDelta(self.vptr);
}

pub fn emit(
    self: MachineInst,
    buffer: *std.io.AnyWriter,
    mapping: *const std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation),
) !void {
    try self.vtable.emit(self.vptr, buffer, mapping);
}

pub fn clobbers(self: MachineInst, preg: regalloc.PhysicalReg) bool {
    return self.vtable.clobbers(self.vptr, preg);
}

// TODO:
// pub fn regTypeForClass(self: MachineInst, class: regalloc.RegClass) types.Type {
//     return self.vtable.regTypeForClass(class);
// }
