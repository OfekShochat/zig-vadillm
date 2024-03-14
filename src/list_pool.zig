const std = @import("std");

pub const SizeClass = u5;

pub const Size = enum(u5) {
    @"4" = 0,
    @"8",
    @"16",
    @"32",
    @"64",
    @"128",
    @"256",
};

fn minSizeClassFor(size: u32) !SizeClass {
    if (size == 0) {
        return 0;
    }

    const ceil_size = @max(try std.math.ceilPowerOfTwo(u32, size), 4);
    return @as(u5, @intCast(@ctz(ceil_size)));
}

pub fn PooledVector(comptime T: type) type {
    return struct {
        offset: u32 = 0,

        pub fn initCapacity(list_pool: *ListPool(T), initial_size_class: Size) !@This() {
            const offset = try list_pool.alloc(@intFromEnum(initial_size_class)) + 1;
            try list_pool.setSize(offset, @intFromEnum(initial_size_class));

            return @This(){
                .offset = offset,
            };
        }

        pub fn deinit(self: @This(), list_pool: *ListPool(T)) !void {
            if (list_pool.sizeOf(self.offset) != 0) {
                try list_pool.dealloc(self.offset);
            }
        }

        pub fn append(self: *@This(), list_pool: *ListPool(T), val: T) !void {
            const curr_size = list_pool.sizeOf(self.offset);

            const size_class = try minSizeClassFor(curr_size);
            const new_size_class = try minSizeClassFor(curr_size + 1);

            // realloc if necessary
            if (size_class != new_size_class) {
                const new_offset = try list_pool.alloc(new_size_class) + 1;

                // copy if we have any elements
                if (self.offset != 0) {
                    const slice = list_pool.get(self.offset) orelse @panic("invalid state in `PooledVector`");
                    const new_slice = list_pool.get(new_offset) orelse @panic("invalid index returned from `alloc`");
                    @memcpy(new_slice[0..slice.len], slice);

                    try list_pool.dealloc(self.offset);
                }

                self.offset = new_offset;
            }

            try list_pool.setSize(self.offset, curr_size + 1);

            const item = self.getPtr(list_pool, curr_size) orelse @panic("`alloc` returned a smaller-than-expected slice");
            item.* = val;
        }

        pub fn get(self: @This(), list_pool: *ListPool(T), index: u32) ?T {
            const slice = list_pool.get(self.offset) orelse @panic("invalid state in `PooledVector`");

            if (index >= slice.len) {
                return null;
            } else {
                return slice[index];
            }
        }

        pub fn getPtr(self: @This(), list_pool: *ListPool(T), index: u32) ?*T {
            const slice = list_pool.get(self.offset) orelse @panic("invalid state in `PooledVector`");

            if (index >= slice.len) {
                return null;
            } else {
                return &slice[index];
            }
        }

        pub fn size(self: @This(), list_pool: *ListPool(T)) u32 {
            return list_pool.sizeOf(self.offset);
        }

        pub fn getSlice(self: @This(), list_pool: *ListPool(T)) ?[]T {
            return list_pool.get(self.offset);
        }
    };
}

fn sizeFor(size_class: SizeClass) u32 {
    return @as(u32, 4) << size_class;
}

