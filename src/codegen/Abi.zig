const PhysicalReg = @import("regalloc.zig").PhysicalReg;

const Abi = @This();

pregs: []const PhysicalReg,
