//! A backtracking register allocator.
//! It uses a priority queue to first visit higher spill-cost ranges
//!
//! Note that late-uses are not supported, as splitting would be more complex with them.

const std = @import("std");
const regalloc = @import("regalloc.zig");
const types = @import("../types.zig");
const codegen = @import("../codegen.zig");

const IntervalTree = @import("interval_tree.zig").IntervalTree;
const MachineFunction = @import("MachineFunction.zig");
const SpillCostCalc = @import("SpillCostCalc.zig");
const CodePoint = @import("CodePoint.zig");
const Abi = @import("Abi.zig");

const Self = @This();

const spill_cost_weight = 2;
const interference_cost_weight = 3;

const Error = regalloc.RegAllocError || std.mem.Allocator.Error;

fn priorityCompare(_: void, lhs: *regalloc.LiveRange, rhs: *regalloc.LiveRange) std.math.Order {
    if (lhs.spill_cost > rhs.spill_cost) {
        return .lt;
    }

    if (lhs.spill_cost < rhs.spill_cost) {
        return .gt;
    }

    return .eq;
}

queue: std.PriorityQueue(*regalloc.LiveRange, void, priorityCompare),
second_chance: std.PriorityQueue(*regalloc.LiveRange, void, priorityCompare),
second_chance_mode: bool = false,

// int, float, vec
live_unions: std.EnumMap(regalloc.RegClass, IntervalTree(*regalloc.LiveRange)),
abi: Abi,
allocator: std.mem.Allocator,
spilled: std.ArrayList(*regalloc.LiveRange),

/// `allocator` should be in an arena; this allocator is very sloppy in terms of memory management.
pub fn init(allocator: std.mem.Allocator, abi: Abi) Self {
    var live_unions = std.EnumMap(regalloc.RegClass, IntervalTree(*regalloc.LiveRange)){};

    inline for (std.meta.fields(regalloc.RegClass)) |class| {
        live_unions.put(
            @field(regalloc.RegClass, class.name),
            // will this allocator when interval tree deinits deinit everything?
            IntervalTree(*regalloc.LiveRange).init(allocator),
        );
    }

    return Self{
        .queue = std.PriorityQueue(*regalloc.LiveRange, void, priorityCompare).init(allocator, void{}),
        .second_chance = std.PriorityQueue(*regalloc.LiveRange, void, priorityCompare).init(allocator, void{}),
        .live_unions = live_unions,
        .abi = abi,
        .allocator = allocator,
        .spilled = std.ArrayList(*regalloc.LiveRange).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.queue.deinit();
    self.second_chance.deinit();

    for (&self.live_unions.values) |*live_union| {
        live_union.deinit();
    }
}

fn runOne(self: *Self, live_range: *regalloc.LiveRange, spillcost_calc: *SpillCostCalc) !void {
    // 1. If we don't have to assign a preg, just spill.
    if (live_range.constraints() == .stack) {
        return self.spill(live_range);
    }

    // 2. Find all allocated live ranges that intersect with `live_range`.
    var interferences = std.ArrayList(*regalloc.LiveRange).init(self.allocator);
    defer interferences.deinit();

    try interferences.ensureTotalCapacity(4);

    var live_union = self.live_unions.getPtrAssertContains(live_range.vreg.class());
    live_union.search(live_range, &interferences) catch {}; // error.NoSuchKey is completely OK here.

    // 3. Try to assign a preg if available, otherwise try to evict.
    if (try self.tryAssignMightEvict(live_range, interferences.items)) |best_preg| {
        return self.assignPregToLiveInterval(live_range.live_interval, best_preg);
    }

    // If there are no interferences, we should have returned already.
    std.debug.assert(interferences.items.len > 0);

    // 4. If evicting fails, meaning evicting the interferences is more
    // costly than leaving it as-is, we try to split the live range in two.
    const split = try self.trySplitAndRequeue(live_range, interferences.items, spillcost_calc);

    if (!live_range.spillable()) return error.ContradictingConstraints;

    // If splitting was unsuccessful, meaning the live range is
    // minimal -- spanning only one instruction -- we either put
    // it into the second-chance allocation queue or spill it.
    if (!split) {
        try self.spill(live_range);
    }
}

pub fn run(self: *Self, live_ranges: []const *regalloc.LiveRange, spillcost_calc: *SpillCostCalc) ![]regalloc.LiveRange {
    try self.queue.addSlice(live_ranges);

    while (self.queue.removeOrNull()) |live_range| {
        try self.runOne(live_range, spillcost_calc);
    }

    // is there a better way of doing this?
    self.second_chance_mode = true;

    while (self.second_chance.removeOrNull()) |live_range| {
        try self.runOne(live_range, spillcost_calc);
    }

    return try self.calculateAllocations();
}

pub fn getIntermediateSolution(self: *Self) std.mem.Allocator.Error![]regalloc.LiveRange {
    return self.calculateAllocations();
}

fn calculateAllocations(self: *Self) ![]regalloc.LiveRange {
    var ranges = std.ArrayList(regalloc.LiveRange).init(self.allocator);

    var used = std.ArrayList(*regalloc.LiveRange).init(self.allocator);
    defer used.deinit();

    for (self.live_unions.values) |live_union| {
        try live_union.collect(&used);
    }

    for (used.items) |range| {
        try ranges.append(range.*);
    }

    for (self.spilled.items) |spilled_range| {
        try ranges.append(spilled_range.*);
    }

    return ranges.toOwnedSlice();
}

fn spill(self: *Self, live_range: *regalloc.LiveRange) Error!void {
    // TODO(ghostway): See if second chance allocation is worth it.
    if (!self.second_chance_mode) {
        return self.second_chance.add(live_range);
    }

    live_range.live_interval.allocation = .{ .stack = null };
    try self.spilled.append(live_range);
}

fn assignPregToLiveInterval(self: *Self, live_interval: *regalloc.LiveInterval, preg: regalloc.PhysicalReg) Error!void {
    var live_union = self.live_unions.getPtrAssertContains(live_interval.ranges[0].class()); // The class should be the same.
    for (live_interval.ranges) |range| {
        live_union.insert(range) catch return error.ContradictingConstraints;
    }

    live_interval.allocation = .{ .preg = preg };
}

fn tryAssignMightEvict(self: *Self, live_range: *regalloc.LiveRange, interferences: []const *regalloc.LiveRange) Error!?regalloc.PhysicalReg {
    const live_union = self.live_unions.getPtrAssertContains(live_range.vreg.class());
    const pregs = self.abi.getPregsByRegClass(live_range.vreg.class());

    var avail_pregs = std.AutoArrayHashMap(regalloc.PhysicalReg, bool).init(self.allocator);
    try avail_pregs.ensureTotalCapacity(pregs.len);
    defer avail_pregs.deinit();

    for (pregs) |preg| {
        try avail_pregs.put(preg, true);
    }

    for (interferences) |interference| {
        const unavail_preg = interference.preg() orelse @panic("`live_union` should contain only preg allocated ranges.");
        try avail_pregs.put(unavail_preg, false);
    }

    if (live_range.preg()) |hint| {
        // We have a hint; use it if available.
        // Otherwise, let the splitter do the work.
        if (avail_pregs.get(hint).?) {
            return hint;
        }
    } else if (live_range.constraints() != .fixed_reg) {
        // If there's no hint, any preg that is available
        // for the whole live-range is great.
        var iter = avail_pregs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*) {
                return entry.key_ptr.*;
            }
        }
    } else {
        const reg = live_range.constraints().fixed_reg;
        try self.evictToMakeRoomFor(reg, live_union, interferences);

        return reg;
    }

    return self.tryEvict(live_range, live_union, interferences);
}

