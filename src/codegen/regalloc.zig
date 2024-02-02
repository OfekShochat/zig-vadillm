//! This is heavily inspired by Cranelift's regalloc2.

const std = @import("std");
const codegen = @import("codegen.zig");
const Abi = @import("Abi.zig");

pub const RegClass = enum(u2) {
    int,
    float,
    vector,
};

pub const RegAllocError = error{
    ContradictingConstraints,
};

pub const RegisterAllocator = struct {
    pub const VTable = struct {
        run: *const fn (self: *anyopaque, []const *LiveRange) (RegAllocError || std.mem.Allocator.Error)!Solution,
        getIntermediateSolution: *const fn (self: *anyopaque) std.mem.Allocator.Error!Solution,
    };

    vptr: *anyopaque,
    vtable: VTable,

    pub fn run(self: *RegisterAllocator, allocator: std.mem.Allocator, abi: Abi, live_ranges: []const *LiveRange) !Solution {
        if (self.vtable.run(self.vptr, live_ranges)) |output| {
            std.log.debug("regalloc found a solution:", .{});
            try output.visualize(allocator, abi, std.io.getStdErr());
            return output;
        } else |err| {
            std.log.debug("regalloc encountered an error: {}.", .{err});
            const inter_out = try self.vtable.getIntermediateSolution(self.vptr);
            try inter_out.visualize(allocator, abi, std.io.getStdErr());
            return err;
        }
    }
};

