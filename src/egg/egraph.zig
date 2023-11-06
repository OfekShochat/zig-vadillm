const std = @import("std");

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
pub fn EGraph(comptime L: type, comptime C: type) type {
    return struct {
        union_find: UnionFind,
        eclasses: std.AutoHashMap(Id, EClass),
        memo: std.AutoHashMap(ENode, Id),
        dirty: std.ArrayList(Id),
        allocator: std.mem.Allocator,

        comptime {
            if (!std.meta.trait.is(.Union)(L)) {
                @compileError("`L` has to be a union to qualify to be a Language.");
            }
        }

        const PendingEntry = struct {
            id: Id,
            eclass: EClass,
        };

        pub const EClass = struct {
            // dude how do I not save the enode itself it feels bad
            parents: std.AutoArrayHashMapUnmanaged(ENode, Id) = .{},
            nodes: std.ArrayListUnmanaged(ENode),
            ctx: C,
        };

        pub const ENode = struct {
            op: L,
            children: std.ArrayListUnmanaged(Id),
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .union_find = UnionFind.init(allocator),
                .eclasses = std.AutoHashMap(Id, EClass).init(allocator),
                .memo = std.AutoHashMap(EClass, Id).init(allocator),
                .worklist = std.ArrayList(Id).init(allocator),
                .allocator = allocator,
            };
        }

        fn lookup(self: @This(), enode: *ENode) ?Id {
            self.canonicalize(enode);
            return self.memo.get(enode.*);
        }

        fn addEclass(self: *@This(), first_enode: ENode) !Id {
            if (self.lookup(first_enode)) |existing| {
                return existing;
            }

            const id = self.union_find.makeSet();

            var nodes = std.ArrayListUnmanaged(ENode){};
            try nodes.append(self.allocator, first_enode);

            const eclass = EClass{ .id = id, .nodes = nodes, .ctx = .{} };

            for (first_enode.children.items) |child| {
                var eclass_child = self.eclasses.getPtr(child) orelse @panic("a saved enode's child is invalid.");
                try eclass_child.parents.put(self.allocator, first_enode, id);
            }

            try self.eclasses.put(id, eclass);
            try self.memo.putNoClobber(first_enode, id);

            // here can call a callback?
            // self.dirty = true;

            return id;
        }

        // this is a horrible name. updateParentsToRepresentatives?
        pub fn canonicalize(self: @This(), enode: *ENode) void {
            for (enode.children.items) |*child| {
                child.* = self.union_find.find(child.*);
            }
        }

        fn merge(self: *@This(), a: Id, b: Id) !Id {
            if (self.union_find.find(a) == self.union_find.find(b)) {
                return self.union_find.find(a);
            }

            const new_id = self.union_find.merge(a, b);
            try self.dirty.append(new_id);

            return new_id;
        }

        fn repair(self: *@This(), eclass_id: Id) void {
            var eclass = self.eclasses.getPtr(eclass_id).?;
            for (eclass.parents.items) |parent| {
                std.debug.assert(self.memo.remove(parent.enode));
                self.canonicalize(&parent.enode);

                try self.memo.putNoClobber(
                    parent.enode,
                    self.union_find.find(parent.eclass_id),
                );
            }

            var visited_parents = std.AutoArrayHashMap(ENode, Id).init(self.allocator);

            for (eclass.parents.items) |parent| {
                if (visited_parents.contains(parent.enode)) {
                    try self.merge(parent.eclass_id, visited_parents.get(parent.enode));
                }

                try visited_parents.put(parent.enode, self.union_find.find(parent.eclass_id));
            }

            eclass.parents.deinit();
            eclass.parents = visited_parents.unmanaged;
        }

        fn rebuild(self: *@This()) void {
            while (self.dirty.items.len > 0) {
                var todo = try self.dirty.toOwnedSlice();
                for (todo) |eclass| {
                    self.repair(self.union_find.find(eclass));
                }
            }
        }
    };
}

test "egraph" {
    var poop = EGraph();
    _= poop;
}
