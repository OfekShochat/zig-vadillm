const std = @import("std");
const egg = @import("../egg.zig");
const EGraph = @import("Egraph.zig");

pub fn Program(comptime L: type) Program {
    return struct {
        const Instruction = enum {
            Bind: struct {
                reg: egg.Id,
                node: L,
                reg2: egg.Id,
            },
            Check: struct {
                reg: egg.Id,
                Node: L,
            },
            Compare: struct {
                reg1: egg.Id,
                reg2: egg.Id,
            },
            Yield: std.ArrayList(egg.Id),
        };

        v2r: std.AutoHashMap(usize, egg.Id),
        stack: std.ArrayList(Instruction);
    };

    pub fn compile(r2p: std.AutoArrayHashMap(egg.Id, N)) {
        var former_reg = 0;
        while(r2p.popOrNull()) |r2p_entry| {
            switch(r2p_entry) {
                .Bind => |bind| {
                    if(r2p_entry.children()) {
                        stack.push(Bind {.reg = r2p_entry.key, .node = r2p_entry.value, .reg2 = former_reg});
                    }
                }
            }
        }
    }
}
