pub const Index = @import("ir.zig").Index;

pub const regalloc = @import("codegen/regalloc.zig");
pub const MachineInst = @import("codegen/MachineInst.zig");
pub const MachineFunction = @import("codegen/MachineFunction.zig");
pub const CodePoint = @import("codegen/CodePoint.zig");
pub const compile = @import("codegen/compile.zig").compile;
