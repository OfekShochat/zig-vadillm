const std = @import("std");

pub const SizeClass = u5;

pub fn PooledVector(comptime T: type) type {
    return struct {
        offset: u32,

        pub fn initCapacity(list_pool: *ListPool(T), initial_size_class: SizeClass) !@This() {
            return @This(){
                .offset = try list_pool.alloc(initial_size_class),
            };
        }

        pub fn deinit(self: @This(), list_pool: *ListPool(T)) !void {
            try list_pool.dealloc(self.offset);
        }

        pub fn get(self: @This(), list_pool: *ListPool(T), index: u32) ?T {
            const slice = list_pool.get(self.offset) orelse @panic("invalid statet in `PooledVector`");

            if (index >= slice.len) {
                return null;
            } else {
                return slice[index];
            }
        }

        pub fn getPtr(self: @This(), list_pool: *ListPool(T), index: u32) ?*T {
            const slice = list_pool.get(self.offset) orelse @panic("invalid statet in `PooledVector`");

            if (index >= slice.len) {
                return null;
            } else {
                return &slice[index];
            }
        }

        pub fn getSlice(self: @This(), list_pool: *ListPool(T)) ?[]T {
            return list_pool.get(self.index);
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

                const length: *u32 = @ptrCast(&self.data.items[curr_len]);
                length.* = sizeFor(size_class);

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
            const length: *u32 = @ptrCast(&self.data.items[offset]);
            const size_class = @ctz(length.*);
            length.* = 0;

            if (self.free.items.len <= size_class) {
                // resize and fill with zeros
                const old_len = self.free.items.len;
                try self.free.resize(size_class + 1);
                @memset(self.free.items[old_len..], 0);
            }

            // prepend the head into the free chunks list
            var next: *u32 = @ptrCast(&self.data.items[offset + 1]);
            next.* = self.free.items[size_class];
            self.free.items[size_class] = offset + 1;
        }

        pub fn get(self: *@This(), offset: u32) ?[]T {
            if (offset >= self.data.items.len) {
                return null;
            }

            const length: *u32 = @ptrCast(&self.data.items[offset]);

            if (length.* == 0) {
                return null;
            }

            return self.data.items[offset + 1 ..][0 .. length.* - 1];
        }
    };
}

test "ListPool" {
    const Yhali = packed struct {
        is_good: bool,
        die: u32,
    };

    var list_pool = ListPool(Yhali).init(std.testing.allocator);
    const index = try list_pool.alloc(3);

    try std.testing.expectEqual(@as(u32, 0), index);
    try std.testing.expectEqual(@as(usize, 31), list_pool.get(index).?.len);

    try list_pool.dealloc(index);

    try std.testing.expectEqual(@as(?[]Yhali, null), list_pool.get(index));

    const index2 = try list_pool.alloc(2);

    defer list_pool.deinit();

    try std.testing.expectEqual(@as(u32, 32), index2);
    try std.testing.expectEqual(@as(usize, 15), list_pool.get(index2).?.len);

    var vec = try PooledVector(Yhali).initCapacity(&list_pool, 3);
    defer vec.deinit(&list_pool) catch @panic("cannot allocate to free list");


    vec.getPtr(&list_pool, 0).?.* = Yhali{.is_good = true, .die = 0 };
    try std.testing.expectEqual(vec.get(&list_pool, 0).?, Yhali{.is_good = true, .die = 0 });
}