pub const VirtualReg = struct {
    class: RegClass,
    index: u32,

    pub fn format(
        self: VirtualReg,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const class_str = switch (self.class) {
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

    const Context = struct {
        row_buf: []u8,
        vis: *SolutionVisualizer,
        active: *std.ArrayList(LiveRange),
        pregs: []const PhysicalReg,
        offsets: std.AutoHashMap(PhysicalReg, usize),

        // fn retireActive(self: Context)
    };

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

        for (pregs, 0..) |preg, i| {
            _ = try std.fmt.bufPrint(row_buf[i * 5 ..], "{}", .{preg});
        }

        row_buf[row_buf.len - 1] = '\n';
        try writer.writeAll(row_buf);

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

            row_buf[stack_offset - 1] = '\n';
            try writer.writeAll(row_buf[0..stack_offset]);
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

        return self.format(writer, allocator, try allocator.alloc(u8, self.max_width * 5), pregs, &active, offsets);
    }
};

pub const Solution = struct {
    allocations: []const LiveRange,
    stitches: Stitch,

    pub fn deinit(self: *Solution, allocator: std.mem.Allocator) void {
        allocator.free(self.allocations);
    }

    pub fn visualize(self: Solution, allocator: std.mem.Allocator, abi: Abi, writer: anytype) !void {
        var visualizer = SolutionVisualizer.init(allocator, abi);

        for (self.allocations) |range| {
            try visualizer.add(range);
        }

        try visualizer.print(writer);
        visualizer.arena.deinit();
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
                (@as(u32, @intFromEnum(vreg.class)) << 20) |
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
    stack: void,
    preg: PhysicalReg,
};

pub const Stitch = struct {
    codepoint: usize,
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

    pub fn compareFn(self: LiveRange, other: LiveRange) std.math.Order {
        return switch (self.start.compareFn(other.start)) {
            .eq => self.end.compareFn(other.end),
            else => |e| e,
        };
    }

    pub fn compareFnConst(_: void, self: *const LiveRange, other: *const LiveRange) std.math.Order {
        return switch (self.start.compareFn(other.start)) {
            .eq => self.end.compareFn(other.end),
            else => |e| e,
        };
    }

    pub fn lessThan(_: void, self: LiveRange, other: LiveRange) bool {
        return self.compareFn(other) == .lt;
    }

    pub fn rawEnd(self: LiveRange) usize {
        return self.end.point;
    }

    pub fn isMinimal(self: LiveRange) bool {
        return std.meta.eql(self.start.getLate(), self.end) or std.meta.eql(self.start.getNextInst(), self.end);
    }

    pub fn class(self: LiveRange) RegClass {
        return self.live_interval.vreg.class;
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

pub const LiveBundle = struct {
    // every vreg in ranges should be equivalent - holding/referencing
    // the same value, while not overlapping.
    ranges: []const LiveRange,
    constraints: LocationConstraint, // the maximum constraints
    start: usize,
    end: usize,

    pub fn calculateSpillcost(self: LiveBundle) usize {
        var sum: usize = 0;
        for (self.ranges) |range| {
            sum += range.spill_cost;
        }
        return sum;
    }

    pub fn class(self: LiveBundle) RegClass {
        // I can assume ranges is non null
        return self.ranges[0].vreg.class;
    }

    pub fn intersects(self: LiveBundle, other: LiveBundle) bool {
        if (self.end < other.start or other.end < self.start) {
            return false;
        }

        var i: usize = 0;
        var j: usize = 0;

        while (i < self.ranges.len and j < other.ranges.len) {
            const a = self.ranges[i];
            const b = other.ranges[j];

            if (rangesIntersect(a, b.start, b.end)) {
                return true;
            }

            if (a.end < b.start) {
                i += 1;
            } else {
                j += 1;
            }
        }

        return false;
    }
};

pub const AllocatedLiveBundle = struct {
    bundle: LiveBundle,
    allocation: Allocation,
};

// TODO: find a better name
pub fn earlyLateToIndex(early_late: usize) usize {
    return early_late / 2;
}

pub fn encodeEarlyLate(index: usize, timing: OperandUseTiming) usize {
    return index * 2 + @intFromEnum(timing);
}

pub fn calculateStitches(allocator: std.mem.Allocator, allocated_ranges: []LiveInterval) ![]const Stitch {
    std.sort.heap(AllocatedLiveBundle, allocated_ranges, void{}, LiveRange.compareFn);

    var last_used = std.AutoHashMap(VirtualReg, *LiveInterval).init(allocator);
    defer last_used.deinit();

    var stitches = std.ArrayList(Stitch).init(allocator);

    // NOTE: live ranges are live always until they are dead,
    // and that's why we can do this easily. Remember, the
    // ranges are still in early/late encoding.
    for (allocated_ranges) |allocated_interval| {
        for (allocated_interval.ranges) |range| {
            if (last_used.get(range.vreg)) |last_bundle| {
                try stitches.append(Stitch{
                    .codepoint = allocated_interval.bundle.start,
                    .from = last_bundle.allocation,
                    .to = allocated_interval.preg,
                });
            }
        }
    }

    return stitches.toOwnedSlice();
}

// pub fn allocatedBundlesLessThan(_: void, lhs: AllocatedLiveBundle, rhs: AllocatedLiveBundle) bool {
//     return lhs.live_range.from < rhs.live_range.from;
// }
//
// pub fn calculateStitches(allocator: std.mem.Allocator, allocated_bundles: []AllocatedLiveBundle) ![]const Stitch {
//     std.sort.heap(AllocatedLiveBundle, allocated_bundles, void{}, allocatedBundlesLessThan);
//
//     var last_used = std.AutoHashMap(VirtualReg, *LiveBundle).init(allocator);
//     defer last_used.deinit();
//
//     var stitches = std.ArrayList(Stitch).init(allocator);
//
//     // NOTE: live ranges are live always until they are dead,
//     // and that's why we can do this easily. Remember, the
//     // ranges are still in early/late encoding.
//     for (allocated_bundles) |allocated_bundle| {
//         for (allocated_bundle.bundle.ranges) |range| {
//             if (last_used.get(range.vreg)) |last_bundle| {
//                 try stitches.append(Stitch{
//                     .codepoint = allocated_bundle.bundle.start,
//                     .from = last_bundle.allocation,
//                     .to = allocated_bundle.allocation,
//                 });
//             }
//         }
//     }
//
//     return stitches.toOwnedSlice();
// }

test "regalloc.Operand" {
    // use constants and also make a test that should panic (index too high?)
    const operand = Operand.init(VirtualReg{ .class = .int, .index = 5 }, .use, .phys_reg, .early);
    try std.testing.expectEqual(@as(u32, 5), operand.vregIndex());
    try std.testing.expectEqual(LocationConstraint.phys_reg, operand.locationConstraints());
    try std.testing.expectEqual(AccessType.use, operand.accessType());
    try std.testing.expectEqual(RegClass.int, operand.regclass());
    try std.testing.expectEqual(OperandUseTiming.early, operand.operandUse());
}
