const std = @import("std");

pub fn Deque(comptime T: type) type {
    return DequeAligned(T, null);
}

pub fn DequeAligned(comptime T: type, comptime alignment: ?u29) type {
    if (alignment == @alignOf(T)) {
        return DequeAligned(T, null);
    }

    return struct {
        allocator: std.mem.Allocator,
        len: usize = 0,
        head: usize = 0,

        // should not be accessed directly
        items: if (alignment) |algn| []align(algn) T else []T,

        pub fn initCapacity(allocator: std.mem.Allocator, size: usize) !@This() {
            if (size == 0) {
                return error.CapacityZero;
            }

            return @This(){
                .allocator = allocator,
                .items = try allocator.alloc(T, size),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.items);
        }

        pub fn capacity(self: @This()) usize {
            return self.items.len;
        }

        fn ensureTotalCapacity(self: *@This(), new_capacity: usize) !void {
            if (self.capacity() >= new_capacity) {
                return;
            }

            // Look at std.ArrayList's impl
            var better_capacity = new_capacity;
            while (true) {
                better_capacity +|= better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }

            try self.ensureTotalCapacityPrecise(better_capacity);
        }

        fn ensureTotalCapacityPrecise(self: *@This(), new_capacity: usize) !void {
            const old_capacity = self.capacity();

            const old_memory = self.items;
            if (self.allocator.resize(old_memory, new_capacity)) {
                self.items.len = new_capacity;
            } else {
                const new_memory = try self.allocator.alloc(T, new_capacity);
                @memcpy(new_memory[0..self.capacity()], self.items);

                self.items.ptr = new_memory.ptr;
                self.items.len = new_capacity;

                self.allocator.free(old_memory);
            }

            self.handleCapacityIncrease(old_capacity);
        }

        fn handleCapacityIncrease(self: *@This(), old_capacity: usize) void {
            const new_capacity = self.capacity();

            // if `self.head <= self.capacity() - self.len` then the head was
            // approximately at the start, having a lot of head room, so we don't need to
            // move it.
            if (self.head > old_capacity - self.len) {
                // number of elements from the head to end-of-capacity
                const head_room = old_capacity - self.head;
                // the number of elements that have wrapped around.
                const tail_room = self.len - head_room;

                // if the number of elements at the tail is less than the head's,
                // and there's enough room for the tail at the end, copy it.
                if (tail_room < head_room and new_capacity - old_capacity >= tail_room) {
                    @memcpy(self.items[old_capacity..], self.items[0..tail_room]);
                } else {
                    const new_head = new_capacity - head_room;
                    std.mem.copyForwards(T, self.items[new_head..], self.items[self.head..][0..head_room]);

                    self.head = new_head;
                }
            }
        }

        pub fn append(self: *@This(), value: T) !void {
            try self.ensureTotalCapacity(self.len + 1);

            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn prepend(self: *@This(), value: T) !void {
            try self.ensureTotalCapacity(self.len + 1);

            self.head = self.wrapSub(@intCast(self.head), 1);
            self.len += 1;

            self.items[self.head] = value;
        }

        fn wrapSub(self: @This(), a: usize, b: usize) usize {
            if (a < b) {
                return self.capacity() - b + a;
            } else {
                return a - b;
            }
        }

        fn wrapAdd(self: @This(), a: usize, b: usize) usize {
            return (a + b) % self.capacity();
        }

        pub fn format(
            self: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            const tail = self.wrapAdd(self.head, self.len);

            try writer.writeAll("{ ");

            for (self.items, 0..) |item, i| {
                if (i < tail or (i >= self.head and i < self.head + self.len)) {
                    try writer.print("{any}", .{item});
                } else {
                    try writer.writeAll(". ");
                }

                if (i == self.head) {
                    try writer.writeAll("(H)");
                }

                if (i == tail) {
                    try writer.writeAll("(T)");
                }

                if (i < self.capacity() - 1) {
                    try writer.writeAll(", ");
                }
            }

            try writer.writeAll(" }");
        }

        pub fn prependSlice(self: *@This(), values: []const T) !void {
            if (values.len == 0) {
                return;
            }

            var i = values.len - 1;
            while (i >= 0) : (i -= 1) {
                try self.prepend(values[i]);
            }
        }

        pub fn appendSlice(self: *@This(), values: []const T) !void {
            for (values) |v| {
                try self.append(v);
            }
        }

        pub fn popFront(self: *@This()) ?T {
            if (self.len == 0) {
                return null;
            }

            defer self.head = self.wrapAdd(self.head, 1);
            self.len -= 1;

            return self.items[self.head];
        }

        pub fn popBack(self: *@This()) ?T {
            if (self.len == 0) {
                return null;
            }

            self.len -= 1;

            return self.items[self.wrapAdd(self.head, self.len)];
        }
    };
}

test "deque append/prepend" {
    const range_upper = 200;

    var deque = try Deque(u32).initCapacity(std.testing.allocator, 3);
    defer deque.deinit();

    for (0..range_upper) |i| {
        try deque.append(@intCast(i));
    }

    for (0..range_upper) |i| {
        try deque.prepend(@intCast(i));
    }

    try deque.prepend(1);

    try std.testing.expectEqual(@as(u32, 1), deque.popFront().?);

    var i: u32 = @intCast(range_upper - 1);
    while (true) : (i -= 1) {
        try std.testing.expectEqual(i, deque.popFront().?);
        try std.testing.expectEqual(i, deque.popBack().?);
        if (i == 0) break;
    }
}
