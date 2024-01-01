const Egraph = @import("egraph.zig").Egraph;
const egg = @import("../egg.zig");
const std = @import("std");

pub fn extract(comptime L: type) !type {
    return struct {
        eclass: egg.Id,
        egraph: Egraph,

        const partiallExp = struct { expression: std.ArrayList(L) };

        fn eval_inst_cost(inst: L) usize {
            return 1;
        }

        fn eval_expression_cost(eclass_id: egg.Id, enode_id: egg.Id) usize {
            var total_cost: usize = 0;
            for (partiallExp.expression) |part_cost| {
                total_cost += eval_inst_cost(part_cost);
            }

            return cost;
        }

        pub fn build_expressions() ![]const L {
            
        }

        pub fn init() @This() {
            return {};
        }
    };
}
