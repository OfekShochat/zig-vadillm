const std = @import("std");
const types = @import("types.zig");
const Type = @import("types.zig").Type;
const mem = std.mem;
const ir = @import("ir.zig");
const a = @import("DominatorTree.zig");
const wtf = @import("LoopAnalysis.zig");
const IndexedMap = @import("indexed_map.zig").IndexedMap;
const Function = @import("function.zig").Function;
const ControlFlowGraph = @import("ControlFlowGraph.zig");
const Instruction = @import("instructions.zig").Instruction;
const Signature = @import("function.zig").Signature;

// pub const Index = u32;
// pub const Index = u32;
// pub const Index = u32;
// pub const Index = u32;
// pub const Index = u32;
// pub const GlobalIndex = u32;

pub const Target = struct {};

pub const Constant = []const u8;

pub const FunctionDecl = struct {
    name: []const u8,
    signature: Signature,
};

// pub const Rewrite = struct {
//     name: []const u8,
// };
//
// pub fn parseRewrite(comptime name: []const u8, comptime rw: []const u8) !Rewrite {
//     return struct {};
// }

// pub const VerifierError = struct {
//     ty: enum {
//         Typecheck,
//     },
//     loc: Index,
//     message: []const u8,
// };

// pub const Verifier = struct {
//     // graph: *const Graph,

//     pub const ErrorStack = std.ArrayList(VerifierError);

//     pub fn init() Verifier {}

//     pub fn verify(self: *Verifier, error_stack: *ErrorStack) bool {
//         var iter = self.graph.nodes.iterator();
//         while (iter) |kv| {
//             try self.typecheck(kv.key_ptr.*, error_stack);
//         }
//     }

//     fn typecheck(self: Verifier, node: Index, error_stack: *ErrorStack) !void {
//         _ = self;

//         try error_stack.append(VerifierError{
//             .ty = .Typecheck,
//             .loc = node,
//             .message = "",
//         });
//     }
// };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    // var instructio = std.heap.MemoryPool(std.ArrayListUnmanaged(ir.Index)).init(alloc);

    var func = Function.init(alloc, Signature{
        .ret = types.I32,
        .args = .{},
    });

    defer func.deinit(alloc);

    try func.appendParam(alloc, types.I32);

    const b = try func.appendBlock(alloc);
    const b2 = try func.appendBlock(alloc);

    // var args = (try instructio.create());
    _ = try func.appendInst(
        alloc,
        b,
        Instruction{ .jump = .{ .block = b2, .args = .{} } },
        types.I32,
    );

    const p1 = try func.appendBlockParam(alloc, b, types.I32);

    _ = try func.appendInst(
        alloc,
        b2,
        Instruction{ .ret = p1 },
        types.I32,
    );

    const cfg = try ControlFlowGraph.fromFunction(alloc, &func);

    var domtree = a{};
    try domtree.compute(alloc, &cfg);
    std.log.info("{any}", .{domtree.formatter(&func)});
    std.log.info("{any}", .{@sizeOf(Instruction)});
}
