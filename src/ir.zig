pub const Function = @import("function.zig").Function;
pub const Block = @import("function.zig").Block;
pub const Signature = @import("function.zig").Signature;
pub const Value = @import("function.zig").Value;
pub const Module = @import("Module.zig");

const IndexedMap = @import("indexed_map.zig").IndexedMap;

pub const Index = u32;

pub const Immediate64 = union(enum) {
    float: f64,
    int: i64,
};

pub const ValuePool = IndexedMap(Index, Value);

pub const Constant = []const u8;
