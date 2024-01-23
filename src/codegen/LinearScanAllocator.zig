//! Even though linear scan allocators are known to be the worst of every world possible, this is just so we can test the final output.
const std = @import("std");

const Abi = @import("Abi.zig");
const PhysicalReg = @import("regalloc.zig").PhysicalReg;
const Operand = @import("regalloc.zig").Operand;

const LinearScanAllocator = @This();

const VirtualReg = @import("regalloc.zig").VirtualReg;
const RegClass = @import("regalloc.zig").RegClass;
const LocationConstraint = @import("regalloc.zig").LocationConstraint;
const LiveRange = @import("regalloc.zig").LiveRange;
const LiveBundle = @import("regalloc.zig").LiveBundle;
const regalloc = @import("regalloc.zig");
const Allocation = @import("regalloc.zig").Allocation;
const AllocatedLiveBundle = regalloc.AllocatedLiveBundle;

const PhysAllocatedLiveBundle = struct {
    bundle: LiveBundle,
    preg: PhysicalReg,
};

allocations: std.ArrayList(AllocatedLiveBundle),
active: std.ArrayList(PhysAllocatedLiveBundle),
inactive: std.ArrayList(PhysAllocatedLiveBundle),
unhandled: std.ArrayList(LiveBundle),

pub fn init(allocator: std.mem.Allocator) LinearScanAllocator {
    return LinearScanAllocator{
        .allocations = std.ArrayList(AllocatedLiveBundle).init(allocator),
        .active = std.ArrayList(PhysAllocatedLiveBundle).init(allocator),
        .inactive = std.ArrayList(PhysAllocatedLiveBundle).init(allocator),
        .unhandled = std.ArrayList(LiveBundle).init(allocator),
    };
}

pub fn deinit(self: *LinearScanAllocator) void {
    self.allocations.deinit();
    self.active.deinit();
    self.inactive.deinit();
    // self.unhandled.deinit();
}

pub fn reset(self: *LinearScanAllocator) void {
    self.allocations.clearRetainingCapacity();
    self.active.clearRetainingCapacity();
    self.inactive.clearRetainingCapacity();
    self.unhandled.clearRetainingCapacity();
}

// `intervals` has to be ordered by liverange's start
pub fn run(
    self: *LinearScanAllocator,
    allocator: std.mem.Allocator,
    intervals: []const LiveBundle,
    abi: Abi,
) !void {
    self.unhandled = std.ArrayList(LiveBundle).fromOwnedSlice(allocator, @constCast(intervals));
    std.mem.reverse(LiveBundle, self.unhandled.items);

    while (self.unhandled.popOrNull()) |current| {
        var idx: usize = 0;
        for (self.active.items) |interval| {
            if (interval.bundle.end < current.start) {
                // remove interval from active
                const done = self.active.orderedRemove(idx);
                try self.allocations.append(AllocatedLiveBundle{
                    .bundle = done.bundle,
                    .allocation = .{ .preg = done.preg },
                });
            } else if (!interval.bundle.intersects(current)) {
                // move from active to inactive
                try self.inactive.append(self.active.orderedRemove(idx));
            } else {
                idx += 1;
            }
        }

        idx = 0;
        for (self.inactive.items) |interval| {
            if (interval.bundle.end < current.start) {
                // remove from inactive
                const stuff = self.inactive.orderedRemove(idx);
                try self.allocations.append(AllocatedLiveBundle{
                    .bundle = stuff.bundle,
                    .allocation = .{ .preg = stuff.preg },
                });
            } else if (interval.bundle.intersects(current)) {
                // move from inactive to active
                try self.active.append(self.inactive.orderedRemove(idx));
            } else {
                idx += 1;
            }
        }

        switch (current.constraints) {
            .stack => {
                // no need to do anything apart from adding to the list
                try self.allocations.append(AllocatedLiveBundle{
                    .bundle = current,
                    .allocation = .stack,
                });

                continue;
            },
            .fixed_reg => |preg| {
                try self.active.append(PhysAllocatedLiveBundle{
                    .bundle = current,
                    .preg = preg,
                });

                try self.allocations.append(AllocatedLiveBundle{
                    .bundle = current,
                    .allocation = .{ .preg = preg },
                });

                continue;
            },
            else => {},
        }

        try self.assignAllocateRegOrStack(allocator, current, abi);
    }

    for (self.active.items) |interval| {
        try self.allocations.append(AllocatedLiveBundle{
            .bundle = interval.bundle,
            .allocation = .{ .preg = interval.preg },
        });
    }

    for (self.inactive.items) |interval| {
        try self.allocations.append(AllocatedLiveBundle{
            .bundle = interval.bundle,
            .allocation = .{ .preg = interval.preg },
        });
    }
}

