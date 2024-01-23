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
