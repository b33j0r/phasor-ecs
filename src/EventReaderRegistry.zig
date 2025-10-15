const std = @import("std");

/// Global registry for EventReader subscriptions.
/// Each system's EventReader(T) gets a unique subscription stored here.
/// The key is a hash of the system function pointer and event type.
const EventReaderRegistry = @This();

const SubscriptionEntry = struct {
    ptr: *anyopaque,
    deinit_fn: *const fn (*anyopaque) void,
};

allocator: std.mem.Allocator,
subscriptions: std.AutoHashMap(u64, SubscriptionEntry),
mutex: std.Thread.Mutex = .{},

pub fn init(allocator: std.mem.Allocator) EventReaderRegistry {
    return .{
        .allocator = allocator,
        .subscriptions = std.AutoHashMap(u64, SubscriptionEntry).init(allocator),
    };
}

pub fn deinit(self: *EventReaderRegistry) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // Clean up all subscriptions
    var iter = self.subscriptions.valueIterator();
    while (iter.next()) |entry| {
        entry.deinit_fn(entry.ptr);
    }
    self.subscriptions.deinit();
}

/// Generate a unique key for a system function + event type combination
pub fn makeKey(comptime system_fn: anytype, comptime T: type) u64 {
    const system_ptr = @intFromPtr(&system_fn);
    const type_hash = comptime blk: {
        const name = @typeName(T);
        var hash: u64 = 0;
        for (name) |c| {
            hash = hash *% 31 +% c;
        }
        break :blk hash;
    };
    return system_ptr ^ type_hash;
}

/// Store a subscription for a given key with its cleanup function
pub fn store(self: *EventReaderRegistry, key: u64, subscription: *anyopaque, deinit_fn: *const fn (*anyopaque) void) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.subscriptions.put(key, .{ .ptr = subscription, .deinit_fn = deinit_fn });
}

/// Retrieve a subscription for a given key
pub fn get(self: *EventReaderRegistry, key: u64) ?*anyopaque {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.subscriptions.get(key)) |entry| {
        return entry.ptr;
    }
    return null;
}

/// Remove a subscription for a given key (used during cleanup)
pub fn remove(self: *EventReaderRegistry, key: u64) bool {
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.subscriptions.remove(key);
}
