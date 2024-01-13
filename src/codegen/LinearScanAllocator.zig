//! Even though linear scan allocators are known to be the worst of every world possible, this is just so we can test the final output.

const std = @import("std");

const Abi = @import("Abi.zig");
// const MachineFunction = @import("MachineFunction.zig");
// const Liveness = @import("Liveness.zig");
const PhysicalReg = @import("regalloc.zig").PhysicalReg;
const Operand = @import("regalloc.zig").Operand;

const LinearScanAllocator = @This();

const VirtualReg = @import("regalloc.zig").VirtualReg;
const LocationConstraint = @import("regalloc.zig").LocationConstraint;

const LiveRange = struct {
    start: usize,
    end: usize,
    vreg: VirtualReg,
    constraints: LocationConstraint,
};

const Allocation = union(enum) {
    stack: void,
    preg: PhysicalReg,
};

const PhysAllocatedLiveRange = struct {
    live_range: LiveRange,
    preg: PhysicalReg,
};

const AllocatedLiveRange = struct {
    live_range: LiveRange,
    allocation: Allocation,
};

allocations: std.ArrayList(AllocatedLiveRange),
active: std.ArrayList(PhysAllocatedLiveRange),
inactive: std.ArrayList(PhysAllocatedLiveRange),
unhandled: std.ArrayList(LiveRange),

