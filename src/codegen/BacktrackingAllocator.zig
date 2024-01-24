const std = @import("std");
const regalloc = @import("regalloc.zig");

const IntervalTree = @import("interval_tree.zig").IntervalTree;
const Abi = @import("Abi.zig");

const Self = @This();

fn priorityCompare(_: void, lhs: regalloc.LiveRange, rhs: regalloc.LiveRange) std.math.Order {
    if (lhs.spill_cost > rhs.spill_cost) {
        return .gt;
    }

    if (lhs.spill_cost < rhs.spill_cost) {
        return .lt;
    }

    return .eq;
}

queue: std.PriorityQueue(regalloc.LiveRange, void, priorityCompare),

// int, float, vec
live_unions: std.EnumMap(regalloc.RegClass, IntervalTree(regalloc.LiveRange)),
abi: Abi,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, abi: Abi) Self {
    var arena = std.ArenaAllocator.init(allocator);
    var live_unions = std.EnumMap(regalloc.RegClass, IntervalTree(regalloc.LiveRange)).init(allocator);

    inline for (std.meta.fields(regalloc.RegClass)) |class| {
        try live_unions.put(
            class,
            IntervalTree(regalloc.LiveRange).initWithArena(arena),
        );
    }

    return Self{
        .queue = std.PriorityQueue(regalloc.LiveRange, void, priorityCompare).init(allocator),
        .live_unions = live_unions,
        .abi = abi,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.queue.deinit();
    self.live_unions.deinit();
}

pub fn run(self: *Self) !regalloc.Output {
    while (self.queue.removeOrNull()) |live_range| {
        if (try self.tryAssignAndPossiblyEvict(live_range)) {
            continue;
        }

        if (try self.trySplit(live_range)) {
            continue;
        }

        try self.spill(live_range);
    }
}

fn tryAssignAndPossiblyEvict(self: *Self, live_range: regalloc.LiveRange) !?regalloc.PhysicalReg {
    const interferences = std.ArrayList(regalloc.LiveRange).init(self.allocator);
    defer interferences.deinit();

    try interferences.ensureTotalCapacity(4);

    var live_union = self.live_unions.getPtr(live_range.class);
    try live_union.search(live_range, &interferences);

    var avail_pregs = std.AutoArrayHashMap(PhysicalReg, bool).init(self.allocator);

    for (self.abi.getPregsByRegClass(live_range.class)) |preg| {
        try avail_pregs.put(preg, true);
    }

    for (interferences.items) |interference| {
        const unavail_preg = interference.allocated_preg orelse @panic("`live_union` should contain only allocated ranges.");
        avail_pregs.put(unavail_preg, false);
    }

    // We have a hint. This is equivalent to using split-able bundles.
    if (live_range.preg) |hint| {
        if (avail_pregs.get(hint).?) {
            return hint;
        }
    }

    // If any preg is available for the whole live-range, use it.
    var iter = avail_pregs.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.*) {
            return entry.key_ptr.*;
        }
    }

    return self.tryEvict(live_range, live_union, &interference.items);
}

fn tryEvict(
    self: *Self,
    live_range: regalloc.LiveRange,
    live_union: *IntervalTree(regalloc.LiveRange),
    interferences: []const regalloc.LiveRange,
) !?regalloc.PhysicalReg {
    // NOTE: `live_range` should have a lower spill cost
    // than the ones in `interferences`, as we are allocating
    // from the most costly to the least.

    const InterferenceCostDetails = struct {
        total_spill_cost: usize,
        interference_count: usize,
    };
    
    // 1. Choose a preg to evict based on the `interferences`.

    var preg_map = std.AutoArrayHashMap(regalloc.PhysicalReg, InterferenceCostDetails).init(self.allocator);
    defer preg_map.deinit();

    // 1.1 Populate the map with spill cost and interference count.
    for (interferences) |interference| {
        var details = try preg_map.getOrPut(
            interference.preg,
            InterferenceCostDetails{ .total_spill_cost = 0, .interference_count = 0 },
        );
        details.total_spill_cost += interference.spill_cost;
        details.interference_count += @min(interference.end, live_range.end) - @max(interference.start, live_range.start);
        try preg_map.put(interference.preg, details);
    }

    // 1.2 Find the minimal interfering preg to evict.
    var min_cost = std.math.maxInt(usize);
    var chosen_preg: ?regalloc.PhysicalReg = null;

    for (preg_map.entries()) |entry| {
        if (entry.value.total_spill_cost < min_cost) {
            min_cost = entry.value.total_spill_cost;
            chosen_preg = entry.key;
        }
    }

    // 2. Evict all `interferences` of the chosen preg.
    for (interferences) |interference| {
        if (interference.preg == chosen_preg) {
            try live_union.delete(interference);
            try self.queue.add(interference);
        }
    }

    return chosen_preg;
}