pub fn assignAllocateRegOrStack(
    self: *LinearScanAllocator,
    allocator: std.mem.Allocator,
    current: LiveBundle,
    abi: Abi,
) !void {
    var free_until = std.AutoArrayHashMap(PhysicalReg, usize).init(allocator);
    defer free_until.deinit();

    const pregs = abi.getPregsByRegClass(current.class()).?;

    try free_until.ensureTotalCapacity(pregs.len);

    for (pregs) |preg| {
        try free_until.put(preg, std.math.maxInt(usize));
    }

    // initialize free_until for each preg.

    // zero if active
    for (self.active.items) |interval| {
        if (interval.bundle.class() == current.class()) {
            try free_until.put(interval.preg, 0);
        }
    }

    // and the next intersection of current and the interval if inactive.
    for (self.inactive.items) |interval| {
        if (interval.bundle.class() == current.class() and interval.bundle.intersects(current)) {
            try free_until.put(interval.preg, @max(interval.bundle.start, current.start));
        }
    }

    // add the intersection with fixed-reg ranges.
    for (self.unhandled.items) |interval| {
        if (interval.class() == current.class() and interval.intersects(current)) {
            switch (interval.constraints) {
                .fixed_reg => |preg| try free_until.put(preg, @max(interval.start, current.start)),
                else => {},
            }
        }
    }

    const max_free_index = std.mem.indexOfMax(usize, free_until.values());
    const max_free = free_until.values()[max_free_index];

    if (max_free == 0) {
        // no regs available
        return self.assignAllocateBlockedReg(current);
    }

    const found = free_until.keys()[max_free_index];

    if (current.end < max_free) {
        // reg's next live section is after current's,
        // we can allocate a reg for the whole interval.
        return self.active.append(PhysAllocatedLiveBundle{
            .bundle = current,
            .preg = found,
        });
    }

    try self.allocations.append(AllocatedLiveBundle{
        .bundle = .{
            .ranges = current.ranges,
            .start = current.start,
            .end = max_free,
            .constraints = current.constraints,
        },
        .allocation = .{ .preg = found },
    });

    @panic("yay");
    // std.debug.print("die", .{});
    // const after_split = LiveRange{
    //     .start = max_free + 1,
    //     .end = current.end,
    // };
    //
    // try self.insertToUnhandled(after_split);
}

fn insertToUnhandled(self: *LinearScanAllocator, live_range: LiveRange) !void {
    // wouldn't this always go to 0?
    var min: usize = 0;
    var max: usize = self.unhandled.items.len;

    while (min <= max) {
        const mid = (min + max) / 2;
        if (mid < live_range.start) {
            min = mid + 1;
        } else if (mid > live_range.start) {
            max = mid - 1;
        } else {
            break;
        }
    }

    try self.unhandled.insert((min + max) / 2, live_range);
}

/// requires a and b to intersect; otherwise, the output is wrong.
fn intersectionWeight(a: LiveBundle, b: LiveBundle) usize {
    var i: usize = 0;
    var j: usize = 0;
    var weight: usize = 0;

    while (i < a.ranges.len and j < b.ranges.len) {
        const aw = a.ranges[i];
        const bw = b.ranges[j];

        if (regalloc.rangesIntersect(aw, bw.start, bw.end)) {
            weight += @min(a.end, b.end) - @max(a.start, b.start);
        }

        if (a.end < b.start) {
            i += 1;
        } else {
            j += 1;
        }
    }

    return weight;
}

