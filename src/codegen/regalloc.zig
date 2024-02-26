const std = @import("std");
const codegen = @import("codegen.zig");
const types = @import("../types.zig");

const Abi = @import("Abi.zig");
const MachineFunction = @import("MachineFunction.zig");
const SpillCostCalc = @import("SpillCostCalc.zig");
const Target = @import("Target.zig");

pub const RegClass = enum(u2) {
    int,
    float,
    vector,
};

pub const RegAllocError = error{
    ContradictingConstraints,
};

/// In bytes
pub const RegisterSize = enum {
    @"1",
    @"2",
    @"4",
    @"8",
    @"16",
    @"32",
    @"64",
    @"128",
};

// TODO: give it the function, it would calculate costs and liveranges then pass it to the regallocator
pub fn runRegalloc(comptime R: type, allocator: std.mem.Allocator, abi: Abi, live_ranges: []const *LiveRange) !Solution {
    const func: *const MachineFunction = undefined;

    var spillcost_calc: SpillCostCalc = undefined;

    // var liveness = Liveness.init(func);
    // const live_ranges = liveness.compute();

    var regalloc = R.init(allocator, abi);
    defer regalloc.deinit();

    if (regalloc.run(live_ranges, &spillcost_calc)) |output| {
        const solution = try Solution.fromAllocatedRanges(allocator, output, func);

        std.log.debug("regalloc found a solution:", .{});
        std.log.debug("{}", .{solution.formatSolution(allocator, abi)});

        return solution;
    } else |err| {
        const inter_output = try regalloc.getIntermediateSolution();
        const solution = try Solution.fromAllocatedRanges(allocator, inter_output, func);

        std.log.err("regalloc encountered an error: {}.", .{err});
        std.log.err("{}", .{solution.formatSolution(allocator, abi)});

        return err;
    }
}

pub const VirtualReg = struct {
    index: u32,
    typ: types.Type,

    pub fn class(self: VirtualReg) RegClass {
        if (self.typ.isVector()) return .vector;
        if (self.typ.isInt()) return .int;
        if (self.typ.isFloat()) return .float;

        @panic("Invalid type in vreg.");
    }

    pub fn format(
        self: VirtualReg,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const class_str = switch (self.class()) {
            .int => "i",
            .float => "f",
            .vector => "v",
        };

        return writer.print("v{}{s}", .{ self.index, class_str });
    }
};

pub const SolutionVisualizer = struct {
    max_end: usize,
    max_width: usize,
    ranges: std.ArrayListUnmanaged(LiveRange),
    abi: Abi,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, abi: Abi) SolutionVisualizer {
        const arena = std.heap.ArenaAllocator.init(allocator);

        // arena fucks everything up.
        return SolutionVisualizer{
            .max_end = 0,
            .max_width = 0,
            .arena = arena,
            .ranges = std.ArrayListUnmanaged(LiveRange){},
            .abi = abi,
        };
    }

    pub fn add(self: *SolutionVisualizer, range: LiveRange) !void {
        if (range.preg() == null) {
            self.max_width += 1;
        }

        self.max_end = @max(range.end.point, self.max_end);
        try self.ranges.append(self.arena.allocator(), range);
    }

    pub fn format(
        self: *SolutionVisualizer,
        writer: anytype,
        allocator: std.mem.Allocator,
        row_buf: []u8,
        pregs: []const PhysicalReg,
        active: *std.ArrayList(LiveRange),
        offsets: std.AutoHashMap(PhysicalReg, usize),
    ) !void {
        @memset(row_buf, ' ');

        var offset: usize = 0;
        for (pregs) |preg| {
            _ = try std.fmt.bufPrint(row_buf[offset..], "{}", .{preg});
            offset += 5;
        }

        row_buf[offset - 2] = '\n';
        try writer.writeAll(row_buf[0 .. offset - 1]);

        var active_stack = std.AutoHashMap(VirtualReg, usize).init(allocator);
        defer active_stack.deinit();

        var step: usize = 0;

        while (self.ranges.items.len > 0 or active.items.len > 0) : (step += 1) {
            @memset(row_buf, ' ');

            var i: usize = 0;
            while (i < active.items.len) {
                if (step > active.items[i].end.point) {
                    if (active.items[i].preg() == null) {
                        _ = active_stack.remove(active.items[i].vreg);
                    }

                    _ = active.orderedRemove(i);
                } else {
                    i += 1;
                }
            }

            while (self.ranges.popOrNull()) |range| {
                if (range.rawStart() <= step) {
                    if (range.preg()) |preg| {
                        _ = try std.fmt.bufPrint(row_buf[offsets.get(preg).?..], "{}", .{range.vreg});
                    }

                    try active.append(range);
                } else {
                    try self.ranges.append(self.arena.allocator(), range);
                    break;
                }
            }

            var stack_offset = pregs.len * 4;
            for (active.items) |active_range| {
                if (active_range.rawStart() == step) {
                    if (active_range.preg() == null) {
                        _ = try std.fmt.bufPrint(row_buf[stack_offset..], "{}", .{active_range.vreg});
                        try active_stack.put(active_range.vreg, stack_offset);
                        stack_offset += 4;
                    }
                    continue;
                }

                if (active_range.preg()) |preg| {
                    row_buf[offsets.get(preg).? + 1] = '|';
                } else {
                    const ofst = active_stack.get(active_range.vreg).?;
                    row_buf[ofst + 1] = '|';
                    stack_offset = @max(ofst, stack_offset) + 4;
                }
            }

            row_buf[stack_offset + 1] = '\n';
            try writer.writeAll(row_buf[0 .. stack_offset + 2]);
        }
    }

    pub fn print(self: *SolutionVisualizer, writer: anytype) !void {
        const allocator = self.arena.allocator();

        const pregs = try self.abi.getAllPregs(allocator);
        self.max_width += pregs.len;

        var offsets = std.AutoHashMap(PhysicalReg, usize).init(allocator);

        for (pregs, 0..) |preg, i| {
            try offsets.put(preg, i * 5);
        }

        std.sort.block(LiveRange, self.ranges.items, void{}, LiveRange.lessThan);
        std.mem.reverse(LiveRange, self.ranges.items);

        var active = std.ArrayList(LiveRange).init(allocator);

        try active.ensureTotalCapacity(self.max_width);

        return self.format(writer, allocator, try allocator.alloc(u8, self.max_width * 5 + 1), pregs, &active, offsets);
    }
};

