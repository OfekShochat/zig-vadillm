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
/// var egraph = Egraph(EgraphNode, EClassContext).init(allocator);
///
/// var const1 = egraph.addEClass(EgraphNode{.constant = &{1}});
/// var const2 = egraph.addEClass(EgraphNode{.constant = &{2});
/// egraph.addEClass(EgraphNode{.add = .{const1, const2}});
///
/// ...
/// ```
pub fn EGraph(comptime T: type, comptime C: type) type {
    return struct {
        nodes: IndexedMap(EClass),
        allocator: std.mem.Allocator,

        comptime {
            if (!std.meta.trait.is(.Union)(T)) {
                @compileError("`T` has to be a union to qualify to be an ENode.");
            }
        }

        pub const EClass = struct {
            equivalences: std.ArrayListUnmanaged(T),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .nodes = IndexedMap(EClass){},
                .allocator = allocator,
            };
        }

        pub fn addEClass(self: *@This(), initial_enode: T) !void {
            _ = self;
            _ = initial_enode;
        }
    };
}

test "EGraph" {
    // has to be a union
    const EgraphNode = union {
        // add: [2]egraph.Id,
        // sub: [2]egraph.Id,
        // constant: []const u8,
    };

    const EClassContext = struct {
        orig_value: ?u32,
        evaluated: ?[]const u8,
    };

    var egraph = EGraph(EgraphNode, EClassContext).init(std.testing.allocator);
    _ = egraph;

    // var const1 = egraph.addEClass(EgraphNode{.constant = &.{1}});
    // var const2 = egraph.addEClass(EgraphNode{.constant = &.{2}});
    // egraph.addEClass(EgraphNode{.add = .{const1, const2}});
}
