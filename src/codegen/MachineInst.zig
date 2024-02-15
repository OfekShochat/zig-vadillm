const std = @import("std");

const regalloc = @import("regalloc.zig");
const Buffer = @import("Buffer.zig");
// const types = @import("../types.zig");

const MachineInst = @This();

vptr: *anyopaque,
vtable: VTable,

pub const VTable = struct {
    getAllocatableOperands: *const fn (self: *anyopaque, *std.ArrayList(regalloc.Operand)) std.mem.Allocator.Error!void,
    // TODO:
    // regTypeForClass: *const fn (regalloc.RegClass) types.Type,
    emit: *const fn (self: *anyopaque, *Buffer, *std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.LiveRange)) anyerror!void,
    getStackDelta: *const fn (self: *anyopaque) isize,
    // fromBytes: *const fn (allocator: std.mem.Allocator, []const u8) error.ParseError!MachineInst,
    // deinit: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn getAllocatableOperands(self: MachineInst, operands_out: *std.ArrayList(regalloc.Operand)) !void {
    return self.vtable.getAllocatableOperands(self.vptr, operands_out);
}

pub fn getStackDelta(self: MachineInst) isize {
    return self.vtable.getStackDelta(self.vptr);
}

pub fn emit(
    self: MachineInst,
    buffer: *Buffer,
    mapping: *std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.LiveRange),
) !void {
    try self.vtable.emit(self.vptr, buffer, mapping);
}

// TODO:
// pub fn regTypeForClass(self: MachineInst, class: regalloc.RegClass) types.Type {
//     return self.vtable.regTypeForClass(class);
// }