fn evictToMakeRoomFor(
    self: *Self,
    preg: regalloc.PhysicalReg,
    live_union: *IntervalTree(*regalloc.LiveRange),
    interferences: []const *regalloc.LiveRange,
) !void {
    for (interferences) |interference| {
        if (std.meta.eql(interference.preg(), preg)) {
            // TODO: print a backtrace.
            if (interference.constraints() == .fixed_reg) return error.ContradictingConstraints;

            interference.evicted_count += 1;
            interference.live_interval.allocation = null;

            live_union.delete(interference) catch @panic("`interferences` should exist in `live_union`.");
            try self.queue.add(interference);
        }
    }
}

fn tryEvict(
    self: *Self,
    live_range: *regalloc.LiveRange,
    live_union: *IntervalTree(*regalloc.LiveRange),
    interferences: []const *regalloc.LiveRange,
) !?regalloc.PhysicalReg {
    // NOTE: `live_range` should have a lower spill cost
    // than the ones in `interferences`, as we are allocating
    // from the most costly to the least.

    const EvictionCostDetails = struct {
        total_spill_cost: usize,
        interference_cost: usize,
        allocatable: bool,
    };

    // 1. Calculate costs and, if a hint wasn't found,
    // choose a preg to evict based on the `interferences`.

    var preg_map = std.AutoArrayHashMap(regalloc.PhysicalReg, EvictionCostDetails).init(self.allocator);
    defer preg_map.deinit();

    // 1.1 Populate the map with eviction costs.
    for (interferences) |interference| {
        var details = preg_map.get(
            interference.preg().?,
        ) orelse EvictionCostDetails{
            .total_spill_cost = 0,
            .interference_cost = 0,
            .allocatable = false,
        };

        details.allocatable = details.allocatable and interference.constraints() != .fixed_reg;
        details.total_spill_cost += interference.spill_cost;
        details.interference_cost += @min(live_range.rawEnd(), interference.rawEnd()) - @max(live_range.rawStart(), interference.rawStart());

        try preg_map.put(interference.preg().?, details);
    }

    // 1.2 Either use the hint or find the minimal interfering preg to evict.
    var min_cost: usize = std.math.maxInt(usize);
    var chosen_preg: ?regalloc.PhysicalReg = null;

    if (live_range.preg()) |hint| {
        chosen_preg = hint;
        min_cost = preg_map.get(hint).?.total_spill_cost;
    } else {
        var iter = preg_map.iterator();
        while (iter.next()) |entry| {
            if (!entry.value_ptr.allocatable) continue;

            const cost = entry.value_ptr.total_spill_cost * spill_cost_weight +
                entry.value_ptr.interference_cost * interference_cost_weight;

            if (cost < min_cost) {
                min_cost = cost;
                chosen_preg = entry.key_ptr.*;
            }
        }
    }

    // We only evict spill costs less than ours.
    if (live_range.spill_cost < min_cost) {
        return null;
    }

    // 2. Evict all `interferences` of the chosen preg.
    try self.evictToMakeRoomFor(chosen_preg.?, live_union, interferences);

    return chosen_preg;
}

