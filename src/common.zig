const IndexedMap = @import("indexed_map.zig").IndexedMap;
const Value = @import("function.zig").Value;

pub const Index = u32;

pub const Immediate64 = union(enum) {
    float: f64,
    int: i64,
};

pub const ValuePool = IndexedMap(Value);

pub const Constant = []const u8;
