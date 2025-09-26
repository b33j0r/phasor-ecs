//! A type-erased actor management system. Handles the shutdown of the App's actors.

allocator: std.mem.Allocator,
actors: std.StringHashMapUnmanaged(ActorHandle) = .empty,

const ActorManager = @This();

pub fn init(allocator: std.mem.Allocator) ActorManager {
    return ActorManager{
        .allocator = allocator,
        .actors = .empty,
    };
}

pub fn deinit(self: *ActorManager) void {
    var it = self.actors.iterator();
    while (it.next()) |entry| {
        std.log.info("Stopping actor: {s}", .{entry.key_ptr.*});
        entry.value_ptr.stop();
        std.log.debug("Stopped actor: {s}", .{entry.key_ptr.*});
    }
    self.actors.deinit(self.allocator);
}

pub fn addActor(self: *ActorManager, comptime T: anytype) !void {
    _ = self;
    _ = T;
}

// ------------------------
// Internal Data Structures
// ------------------------

/// `ActorHandle` is a type-erased lifecycle management interface for actors.
/// It doesn't expose any of the message passing capabilities, just start/stop.
pub const ActorHandle = struct {
    name: []const u8,
    ptr: *anyopaque,
    stop_fn: *const fn (*anyopaque) void,

    const Self = @This();

    pub fn stop(self: *Self) void {
        // Let the actor's own stop() method handle thread joining
        self.stop_fn(self.ptr);
    }
};

// -------
// Imports
// -------
//
const std = @import("std");
