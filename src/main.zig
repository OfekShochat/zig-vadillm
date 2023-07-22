const std = @import("std");

pub const NodeRef = u32;

const SIZE_MASK = 0b111;
const INVALID_MASK = 0xFFFF;
const IS_INT_MASK = 1 << 3;
const IS_FLOAT_MASK = 1 << 4;
const IS_PTR_MASK = 1 << 5;
const IS_VECTOR_MASK = 1 << 6;
const LANES_MASK = 0b111 << 7;

/// Type; can you guess what this is?
/// Encoded in a bitset (0x0 is void, 0xFFFF is invalid):
/// +---------------+-----+-------+-----+--------+-------------+
/// | 0-2           | 3   | 4     | 5   | 6      | 7-9         |
/// +---------------+-----+-------+-----+--------+-------------+
/// | log2(bitsize) | int | float | ptr | vector | log2(lanes) |
/// +---------------+-----+-------+-----+--------+-------------+
pub const Type = struct {
    val: u16,

    pub fn from(comptime T: type) Type {
        var val: u16 = 0;

        const type_info = @typeInfo(T);
        switch (type_info) {
            .Float => |float| {
                comptime if (!std.math.isPowerOfTwo(float.bits)) {
                    @compileError("float bits have to be powers of two.");
                };
                val |= IS_FLOAT_MASK;
                val |= @ctz(float.bits);
            },
            .Int => |int| {
                comptime if (!std.math.isPowerOfTwo(int.bits)) {
                    @compileError("int bits have to be powers of two.");
                };
                val |= IS_INT_MASK;
                val |= @ctz(int.bits);
            },
            .Vector => |vec| {
                comptime if (!std.math.isPowerOfTwo(vec.len)) {
                    @compileError("vector lengths have to be powers of two.");
                };
                val |= Type.from(vec.child).val;
                val |= IS_VECTOR_MASK;

                const size: u16 = @ctz(@as(u16, vec.len));
                val |= size << 7;
            },
            .Pointer => val |= IS_PTR_MASK,
            else => {}, // void is 0x0 anyway
        }

        return Type{ .val = val };
    }

    pub fn invalid_type() Type {
        return Type{ .val = INVALID_MASK };
    }

    pub fn log2_bits(self: Type) u3 {
        return @truncate(self.val & SIZE_MASK);
    }

    pub fn bits(self: Type) u16 {
        return @as(u16, 1) << self.log2_bits();
    }

    pub fn bytes(self: Type) u16 {
        return (self.bits() + 7) / 8;
    }

    pub fn log2_lanes(self: Type) u3 {
        return @intCast((self.val & LANES_MASK) >> 7);
    }

    pub fn lanes(self: Type) u16 {
        return @as(u16, 1) << self.log2_lanes();
    }

    pub fn is_int(self: Type) bool {
        return self.val & IS_INT_MASK != 0;
    }

    pub fn is_float(self: Type) bool {
        return self.val & IS_FLOAT_MASK != 0;
    }

    pub fn is_ptr(self: Type) bool {
        return self.val & IS_PTR_MASK != 0;
    }

    pub fn is_vector(self: Type) bool {
        return self.val & IS_VECTOR_MASK != 0;
    }

    pub fn is_valid(self: Type) bool {
        return self.val != INVALID_MASK;
    }
};

const PTR = Type.from(*i8);

pub const BinOp = struct { lhs: NodeRef, rhs: NodeRef };

pub const Instruction = union(enum) {
    add: BinOp,
    sub: BinOp,
    mul: BinOp,
    shl: BinOp,
    shr: BinOp,

    alloca: struct { size: usize, alignment: usize },

    brif: struct {
        cond: NodeRef,
        cond_true: NodeRef,
        cond_false: NodeRef,
        params: std.ArrayList(NodeRef),
    },
};

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
/// // ?*Node is given to get the (optional) origin node
/// var egraph = Egraph(EgraphNode, ?*Node).init(allocator);
///
/// var const1 = egraph.add_eclass(EgraphNode{.constant = &{1}});
/// var const2 = egraph.add_eclass(EgraphNode{.constant = &{2});
/// egraph.add_eclass(EgraphNode{.add = .{const1, const2}});
///
/// var pass_ctx = MyPassContext{
///     ...
/// };
///
/// var iter =
///
/// ...
/// ```
pub fn Egraph(comptime T: type, comptime C: type) type {
    return struct {
        nodes: std.AutoHashMap(NodeRef, T),
        allocator: std.mem.Allocator,

        pub const EClass = struct {
            equivalences: std.ArrayList(T),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .nodes = std.AutoHashMap(NodeRef, T).init(allocator),
                .allocator = allocator,
            };
        }
    };
}

pub const NodeData = union(enum) {
    alias: struct { to: NodeRef },
    region: struct {
        nodes: std.ArrayList(NodeRef), // nodes that use the parameters
        params: std.ArrayList(Type),
    },
    param: struct { idx: usize, region: NodeRef },
    constant: []const u8,
    global_value: struct { name: []const u8, initial_value: []const u8 },
    inst: Instruction,
};

