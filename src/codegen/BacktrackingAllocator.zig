const std = @import("std");
const regalloc = @import("regalloc.zig");

const IntervalTree = @import("interval_tree.zig").IntervalTree;
const Abi = @import("Abi.zig");

const Self = @This();

const hint_weight = 20;

fn priorityCompare(_: void, lhs: regalloc.LiveRange, rhs: regalloc.LiveRange) std.math.Order {
    if (lhs.spill_cost > rhs.spill_cost) {
        return .gt;
    }

    if (lhs.spill_cost < rhs.spill_cost) {
        return .lt;
    }

    return .eq;
}

queue: std.PriorityQueue(*regalloc.LiveRange, void, priorityCompare),
interval_arena: std.heap.ArenaAllocator,

live_intervals: LiveIntervalContainer,
// int, float, vec
live_unions: std.EnumMap(regalloc.RegClass, IntervalTree(*regalloc.LiveRange)),
abi: Abi,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, abi: Abi) Self {
    var arena = std.ArenaAllocator.init(allocator);
    var live_unions = std.EnumMap(regalloc.RegClass, *IntervalTree(regalloc.LiveRange)).init(allocator);

    inline for (std.meta.fields(regalloc.RegClass)) |class| {
        try live_unions.put(
            class,
            IntervalTree(*regalloc.LiveRange).initWithArena(arena),
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
        if (try self.tryAssignMightEvict(live_range)) |best_preg| {
            continue;
        }

        if (try self.trySplit(live_range)) |best_preg| {
            continue;
        }

        // maybe add to second-chance allocation queue?
        try self.spill(live_range);
    }
}

fn tryAssignMightEvict(self: *Self, live_range: *regalloc.LiveRange) !?regalloc.PhysicalReg {
    const interferences = std.ArrayList(*regalloc.LiveRange).init(self.allocator);
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

    if (live_range.live_interval.preg) |hint| {
        // We have a hint; use it if available.
        // Otherwise, let the splitter do the work.
        if (avail_pregs.get(hint).?) {
            return preg;
        }
    } else {
        // If there's no hint, any preg that is available 
        // for the whole live-range is great.
        var iter = avail_pregs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*) {
                return entry.key_ptr.*;
            }
        }
    }

    return self.tryEvict(live_range, live_union, &interference.items);
}

fn tryEvict(
    self: *Self,
    live_range: *regalloc.LiveRange,
    live_union: *IntervalTree(regalloc.LiveRange),
    interferences: []const regalloc.LiveRange,
) !?regalloc.PhysicalReg {
    // NOTE: `live_range` should have a lower spill cost
    // than the ones in `interferences`, as we are allocating
    // from the most costly to the least.

    const EvictionCostDetails = struct {
        total_spill_cost: usize,
        interference_count: usize,
    };

    // 1. Calculate costs and, if a hint wasn't found,
    // choose a preg to evict based on the `interferences`.

    var preg_map = std.AutoArrayHashMap(regalloc.PhysicalReg, InterferenceCostDetails).init(self.allocator);
    defer preg_map.deinit();

    // 1.1 Populate the map with eviction costs.
    for (interferences) |interference| {
        var details = preg_map.get(
            interference.live_interval.preg.?,
        ) orelse EvictionCostDetails{ .total_spill_cost = 0, .interference_count = 0 };

        details.total_spill_cost += interference.spill_cost;

        try preg_map.put(interference.preg, details);
    }

    // 1.2 Either use the hint or find the minimal interfering preg to evict.
    var min_cost = std.math.maxInt(usize);
    var chosen_preg: ?regalloc.PhysicalReg = null;

    if (live_range.live_interval.preg) |hint| {
        chosen_preg = hint;
        min_cost = preg_map.get(hint).?;
    } else {
        var iter = preg_map.iterator();
        while (iter.next()) |entry| {
            const cost = entry.value_ptr.total_spill_cost;

            if (cost < min_cost) {
                min_cost = cost;
                chosen_preg = entry.key_ptr;
            }
        }
    }

    // We only evict spill costs less than ours, so that we are guaranteed a solution.
    if (live_range.spill_cost < min_cost) {
        return null;
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

fn trySplit(self: *Self, live_range: *regalloc.LiveRange) !?regalloc.PhysicalReg {
    const interferences = std.ArrayList(*regalloc.LiveRange).init(self.allocator);
    defer interferences.deinit();

    try interferences.ensureTotalCapacity(4);

    var live_union = self.live_unions.getPtr(live_range.class);
    try live_union.search(live_range, &interferences);

    std.debug.assert(interferences.items.len > 0);

    var first_point_of_intersection = interferences.items[0];

    for (interferences.items) |interference| {
        if (interference.start > live_range.start and interference.start < first_point_of_intersection) {
            first_point_of_intersection = interference.start;
        }
    }

    // split live interval
    const split_ranges = splitAt(first_point_of_intersection, live_range.live_interval);

    try self.queue.add(split_ranges[0]);
    try self.queue.add(split_ranges[1]);
}

fn splitAt(at: usize, live_interval: *regalloc.LiveInterval) ![2]LiveInterval {
    const allocator = self.interval_arena.allocator();

    var split_intervals = try allocator.alloc(regalloc.LiveInterval, 2);

    for (live_interval.ranges, 0..) |range, i| {
        if (range.start < at and at < range.end) {
            var a_ranges = try std.mem.copy(allocator, live_interval.ranges[0..i + 1]);
            var b_ranges = try std.mem.copy(allocator, live_interval.ranges[i..]);

            a_ranges[i] = .{
                .start = range.start,
                .end = at,
            };
            
            b_ranges[0] = .{
                .start = at + 1,
                .end = range.end,
            };

            split_intervals[0].ranges = a_ranges;
            split_intervals[1].ranges = b_ranges;

            allocator.free(live_interval.ranges);

            break;
        }
    } else {
        return error.AtDoesNotIntersect;
    }

    interval_a.

    allocator.destroy(live_interval);

    reutrn intervals;
}

// this is not comparable to `live_range`'s cost, so I can't use it in the cost calc:
// + interference_count_weight * entry.value_ptr.interference_count;