pub const SolutionConsumer = struct {
    stitches: []const Stitch,
    ranges: []const LiveRange,
    current: codegen.CodePoint,
    mapping: std.AutoArrayHashMap(LiveRange, PhysicalReg),

    pub const SolutionPoint = struct {
        mapping: *std.AutoHashMap(VirtualReg, PhysicalReg),
        stitches: []const Stitch,
    };

    pub fn advance(self: *SolutionConsumer) !SolutionPoint {
        try self.advanceActive();

        const stitches = try self.advanceStitches();

        self.current = self.current.getNextInst();

        return SolutionPoint{
            .mapping = &self.mapping,
            .stitches = stitches,
        };
    }

    fn advanceStitches(self: *SolutionConsumer) []const Stitch {
        if (self.stitches.len == 0) return &.{};

        if (self.stitches[0].codepoint.isSame(self.current)) {
            return &.{};
        }

        var end: usize = 0;
        for (self.stitches) |stitch| {
            end += 1;
            if (!stitch.code_point.isSame(self.current)) break;
        }

        defer self.stitches = self.stitches[end..];

        return self.stitches[0..end];
    }

    fn advanceActive(self: *SolutionConsumer) ![]const LiveRange {
        var i: usize = 0;
        while (i < self.mapping.values().len) {
            if (self.current.isAfter(self.mapping.values().end)) {
                _ = self.mapping.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        var index: usize = 0;

        while (index < self.ranges.len) {
            const range = self.ranges[index];
            if (range.start.isBeforeOrAt(self.current)) {
                try self.mapping.put(range.vreg(), range);
                index += 1;
            }
        }

        self.ranges = self.ranges[index..];
    }
};

fn discoverStitches(allocator: std.mem.Allocator, allocated_ranges: []LiveRange) ![]Stitch {
    std.sort.heap(LiveRange, allocated_ranges, void{}, LiveRange.lessThan);

    // Preserves insertion order.
    var intervals = std.AutoArrayHashMap(*LiveInterval, void).init(allocator);
    defer intervals.deinit();

    for (allocated_ranges) |range| {
        try intervals.put(range.live_interval, void{});
    }

    var last_used = std.AutoHashMap(VirtualReg, *LiveRange).init(allocator);
    defer last_used.deinit();

    var stitches = std.ArrayList(Stitch).init(allocator);

    // NOTE:
    // Live intervals should be continuous accross blocks, considering control flow.
    // Also note that splits within instructions are discarded in emission.

    for (intervals.keys()) |interval| {
        const range = interval.ranges[0];
        if (last_used.get(range.vreg)) |last_range| {
            if (std.meta.eql(interval.allocation.?, last_range.live_interval.allocation.?)) continue;

            try stitches.append(Stitch{
                .codepoint = last_range.end.getNextInst(),
                .from = last_range.live_interval.allocation.?,
                .to = interval.allocation.?,
            });
        }

        try last_used.put(range.vreg, range);
    }

    return stitches.toOwnedSlice();
}

/// `stitches` should be ordered by codepoint.
fn assignStackSlotsToStitches(func: *const MachineFunction, stitches: []Stitch, target: Target) !void {
    var idx: usize = 0;

    // Should never go negative in valid code.
    var delta: isize = 0;

    var iter = func.blockIter();
    while (iter.next()) |block| {
        var current = block.start;

        for (block.insts) |inst| {
            std.debug.assert(delta >= 0);

            while (stitches[idx].codepoint.isSame(current)) : (idx += 1) {
                if (stitches[idx].to == .stack) {
                    // TODO: should this always be `word_size`?
                    delta += target.word_size;
                    stitches[idx].to = .{ .stack = @intCast(delta) };
                }
            }

            delta += inst.getStackDelta();
            current = current.getNextInst();
        }
    }
}

pub const Solution = struct {
    allocations: []const LiveRange,
    stitches: []const Stitch,

    pub fn deinit(self: *Solution, allocator: std.mem.Allocator) void {
        allocator.free(self.allocations);
        allocator.free(self.stitches);
    }

    const FormatContext = struct {
        solution: Solution,
        allocator: std.mem.Allocator,
        abi: Abi,
    };

    pub fn formatSolution(solution: Solution, allocator: std.mem.Allocator, abi: Abi) std.fmt.Formatter(visualize) {
        return .{ .data = .{
            .solution = solution,
            .allocator = allocator,
            .abi = abi,
        } };
    }

    pub fn visualize(ctx: FormatContext, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var visualizer = SolutionVisualizer.init(ctx.allocator, ctx.abi);
        defer visualizer.arena.deinit();

        for (ctx.solution.allocations) |range| {
            visualizer.add(range) catch @panic("OOM");
        }

        visualizer.print(writer) catch @panic("OOM or Writer");
    }

    pub fn fromAllocatedRanges(allocator: std.mem.Allocator, allocations: []LiveRange, func: *const MachineFunction) !Solution {
        const stitches = try discoverStitches(allocator, allocations);
        _ = func;
        // try assignStackSlotsToStitches(func, stitches);

        return Solution{
            .allocations = allocations,
            .stitches = stitches,
        };
    }
};

pub const PhysicalReg = struct {
    class: RegClass,
    /// the unique encoding of a register. should fit into 7 bits.
    encoding: u7,

    pub fn format(
        self: PhysicalReg,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const class_str = switch (self.class) {
            .int => "i",
            .float => "f",
            .vector => "v",
        };

        return writer.print("p{}{s}", .{ self.encoding, class_str });
    }
};

pub const Register = union(enum) {
    preg: PhysicalReg,
    vreg: VirtualReg,
};

pub const LocationConstraint = union(enum) {
    none,
    phys_reg,
    stack,

    /// fixed physical register
    fixed_reg: PhysicalReg,

    /// simulates instructions such as `add` that only have two operands but modify one:
    /// add v2 [late def], v1 [early use], v0 [early use, reuse-reg(0)]
    /// Should be emulated by adding it to the same interval.
    reuse: u6,

    pub fn asBytes(self: LocationConstraint) u8 {
        return switch (self) {
            .none => 0b0,
            .phys_reg => 0b1,
            .stack => 0b10,
            .fixed_reg => |reg| 0b10000000 | @as(u8, reg.encoding),
            .reuse => |idx| 0b01000000 | @as(u8, idx),
        };
    }
};

pub const AccessType = enum(u1) {
    def = 0,
    use = 1,
};

pub const OperandUseTiming = enum(u1) {
    early = 0,
    late = 1,
};

pub const Operand = struct {
    //! # An Operand
    //!
    //! +-------------+-------------+-------------+-----------+------------+
    //! | 24-31       | 23          | 22          | 20-21     | 0-19       |
    //! +-------------+-------------+-------------+-----------+------------+
    //! | constraints | access type | operand use | reg class | vreg index |
    //! +-------------+-------------+-------------+-----------+------------+
    //! # constraints' encoding:
    //! 00000000 => none
    //! 00000001 => phys_reg
    //! 00000010 => stack
    //! 1xxxxxxx => fixed_reg{xxxxxxx}
    //! 01xxxxxx => reuse{xxxxxx}
    bits: u32,

    pub fn init(vreg: VirtualReg, access_type: AccessType, constraints: LocationConstraint, operand_use: OperandUseTiming) Operand {
        std.debug.assert(vreg.index < (1 << 20));

        return Operand{
            .bits = vreg.index |
                (@as(u32, @intFromEnum(vreg.class())) << 20) |
                (@as(u32, @intFromEnum(operand_use)) << 22) |
                (@as(u32, @intFromEnum(access_type)) << 23) |
                (@as(u32, constraints.asBytes()) << 24),
        };
    }

    pub fn locationConstraints(self: Operand) LocationConstraint {
        const constraints = (self.bits >> 24) & 0xFF;

        if (constraints & 0b10000000 != 0) {
            return LocationConstraint{ .fixed_reg = .{
                .class = self.regclass(),
                .encoding = @intCast(constraints & 0b01111111),
            } };
        } else if (constraints & 0b01000000 != 0) {
            return LocationConstraint{ .reuse = @intCast(constraints & 0b00111111) };
        }

        return switch (constraints) {
            0 => .none,
            1 => .phys_reg,
            2 => .stack,
            else => @panic("invalid encoding"),
        };
    }

    pub fn regclass(self: Operand) RegClass {
        return @enumFromInt((self.bits >> 20) & 0b11);
    }

    pub fn operandUse(self: Operand) OperandUseTiming {
        return @enumFromInt((self.bits >> 22) & 0b1);
    }

    pub fn accessType(self: Operand) AccessType {
        return @enumFromInt((self.bits >> 23) & 0b1);
    }

    pub fn vregIndex(self: Operand) u32 {
        return self.bits & 0x3FF;
    }
};

pub const Allocation = union(enum) {
    /// sp-relative
    stack: ?usize,
    preg: PhysicalReg,
};

pub const Stitch = struct {
    codepoint: codegen.CodePoint,
    from: Allocation,
    to: Allocation,
};

pub const LiveRange = struct {
    start: codegen.CodePoint,
    end: codegen.CodePoint,
    live_interval: *LiveInterval,
    uses: []const codegen.CodePoint,
    spill_cost: usize,
    vreg: VirtualReg,

    split_count: u8 = 0,
    evicted_count: u8 = 0,

    pub const Point = u32;

    pub fn rawStart(self: LiveRange) usize {
        return self.start.point;
    }

    pub fn compare(self: LiveRange, other: LiveRange) std.math.Order {
        return switch (self.start.compare(other.start)) {
            .eq => self.end.compare(other.end),
            else => |e| e,
        };
    }

    pub fn compareConst(_: void, self: *const LiveRange, other: *const LiveRange) std.math.Order {
        return switch (self.start.compare(other.start)) {
            .eq => self.end.compare(other.end),
            else => |e| e,
        };
    }

    pub fn lessThan(_: void, self: LiveRange, other: LiveRange) bool {
        return self.compare(other) == .lt;
    }

    pub fn rawEnd(self: LiveRange) usize {
        return self.end.point;
    }

    pub fn isMinimal(self: LiveRange) bool {
        return self.end.point - self.start.point <= 2;
    }

    pub fn class(self: LiveRange) RegClass {
        return self.vreg.class();
    }

    pub fn preg(self: LiveRange) ?PhysicalReg {
        if (self.live_interval.allocation) |allocation| {
            if (allocation == .preg) {
                return allocation.preg;
            } else return null;
        } else return null;
    }

    pub fn constraints(self: LiveRange) LocationConstraint {
        return self.live_interval.constraints;
    }

    pub fn spillable(self: LiveRange) bool {
        return switch (self.constraints()) {
            .none, .stack, .reuse => true,
            .fixed_reg, .phys_reg => false,
        };
    }
};

pub const LiveInterval = struct {
    ranges: []const *LiveRange,
    constraints: LocationConstraint,
    allocation: ?Allocation,
};

pub fn rangesIntersect(a: LiveRange, start: usize, end: usize) bool {
    return (a.start >= start and a.start <= end) or (start >= a.start and start <= a.end);
}

test "regalloc.Operand" {
    // use constants and also make a test that should panic (index too high?)
    const operand = Operand.init(VirtualReg{ .typ = types.I8, .index = 5 }, .use, .phys_reg, .early);
    try std.testing.expectEqual(@as(u32, 5), operand.vregIndex());
    try std.testing.expectEqual(LocationConstraint.phys_reg, operand.locationConstraints());
    try std.testing.expectEqual(AccessType.use, operand.accessType());
    try std.testing.expectEqual(RegClass.int, operand.regclass());
    try std.testing.expectEqual(OperandUseTiming.early, operand.operandUse());
}
