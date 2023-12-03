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
        eclasses: std.AutoArrayHashMap(Id, EClass),
        memo: std.AutoHashMap(L, Id),
        dirty_ids: std.ArrayList(Id),
        dirty: bool,
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
            children: std.AutoArrayHashMapUnmanaged(L, Id) = .{},
            nodes: std.ArrayListUnmanaged(L),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .union_find = UnionFind.init(allocator),
                .eclasses = std.AutoArrayHashMap(Id, EClass).init(allocator),
                .memo = std.AutoHashMap(L, Id).init(allocator),
                .dirty_ids = std.ArrayList(Id).init(allocator),
                .dirty = false,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.dirty_ids.deinit();
            self.memo.deinit();
            for (self.eclasses.values()) |*eclass| {
                eclass.children.deinit(self.allocator);
                eclass.nodes.deinit(self.allocator);
            }
            self.eclasses.deinit();
            self.union_find.deinit();
        }

        pub fn get(self: @This(), id: Id) ?*EClass {
            return self.eclasses.getPtr(id);
        }

        pub fn addEclass(self: *@This(), first_enode: L) !Id {
            var enode = first_enode;
            if (self.lookup(&enode)) |existing| {
                return existing;
            }

            const id = try self.union_find.makeSet();

            var nodes = std.ArrayListUnmanaged(L){};
            try nodes.append(self.allocator, enode);

            const eclass = EClass{ .nodes = nodes, .ctx = .{} };

            if (enode.getMutableChildren()) |children| {
                for (children) |child| {
                    var eclass_child = self.eclasses.getPtr(child) orelse @panic("a saved enode's child is invalid.");
                    try eclass_child.children.put(self.allocator, enode, id);
                }
            }

            try self.eclasses.put(id, eclass);
            try self.memo.putNoClobber(enode, id);

            // here can call a callback?
            self.dirty = true;

            return id;
        }

        pub fn saturate(self: *@This(), rewrites: []const egg.Program(L), max_iter: usize) !void {
            var results = egg.MatchResultsArray.init(self.allocator);
            defer results.deinit(self.allocator);

            self.dirty = true;

            var iters: usize = 0;
            while (self.dirty and iters > max_iter) {
                self.dirty = false;

                for (rewrites) |rw| {
                    self.ematch(rw.lhs, results);
                    // use results.value.toOwnedSlice() to write individual results with the rewrite
                }

                for (results.value.items) |subst| {
                    _ = subst;
                    // for each rewrite, write each enode of the rhs and merge the symbols
                    for (subst, rw.rhs) |match, rhs|  {}
                    // add the new terms into the old
                }
            }
        }

        pub fn ematch(self: @This(), program: egg.Program(L), results: *egg.MatchResultsArray) void {
            var vm = egg.Machine(L).init(program, self.allocator);
            for (self.eclasses.keys()) |eclass| {
                vm.run(self, results, eclass, self.allocator) catch {};
            }
        }

        fn lookup(self: @This(), enode: *L) ?Id {
            self.canonicalize(enode);
            return self.memo.get(enode.*);
        }

        fn canonicalize(self: @This(), enode: *L) void {
            if (enode.getMutableChildren()) |children| {
                for (children) |*child| {
                    child.* = self.union_find.find(child.*);
                }
            }
        }

        fn merge(self: *@This(), a: Id, b: Id) !Id {
            if (self.union_find.find(a) == self.union_find.find(b)) {
                return self.union_find.find(a);
            }

            const new_id = self.union_find.merge(a, b);
            try self.dirty_ids.append(new_id);

            return new_id;
        }

        fn repair(self: *@This(), eclass_id: Id) void {
            var eclass = self.eclasses.getPtr(eclass_id).?;
            for (eclass.children.items) |parent| {
                std.debug.assert(self.memo.remove(parent.enode));
                self.canonicalize(&parent.enode);

                try self.memo.putNoClobber(
                    parent.enode,
                    self.union_find.find(parent.eclass_id),
                );
            }

            var visited_children = std.AutoArrayHashMap(L, Id).init(self.allocator);

            for (eclass.children.items) |parent| {
                if (visited_children.contains(parent.enode)) {
                    try self.merge(parent.eclass_id, visited_children.get(parent.enode));
                }

                try visited_children.put(parent.enode, self.union_find.find(parent.eclass_id));
            }

            eclass.children.deinit();
            eclass.children = visited_children.unmanaged;
        }

        pub fn find(self: @This(), id: Id) Id {
            return self.union_find.find(id);
        }

        fn rebuild(self: *@This()) void {
            while (self.dirty_ids.items.len > 0) {
                var todo = try self.dirty_ids.toOwnedSlice();
                for (todo) |eclass| {
                    self.repair(self.union_find.find(eclass));
                }
            }
        }
    };
}
