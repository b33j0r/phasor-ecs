//! Implements a thread-safe event queue with multiple producers and a single consumer.
//! The queue blocks producers when full and the consumer when empty. trySend and tryRecv
//! methods are also provided for non-blocking operations.

const std = @import("std");
const channel_mod = @import("phasor-channel");
const root = @import("root.zig");
const Commands = root.Commands;

pub fn Events(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        cap: usize,

        sender: Channel.Sender,
        receiver: Channel.Receiver,

        const Channel = channel_mod.Channel(T);
        const Self = @This();

        pub const Error = error{
            QueueClosed,
            QueueFull,
        };

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const channel_pair = try Channel.create(allocator, capacity);
            return .{
                .allocator = allocator,
                .cap = capacity,
                .sender = channel_pair.sender,
                .receiver = channel_pair.receiver,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sender.deinit();
            self.receiver.deinit();
        }

        /// Blocking send: waits while full unless closed.
        pub fn send(self: *Self, value: T) !void {
            self.sender.send(value) catch |err| switch (err) {
                Channel.Error.Closed => return Error.QueueClosed,
            };
        }

        /// Non-blocking send: error if full or closed.
        pub fn trySend(self: *Self, value: T) !void {
            const sent = self.sender.trySend(value) catch |err| switch (err) {
                Channel.Error.Closed => return Error.QueueClosed,
            };
            if (!sent) return Error.QueueFull;
        }

        /// Blocking recv: waits while empty unless closed (panics if closed+empty).
        /// Matches the given signature (no error return). Do not call after close/empty.
        pub fn recv(self: *Self) T {
            return self.receiver.recv() catch |err| switch (err) {
                Channel.Error.Closed => @panic("Events.recv called on closed and empty queue"),
            };
        }

        /// Non-blocking recv: returns null if empty (closed or not).
        pub fn tryRecv(self: *Self) !?T {
            return self.receiver.tryRecv();
        }

        /// Optional helper to mark closed; wakes all waiters.
        pub fn close(self: *Self) void {
            self.sender.close();
            self.receiver.close();
        }
    };
}

pub fn EventWriter(comptime T: type) type {
    return struct {
        events: ?*Events(T),

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.events = commands.getResource(Events(T));
            if (self.events == null) return error.EventMustBeRegistered;
        }

        pub fn send(self: Self, event: T) !void {
            if (self.events == null) return error.EventNotInitialized;
            try self.events.?.send(event);
        }

        pub fn trySend(self: Self, event: T) !void {
            if (self.events == null) return error.EventNotInitialized;
            try self.events.?.trySend(event);
        }
    };
}

pub fn EventReader(comptime T: type) type {
    return struct {
        events: ?*Events(T),

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.events = commands.getResource(Events(T));
            if (self.events == null) return error.EventMustBeRegistered;
        }

        pub fn recv(self: Self) T {
            if (self.events == null) return error.EventNotInitialized;
            return self.events.?.recv();
        }

        pub fn tryRecv(self: Self) !?T {
            if (self.events == null) return error.EventNotInitialized;
            return self.events.?.tryRecv();
        }
    };
}
