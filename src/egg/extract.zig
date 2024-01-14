const EGraph = @import("egraph.zig").EGraph;
const egg = @import("egg.zig");
const std = @import("std");
const ToyLanguage = @import("tests.zig").ToyLanguage;

pub fn extract(comptime L: type) type {
    return struct {
        eclass: egg.Id,
        partialExp: std.ArrayList(L),

        fn eval_eclass_min_cost(self: *@This(), eclass_id: egg.Id, egraph: anytype) !usize {
            var enodes = egraph.get(eclass_id).?.*.nodes.items;
            var min_enode = enodes[0];
            var min_cost = enodes[0].getExpressionCost();
            for (0..enodes.len) |i| {
                var enode_cost = enodes[i].getExpressionCost();
                if (enode_cost < min_cost) {
                    min_cost = enodes[i].getExpressionCost();
                    min_enode = enodes[i];
                }
            }

            try self.partialExp.append(min_enode);
            return min_cost;
        }

        fn eval_expression_cost(self: *@This(), eclass_id: egg.Id, egraph: anytype) !usize {
            var total_cost: usize = 0;
            var eclass = egraph.get(eclass_id);
            total_cost += try eval_eclass_min_cost(self, eclass_id, egraph);
            std.log.warn("current_cost: {}", .{total_cost});
            var children = eclass.?.children.values();
            std.log.warn("number of childrens: {}", .{children.len});
            for (children) |child| {
                total_cost += try eval_eclass_min_cost(self, child, egraph);
                std.log.warn("current cost: {}", .{total_cost});
            }

            std.log.warn("total expression cost: {}", .{total_cost});
            return total_cost;
        }

        pub fn find_cheapest_expression(self: *@This(), root_eclass: egg.Id, egraph: anytype) !usize {
            var total_cost: usize = 0;
            var eclass_stack = std.ArrayList(egg.Id).init(std.testing.allocator);
            defer eclass_stack.deinit();

            try eclass_stack.append(root_eclass);
            while (true) {
                if (eclass_stack.items.len == 0) {
                    break;
                }

                var eclass = eclass_stack.popOrNull() orelse return total_cost; // eclass_stack.items[eclass_stack.items.len - 1];
                total_cost += try eval_expression_cost(self, eclass, egraph);
                std.log.warn("current cost: {}", .{try eval_expression_cost(self, eclass, egraph)});
                var childrens = egraph.get(eclass).?.children;
                std.log.warn("childrens: {}", .{childrens.values().len});
                for (childrens.values()) |children| {
                    std.log.warn("children: {}", .{egraph.get(children).?.*.nodes.items[0]});
                    try eclass_stack.append(children);
                }

                std.log.warn("eclass_stack size before pop: {}", .{eclass_stack.items.len});
                _ = eclass_stack.popOrNull() orelse return total_cost;
                std.log.warn("eclass_stack size: {}", .{eclass_stack.items.len});
            }

            return total_cost;
        }

        pub fn init(eclass: egg.Id) @This() {
            return @This(){ .eclass = eclass, .partialExp = std.ArrayList(L).init(std.testing.allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.partialExp.deinit();
        }
    };
}

test "extract" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    _ = try egraph.addEclass(.{ .add = .{ const1, const1 } });

    var childrens = egraph.get(0).?.*.children;
    var children = egraph.get(childrens.values()[0]);
    std.log.warn("childrens: {}", .{children.?.children.values().len});
    std.log.warn("children children {}", .{children.?.children.keys().len});
    var extract_obj = extract(ToyLanguage).init(0);
    var cost: usize = try extract_obj.find_cheapest_expression(0, egraph);
    std.log.warn("cost: {}", .{cost});
    for (extract_obj.partialExp.items) |lang| {
        std.log.warn("obj: {}", .{lang});
    }
    extract_obj.deinit();
}