pub fn init(allocator: std.mem.Allocator) LinearScanAllocator {
    return LinearScanAllocator{
        .allocations = std.ArrayList(AllocatedLiveRange).init(allocator),
        .active = std.ArrayList(PhysAllocatedLiveRange).init(allocator),
        .inactive = std.ArrayList(PhysAllocatedLiveRange).init(allocator),
        .unhandled = std.ArrayList(LiveRange).init(allocator),
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

// Ranges have to be within block boundaries.
fn rangesIntersect(a: LiveRange, b: LiveRange) bool {
    return (a.start >= b.start and a.start <= b.end) or (b.start >= a.start and b.start <= a.end);
}

// `intervals` has to be ordered by liverange's start
pub fn run(
    self: *LinearScanAllocator,
    allocator: std.mem.Allocator,
    intervals: []const LiveRange,
    abi: Abi,
) !void {
    self.unhandled = std.ArrayList(LiveRange).fromOwnedSlice(allocator, @constCast(intervals));
    std.mem.reverse(LiveRange, self.unhandled.items);

    while (self.unhandled.popOrNull()) |current| {
        std.debug.print("{any} {}\n", .{ self.unhandled.items, current });
        var idx: usize = 0;
        for (self.active.items) |interval| {
            if (interval.live_range.end < current.start) {
                // remove interval from active
                const done = self.active.orderedRemove(idx);
                try self.allocations.append(AllocatedLiveRange{
                    .live_range = done.live_range,
                    .allocation = .{ .preg = done.preg },
                });
            }
            //else if (!rangesIntersect(interval.live_range, current)) {
            // FIXME: this is if I make intervals that are not continuous
            // move from active to inactive
            //    try self.inactive.append(self.active.orderedRemove(idx));
            else {
                idx += 1;
            }
        }

        idx = 0;
        for (self.inactive.items) |interval| {
            if (interval.live_range.end < current.start) {
                // remove from inactive
                _ = self.inactive.orderedRemove(idx);
            } else if (rangesIntersect(interval.live_range, current)) {
                // move from inactive to active
                try self.active.append(self.inactive.orderedRemove(idx));
            } else {
                idx += 1;
            }
        }

        switch (current.constraints) {
            .stack => {
                // no need to do anything apart from adding to the list
                try self.allocations.append(AllocatedLiveRange{
                    .live_range = current,
                    .allocation = .stack,
                });

                continue;
            },
            .fixed_reg => |preg| {
                try self.active.append(PhysAllocatedLiveRange{
                    .live_range = current,
                    .preg = preg,
                });

                try self.allocations.append(AllocatedLiveRange{
                    .live_range = current,
                    .allocation = .{ .preg = preg },
                });

                continue;
            },
            else => {},
        }

        try self.assignAllocateRegOrStack(allocator, current, abi);
    }

    for (self.active.items) |interval| {
        try self.allocations.append(AllocatedLiveRange{
            .live_range = interval.live_range,
            .allocation = .{ .preg = interval.preg },
        });
    }
}

pub fn assignAllocateRegOrStack(
    self: *LinearScanAllocator,
    allocator: std.mem.Allocator,
    current: LiveRange,
    abi: Abi,
) !void {
    var free_until = std.AutoArrayHashMap(PhysicalReg, usize).init(allocator);
    defer free_until.deinit();

    const pregs = abi.getPregsByRegClass(current.vreg.class);

    try free_until.ensureTotalCapacity(pregs.len);

    for (pregs) |preg| {
        try free_until.put(preg, std.math.maxInt(usize));
    }

    // initialize free_until for each preg.

    // zero if active
    for (self.active.items) |interval| {
        // std.debug.print("{} active at the same time as {}\n", .{ interval, current });
        try free_until.put(interval.preg, 0);
    }

    // and the next intersection of current and the interval if inactive.
    for (self.inactive.items) |interval| {
        if (interval.live_range.vreg.class == current.vreg.class and rangesIntersect(interval.live_range, current)) {
            try free_until.put(interval.preg, @max(interval.live_range.start, current.start));
        }
    }

    // add the intersection with fixed-reg ranges.
    for (self.unhandled.items) |interval| {
        if (interval.vreg.class == current.vreg.class and rangesIntersect(interval, current)) {
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
        return self.active.append(PhysAllocatedLiveRange{
            .live_range = current,
            .preg = found,
        });
    }

    try self.allocations.append(AllocatedLiveRange{
        .live_range = .{
            .start = current.start,
            .end = max_free,
            .vreg = current.vreg,
            .constraints = current.constraints,
        },
        .allocation = .{ .preg = found },
    });

    const after_split = LiveRange{
        .start = max_free + 1,
        .end = current.end,
        .vreg = current.vreg,
        .constraints = current.constraints,
    };

    try self.insertToUnhandled(after_split);
}

fn insertToUnhandled(self: *LinearScanAllocator, live_range: LiveRange) !void {
    std.debug.print("\n\nwtf\n\n", .{});
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

    std.debug.print("\n\nwtf {}\n\n", .{min + max});
    try self.unhandled.insert((min + max) / 2, live_range);
}

/// requires a and b to intersect; otherwise, the output is wrong.
fn intersectionWeight(a: LiveRange, b: LiveRange) usize {
    return @min(a.end, b.end) - @max(a.start, b.start);
}

fn assignAllocateBlockedReg(
    self: *LinearScanAllocator,
    current: LiveRange,
) !void {
    // NOTE: I don't want to store every use, so I can't do distance-to-next-use.
    // I'm using here a really naive heuristic: the length of the live range.
    // This means the allocator is really bad at allocating for vregs that are
    // used far from their definition for no reason.

    // calculate spill weight (cost) for current
    // pretty much winged everything here
    const current_spill_cost = (current.end - current.start) * 3 + 20;

    var min_active_cost: usize = std.math.maxInt(usize);
    var min_cost_idx: ?usize = null;

    // calculate spill weight (cost) for the intervals blocking current
    for (self.active.items, 0..) |interval, i| {
        if (interval.live_range.vreg.class == current.vreg.class) {
            const length = interval.live_range.end - interval.live_range.start;
            const interference = intersectionWeight(current, interval.live_range); // should probably do this with all active intervals, but eh.

            const cost = length * 3 + interference * 4;

            if (cost < min_active_cost) {
                min_active_cost = cost;
                min_cost_idx = i;
            }
        }
    }

    if (min_active_cost < current_spill_cost) {
        // spill min_cost's range
        const interval = self.active.orderedRemove(min_cost_idx.?);
        try self.allocations.append(AllocatedLiveRange{
            .live_range = interval.live_range,
            .allocation = .stack,
        });

        try self.active.append(PhysAllocatedLiveRange{
            .live_range = current,
            .preg = interval.preg,
        });
    } else {
        // spill current
        try self.allocations.append(AllocatedLiveRange{
            .live_range = current,
            .allocation = .stack,
        });
    }
}

test "poop" {
    const allocator = std.testing.allocator;

    var regalloc = LinearScanAllocator.init(allocator);
    defer regalloc.deinit();

    try regalloc.run(
        allocator,
        &.{
            LiveRange{
                .start = 0,
                .end = 3,
                .vreg = VirtualReg{ .class = .int, .index = 0 },
                .constraints = .none,
            },
            LiveRange{
                .start = 2,
                .end = 5,
                .vreg = VirtualReg{ .class = .int, .index = 2 },
                .constraints = .none,
            },
            LiveRange{
                .start = 2,
                .end = 10,
                .vreg = VirtualReg{ .class = .int, .index = 1 },
                .constraints = .none,
            },
        },
        Abi{
            .int_pregs = &.{
                PhysicalReg{ .class = .int, .encoding = 0 },
                PhysicalReg{ .class = .int, .encoding = 1 },
            },
            .float_pregs = &.{},
            .vector_pregs = &.{},
        },
    );

    std.debug.print("\n\n", .{});
    for (regalloc.allocations.items) |allocation| {
        std.debug.print("{any}\n\n", .{allocation});
    }

    std.debug.print("\n\n", .{});

    // regalloc.reset();

    // try regalloc.run(
    //     allocator,
    //     &.{
    //         LiveRange{
    //             .start = 0,
    //             .end = 3,
    //             .vreg = VirtualReg{ .class = .float, .index = 0 },
    //             .constraints = .none,
    //         },
    //         LiveRange{
    //             .start = 2,
    //             .end = 5,
    //             .vreg = VirtualReg{ .class = .int, .index = 2 },
    //             .constraints = .none,
    //         },
    //         LiveRange{
    //             .start = 2,
    //             .end = 10,
    //             .vreg = VirtualReg{ .class = .int, .index = 1 },
    //             .constraints = .none,
    //         },
    //         LiveRange{
    //             .start = 2,
    //             .end = 5,
    //             .vreg = VirtualReg{ .class = .float, .index = 1 },
    //             .constraints = .none,
    //         },
    //         LiveRange{
    //             .start = 9,
    //             .end = 20,
    //             .vreg = VirtualReg{ .class = .int, .index = 10 },
    //             .constraints = .none,
    //         },
    //     },
    //     Abi{
    //         .int_pregs = &.{
    //             PhysicalReg{ .class = .int, .encoding = 0 },
    //             // PhysicalReg{ .class = .int, .encoding = 1 },
    //         },
    //         .float_pregs = &.{
    //             PhysicalReg{ .class = .float, .encoding = 0 },
    //         },
    //         .vector_pregs = &.{},
    //     },
    // );

    // for (regalloc.allocations.items) |allocation| {
    //     std.debug.print("{any}\n\n", .{allocation});
    // }
}
