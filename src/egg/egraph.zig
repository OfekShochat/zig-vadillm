const std = @import("std");
const IndexedMap = @import("../indexed_map.zig").IndexedMap;

const egg = @import("../egg.zig");
const UnionFind = egg.UnionFind;
const Id = egg.Id;

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
pub fn EGraph(comptime E: type, comptime C: type) type {
    return struct {
        union_find: UnionFind,
        nodes: IndexedMap(Id, EClass),
        memo: std.AutoHashMap(EClass, Id),
        // pending: std.ArrayList()
        allocator: std.mem.Allocator,

        // comptime {
        //     if (!std.meta.trait.is(.Union)(T)) {
        //         @compileError("`T` has to be a union to qualify to be an ENode.");
        //     }
        // }

        const PendingEntry = struct {
            id: Id,
            eclass: EClass,
        };

        pub const EClass = struct {
            id: Id,
            parents: std.ArrayListUnmanaged(Id) = .{},
            nodes: std.ArrayListUnmanaged(E),
            ctx: C,
        };

        //     pub const ENode = struct {
        //         op: O,
        //         children:
        // };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .nodes = IndexedMap(Id, EClass){},
                .allocator = allocator,
            };
        }

        pub fn addEnode(self: *@This(), enode: E) Id {
            const canon_enode = self.canonicalize(enode);
            if (self.memo.contains(canon_enode)) {
                return self.memo.get(canon_enode);
            }

            return 0;
            // const id = self.addEclass();
        }

        // fn addEclass(self: *@This(), enode: ENode) Id {
        //     const id = self.union_find.makeSet();
        //
        //     var nodes = std.ArrayListUnmanaged(ENode){};
        //     try nodes.append(self.allocator, enode);
        //
        //     const eclass = EClass {
        //         .id = id,
        //         .nodes = nodes,
        //         .ctx = .{}
        //     };
        // }

        // this is a horrible name. updateParentsToRepresentatives?
        pub fn canonicalize(self: *@This(), enode: E) Id {
            // for (enode.)
            self.union_find.find(enode);
        }
    };
}

test "EGraph" {
    // has to be a union
    // const EgraphNode = union {
    //     // add: [2]egraph.Id,
    //     // sub: [2]egraph.Id,
    //     // constant: []const u8,
    // };
    //
    // const EClassContext = struct {
    //     orig_value: ?u32,
    //     evaluated: ?[]const u8,
    // };

    //
    // var egraph = EGraph(EgraphNode, EClassContext).init(std.testing.allocator);
    // _ = egraph;

    // var const1 = egraph.addEClass(EgraphNode{.constant = &.{1}});
    // var const2 = egraph.addEClass(EgraphNode{.constant = &.{2}});
    // egraph.addEClass(EgraphNode{.add = .{const1, const2}});
}