fn assignAllocateBlockedReg(
    self: *LinearScanAllocator,
    current: LiveBundle,
) !void {
    // NOTE: I don't want to store every use, so I can't do distance-to-next-use.
    // I'm using here a really naive heuristic: the length of the live range.
    // This means the allocator is really bad at allocating for functions that have
    // both long-lived and short-lived intervals together.

    // calculate spill weight (cost) for current
    // pretty much winged everything here
    const current_spill_cost: usize = if (current.constraints == .phys_reg) blk: {
        break :blk std.math.maxInt(usize);
    } else blk: {
        break :blk current.calculateSpillcost() * 4 / 5;
    };

    var min_active_cost: usize = std.math.maxInt(usize);
    var min_cost_idx: ?usize = null;

    // calculate spill weight (cost) for the intervals blocking current
    for (self.active.items, 0..) |interval, i| {
        if (interval.bundle.class() == current.class()) {
            const interference = intersectionWeight(current, interval.bundle); // should probably do this with all active intervals, but eh.

            const cost: usize = if (interval.bundle.constraints == .phys_reg) blk: {
                break :blk std.math.maxInt(usize);
            } else blk: {
                break :blk interval.bundle.calculateSpillcost() - interference * 2 / 3;
            };

            if (cost < min_active_cost) {
                min_active_cost = cost;
                min_cost_idx = i;
            }
        }
    }

    if (min_active_cost < current_spill_cost) {
        // spill min_cost's range
        const interval = self.active.orderedRemove(min_cost_idx.?);
        try self.allocations.append(AllocatedLiveBundle{
            .bundle = interval.bundle,
            .allocation = .stack,
        });

        try self.active.append(PhysAllocatedLiveBundle{
            .bundle = current,
            .preg = interval.preg,
        });
    } else if (current_spill_cost != std.math.maxInt(usize)) {
        // spill current
        try self.allocations.append(AllocatedLiveBundle{
            .bundle = current,
            .allocation = .stack,
        });
    } else {
        @panic("Unrealistic requirements.");
    }
}

test "poop" {
    const allocator = std.testing.allocator;

    var reg_allocator = LinearScanAllocator.init(allocator);
    defer reg_allocator.deinit();

    var bundles = &.{
        LiveBundle{
            .ranges = &.{
                LiveRange{
                    .start = 0,
                    .end = 3,
                    .vreg = VirtualReg{ .class = .int, .index = 0 },
                    .spill_cost = 2,
                },
                LiveRange{
                    .start = 6,
                    .end = 7,
                    .vreg = VirtualReg{ .class = .int, .index = 0 },
                    .spill_cost = 7,
                },
            },
            .start = 0,
            .constraints = .none,
            .end = 7,
        },
        LiveBundle{
            .ranges = &.{
                LiveRange{
                    .start = 4,
                    .end = 5,
                    .vreg = VirtualReg{ .class = .int, .index = 2 },
                    .spill_cost = 3,
                },
                LiveRange{
                    .start = 7,
                    .end = 10,
                    .vreg = VirtualReg{ .class = .int, .index = 2 },
                    .spill_cost = 5,
                },
            },
            .start = 4,
            .constraints = .none,
            .end = 10,
        },
        LiveBundle{
            .ranges = &.{
                LiveRange{
                    .start = 6,
                    .end = 6,
                    .spill_cost = 5,
                    .vreg = VirtualReg{ .class = .int, .index = 1 },
                },
            },
            .constraints = .none,
            .start = 6,
            .end = 6,
        },
        LiveBundle{
            .ranges = &.{
                LiveRange{
                    .start = 10,
                    .end = 30,
                    .spill_cost = 1,
                    .vreg = VirtualReg{ .class = .int, .index = 3 },
                },
            },
            .constraints = .none,
            .start = 10,
            .end = 30,
        },
    };

    const start = try std.time.Instant.now();
    try reg_allocator.run(
        allocator,
        bundles,
        Abi{
            .int_pregs = &.{
                PhysicalReg{ .class = .int, .encoding = 0 },
                PhysicalReg{ .class = .int, .encoding = 1 },
            },
            .float_pregs = null,
            .vector_pregs = null,
        },
    );

    std.debug.print("{}\n\n", .{std.fmt.fmtDuration((try std.time.Instant.now()).since(start))});
    for (reg_allocator.allocations.items) |allocation| {
        std.debug.print("{any}\n\n", .{allocation});
    }
}