pub const NodeHasher = struct {
    graph: *Graph,

    pub fn hash(self: NodeHasher, node_ref: NodeRef) ?u64 {
        if (self.graph.nodes.get(node_ref)) |node| {
            return switch (node.data) {
                .alias => |alias| blk: {
                    std.debug.assert(alias.to != node_ref);
                    break :blk self.hash(alias.to);
                },
                .region => null, // should region nodes be hashed? yes
                .param => |param| std.hash.Murmur2_64.hash(&std.mem.toBytes(param.idx)) ^ self.hash(param.region).?,
                .constant => |constant| std.hash.Murmur2_64.hash(constant),
                .global_value => |gv| std.hash.Murmur2_64.hash(gv.name),
                .inst => |inst| self.hash_inst(inst),
            };
        }
        return null;
    }

    fn hash_inst(self: NodeHasher, inst: Instruction) u64 {
        return switch (inst) {
            .add, .sub, .mul => |binop| self.hash_binop(binop, inst),
            else => 0,
        };
    }

    fn hash_binop(self: NodeHasher, binop: BinOp, op: Instruction) u64 {
        return self.hash(binop.lhs).? ^ self.hash(binop.rhs).? ^ std.hash.Murmur2_64.hash(&std.mem.toBytes(op));
    }
};

pub const Node = struct {
    uses: std.ArrayList(NodeRef),
    data: NodeData,
    ty: Type,

    pub fn init(data: NodeData, ty: Type, alloc: std.mem.Allocator) Node {
        return Node{
            .uses = std.ArrayList(NodeRef).init(alloc),
            .data = data,
            .ty = ty,
        };
    }

    pub fn deinit(self: Node) void {
        self.uses.deinit();
    }
};

pub const Graph = struct {
    nodes: std.AutoHashMap(NodeRef, Node),
    counter: u32,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Graph {
        return Graph{
            .nodes = std.AutoHashMap(NodeRef, Node).init(alloc),
            .counter = 0,
            .alloc = alloc,
        };
    }

    pub fn add_node(self: *Graph, node_data: NodeData, ty: Type) !NodeRef {
        defer self.counter += 1;
        try self.nodes.put(self.counter, Node.init(node_data, ty, self.alloc));

        return self.counter;
    }

    pub fn deinit(self: *Graph) void {
        var iter = self.nodes.iterator();
        while (iter.next()) |kv| {
            kv.value_ptr.deinit();
        }

        self.nodes.deinit();
    }
};

pub const VerifierError = struct {
    ty: enum {
        Typecheck,
    },
    loc: NodeRef,
    message: []const u8,
};

pub const Verifier = struct {
    graph: *const Graph,

    pub const ErrorStack = std.ArrayList(VerifierError);

    pub fn init(graph: *Graph) Verifier {
        return Verifier{ .graph = graph };
    }

    pub fn verify(self: *Verifier, error_stack: *ErrorStack) bool {
        var iter = self.graph.nodes.iterator();
        while (iter) |kv| {
            try self.typecheck(kv.key_ptr.*, error_stack);
        }
    }

    fn typecheck(self: Verifier, node: NodeRef, error_stack: *ErrorStack) !void {
        _ = self;

        try error_stack.append(VerifierError{
            .ty = .Typecheck,
            .loc = node,
            .message = "",
        });
    }
};

const poop = union {};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var graph = Graph.init(alloc);
    defer graph.deinit();

    var const1 = try graph.add_node(.{ .constant = &[_]u8{ 1, 2, 3 } }, Type.from(*i8));
    var gv1 = try graph.add_node(.{ .global_value = .{
        .name = "hello",
        .initial_value = &[_]u8{ 1, 2, 3 },
    } }, Type.from(*i8));

    var add = try graph.add_node(.{ .inst = .{
        .add = .{ .lhs = const1, .rhs = gv1 },
    } }, PTR);

    std.log.info("{?}", .{graph.nodes.get(add)});

    var egraph = Egraph(poop, ?*Node).init(alloc);
    _ = egraph;

    // var verifier = Verifier.init(&graph);
    // var errors = Verifier.ErrorStack.init(alloc);

    // _ = try verifier.typecheck(add, &errors);
    // _ = try verifier.verify(add, &errors);
}

test "types" {
    const iv = Type.from(@Vector(4, i32));
    try std.testing.expect(iv.is_valid());
    try std.testing.expect(iv.is_vector());
    try std.testing.expect(iv.lanes() == 4);
    try std.testing.expect(iv.bits() == 32);
    try std.testing.expect(iv.bytes() == 4);
    try std.testing.expect(!iv.is_ptr());
    try std.testing.expect(!iv.is_float());

    const f = Type.from(f64);
    try std.testing.expect(f.is_valid());
    try std.testing.expect(f.is_float());
    try std.testing.expect(!f.is_vector());
    try std.testing.expect(!f.is_ptr());
    try std.testing.expect(f.bits() == 64);
    try std.testing.expect(f.bytes() == 8);
}