fn trySplitAndRequeue(self: *Self, live_range: *regalloc.LiveRange, interferences: []const *regalloc.LiveRange, spillcost_calc: *SpillCostCalc) !bool {
    var first_point_of_intersection = CodePoint.invalidMax();

    for (interferences) |interference| {
        if (interference.start.isBefore(first_point_of_intersection)) {
            first_point_of_intersection = CodePoint{
                .point = @max(interference.start.point, live_range.start.point),
            };
        }
    }

    std.debug.assert(!std.meta.eql(first_point_of_intersection, CodePoint.invalidMax()));
    std.debug.assert(live_range.start.isBeforeOrAt(first_point_of_intersection) and live_range.end.isAfterOrAt(first_point_of_intersection));

    const split_result = try regalloc.splitAtLeaky(self.allocator, first_point_of_intersection, live_range.live_interval, spillcost_calc);

    if (split_result == null) {
        return false;
    }

    var live_union = self.live_unions.getPtrAssertContains(live_range.vreg.class());
    live_union.delete(split_result.?.split_range) catch {}; // error.NoSuchKey might be expected here.

    for (split_result.?.ranges) |*range| {
        try self.queue.add(range);
    }

    return true;
}

test "regalloc.simple allocations" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const abi = Abi{
        .int_pregs = &.{
            regalloc.PhysicalReg{ .class = .int, .encoding = 0 },
            // regalloc.PhysicalReg{ .class = .int, .encoding = 1 },
            // regalloc.PhysicalReg{ .class = .int, .encoding = 2 },
        },
        .float_pregs = &.{},
        .vector_pregs = &.{},
        .call_conv = .{
            .params = &.{
                regalloc.PhysicalReg{ .class = .int, .encoding = 0 },
            },
            .syscall_params = &.{
                regalloc.PhysicalReg{ .class = .int, .encoding = 0 },
            },
            .callee_saved = &.{
                regalloc.PhysicalReg{ .class = .int, .encoding = 0 },
            },
        },
    };

    var ranges = std.ArrayList(*regalloc.LiveRange).init(arena.allocator());

    var intervals = try arena.allocator().alloc(regalloc.LiveInterval, 3);

    // late uses are NOT permitted

    var live_ranges = [_]regalloc.LiveRange{
        .{
            .start = .{ .point = 10 },
            .end = .{ .point = 30 },
            .spill_cost = 1,
            .live_interval = &intervals[0],
            .vreg = regalloc.VirtualReg{ .typ = types.I8, .index = 0 },
            .uses = &.{ .{ .point = 14 }, .{ .point = 30 } },
        },
        .{
            .start = .{ .point = 10 },
            .end = .{ .point = 31 },
            .spill_cost = 10,
            .live_interval = &intervals[1],
            .vreg = regalloc.VirtualReg{ .typ = types.I16, .index = 1 },
            .uses = &.{ .{ .point = 20 }, .{ .point = 30 } },
        },
        .{
            .start = .{ .point = 0 },
            .end = .{ .point = 22 },
            .spill_cost = 3,
            .live_interval = &intervals[2],
            .vreg = regalloc.VirtualReg{ .typ = types.I8, .index = 2 },
            .uses = &.{ .{ .point = 4 }, .{ .point = 22 } },
        },
    };

    const constraints = [_]regalloc.LocationConstraint{
        .{ .fixed_reg = .{ .class = .int, .encoding = 0 } },
        .none,
        .none,
    };

    try ranges.append(&live_ranges[0]);
    try ranges.append(&live_ranges[1]);
    try ranges.append(&live_ranges[2]);

    for (0..live_ranges.len) |i| {
        var current_ranges = try arena.allocator().alloc(*regalloc.LiveRange, 1);
        current_ranges[0] = &live_ranges[i];
        intervals[i] = .{
            .ranges = current_ranges,
            .constraints = constraints[i],
            .allocation = null,
        };
    }

    _ = abi;
    // _ = try regalloc.runRegalloc(Self, arena.allocator(), abi, ranges.items);
}
