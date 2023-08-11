const std = @import("std");

const IndexedMap = @import("indexed_map.zig").IndexedMap;

/// An Egraph representation.
///
/// T: the enode type
/// C: the context type that will be present in every eclass
///
/// # Example
///
/// ```
/// const egraph = @import("egraph.zig");
/// const Egraph = egraph.Egraph;
/// ...
///
/// // has to be a union
/// pub const EgraphNode = union {
///     add: [2]egraph.Id,
///     sub: [2]egraph.Id,
///     constant: []const u8,
/// };
///
/// pub const EClassContext = struct {
///     orig_value: ?Index,
///     evaluated: ?Constant,
/// };
///
/// // ?*Node is given to get the (optional) origin node
/// var egraph = Egraph(EgraphNode, EClassContext).init(allocator);
///
/// var const1 = egraph.add_eclass(EgraphNode{.constant = &{1}});
/// var const2 = egraph.add_eclass(EgraphNode{.constant = &{2});
/// egraph.add_eclass(EgraphNode{.add = .{const1, const2}});
///
/// ...
/// ```
pub fn EGraph(comptime T: type, comptime C: type) type {
    return struct {
        nodes: IndexedMap(EClass),
        allocator: std.mem.Allocator,

        pub const EClass = struct {
            equivalences: std.ArrayListUnmanaged(T),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .nodes = IndexedMap(EClass),
                .allocator = allocator,
            };
        }
    };
}