pub fn ListPool(comptime T: type) type {
    return struct {
        comptime {
            if (@sizeOf(T) < @sizeOf(u32)) {
                @compileError("`@sizeOf(T)` has to be bigger than `@sizeOf(u32)` to fit the length inside it.");
            }
        }

        data: std.ArrayList(T),
        free: std.ArrayList(u32),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .data = std.ArrayList(T).init(allocator),
                .free = std.ArrayList(u32).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.data.deinit();
            self.free.deinit();
        }

        pub fn alloc(self: *@This(), size_class: SizeClass) !u32 {
            if (size_class >= self.free.items.len or self.free.items[size_class] == 0) {
                const curr_len = self.data.items.len;
                try self.data.resize(curr_len + sizeFor(size_class));

                try self.setSize(@as(u32, @intCast(curr_len)) + 1, sizeFor(size_class) - 1);
                // const length: *u32 = @ptrCast(&self.data.items[curr_len]);
                // length.* = sizeFor(size_class);

                return @intCast(curr_len);
            }

            // free list is a singly linked list of the free blocks,
            // set the free chunks list head to the next free chunk.
            const head = self.free.items[size_class];

            const next: *u32 = @ptrCast(&self.data.items[head]);
            self.free.items[size_class] = next.*;

            return head - 1;
        }

        // offset is the offset with the length
        pub fn dealloc(self: *@This(), offset: u32) !void {
            const length: *u32 = @ptrCast(&self.data.items[offset - 1]);
            const size_class = @ctz(length.*);
            length.* = 0;

            if (self.free.items.len <= size_class) {
                // resize and fill with zeros
                const old_len = self.free.items.len;
                try self.free.resize(size_class + 1);
                @memset(self.free.items[old_len..], 0);
            }

            // prepend the head into the free chunks list
            const next: *u32 = @ptrCast(&self.data.items[offset + 1]);
            next.* = self.free.items[size_class];
            self.free.items[size_class] = offset + 1;
        }

        pub fn get(self: *@This(), offset: u32) ?[]T {
            if (offset == 0 or offset >= self.data.items.len) {
                return null;
            }

            const length: *u32 = @ptrCast(&self.data.items[offset - 1]);

            if (length.* == 0) {
                return null;
            }

            return self.data.items[offset..][0..length.*];
        }

        pub fn sizeOf(self: @This(), offset: u32) u32 {
            if (offset == 0) {
                return 0;
            }

            return @as(*u32, @ptrCast(&self.data.items[offset - 1])).*;
        }

        pub fn setSize(self: @This(), offset: u32, size: u32) !void {
            if (offset == 0 or offset >= self.data.items.len) {
                return error.OutOfBounds;
            }

            @as(*u32, @ptrCast(&self.data.items[offset - 1])).* = size;
        }
    };
}

test "ListPool" {
    const Yhali = packed struct {
        is_good: bool,
        die: u32,
    };

    var list_pool = ListPool(Yhali).init(std.testing.allocator);
    const index = try list_pool.alloc(3) + 1;
    try list_pool.setSize(index, 31);

    try std.testing.expectEqual(@as(u32, 1), index);
    try std.testing.expectEqual(@as(usize, 31), list_pool.get(index).?.len);

    try list_pool.dealloc(index);

    try std.testing.expectEqual(@as(?[]Yhali, null), list_pool.get(index));

    const index2 = try list_pool.alloc(2) + 1;
    try list_pool.setSize(index2, 15);

    defer list_pool.deinit();

    try std.testing.expectEqual(@as(u32, 33), index2);
    try std.testing.expectEqual(@as(usize, 15), list_pool.get(index2).?.len);

    var vec = try PooledVector(Yhali).initCapacity(&list_pool, .@"32");
    defer vec.deinit(&list_pool) catch @panic("cannot allocate to free list");

    vec.getPtr(&list_pool, 0).?.* = Yhali{ .is_good = true, .die = 0 };
    try std.testing.expectEqual(vec.get(&list_pool, 0).?, Yhali{ .is_good = true, .die = 0 });
}

test "PooledVector" {
    var list_pool = ListPool(u32).init(std.testing.allocator);
    defer list_pool.deinit();

    var vec = PooledVector(u32){};
    defer vec.deinit(&list_pool) catch @panic("cannot allocate to free list");

    for (0..10) |i| {
        try vec.append(&list_pool, @intCast(i));
    }

    try std.testing.expectEqual(@as(u32, 10), vec.size(&list_pool));

    for (0..10) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(i)), vec.get(&list_pool, @intCast(i)).?);
    }
}
