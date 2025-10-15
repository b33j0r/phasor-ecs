//! Implements a thread-safe event broadcast system with multiple readers.
//! Each EventReader maintains its own cursor into the event buffer.
//! The queue blocks producers when full and drops events for slow readers.

const std = @import("std");
const phasor_channel = @import("phasor-channel");

const root = @import("root.zig");
const Commands = root.Commands;
const EventReaderRegistry = root.EventReaderRegistry;

pub fn Events(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        cap: usize,

        sender: Channel.Sender,
        controller: Channel.Controller,

        const Channel = phasor_channel.BroadcastChannel(T);
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
                .controller = channel_pair.controller,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sender.deinit();
            self.controller.deinit();
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

        /// Create a new receiver with its own cursor
        pub fn subscribe(self: *Self) !Channel.Receiver {
            return self.controller.subscribe() catch |err| switch (err) {
                Channel.Error.Closed => return Error.QueueClosed,
                error.OutOfMemory => return error.OutOfMemory,
            };
        }

        /// Optional helper to mark closed; wakes all waiters.
        pub fn close(self: *Self) void {
            self.sender.close();
            self.controller.close();
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
        receiver: ?*Events(T).Channel.Receiver = null,

        const Self = @This();

        /// One-time initialization per system - creates and stores subscription in registry
        pub fn init_system_param_once(comptime system_fn: anytype, commands: *Commands) !void {
            const events = commands.getResource(Events(T));
            if (events == null) return error.EventMustBeRegistered;

            // Get or create the registry
            const registry = commands.getResource(EventReaderRegistry) orelse
                return error.EventReaderRegistryNotFound;

            // Generate unique key for this system + event type combo
            const key = EventReaderRegistry.makeKey(system_fn, T);

            // Check if already subscribed
            if (registry.get(key)) |_| {
                return; // Already initialized
            }

            // Create a wrapper that holds both the receiver and allocator
            const Wrapper = struct {
                receiver: Events(T).Channel.Receiver,
                allocator: std.mem.Allocator,
            };

            const alloc = commands.world.allocator;
            const wrapper_ptr = try alloc.create(Wrapper);
            errdefer alloc.destroy(wrapper_ptr);

            wrapper_ptr.* = .{
                .receiver = try events.?.subscribe(),
                .allocator = alloc,
            };

            // Create cleanup function
            const cleanupFn = &struct {
                fn cleanup(ptr: *anyopaque) void {
                    const wrapper: *Wrapper = @ptrCast(@alignCast(ptr));
                    wrapper.receiver.deinit();
                    const alloc_copy = wrapper.allocator;
                    alloc_copy.destroy(wrapper);
                }
            }.cleanup;

            // Store in registry with cleanup function
            try registry.store(key, @ptrCast(wrapper_ptr), cleanupFn);
        }

        /// Per-frame initialization - looks up subscription from registry
        pub fn init_system_param_with_context(self: *Self, comptime system_fn: anytype, commands: *Commands) !void {
            const Wrapper = struct {
                receiver: Events(T).Channel.Receiver,
                allocator: std.mem.Allocator,
            };

            const registry = commands.getResource(EventReaderRegistry) orelse
                return error.EventReaderRegistryNotFound;

            const key = EventReaderRegistry.makeKey(system_fn, T);

            const wrapper_opaque = registry.get(key) orelse
                return error.EventReaderNotSubscribed;

            const wrapper: *Wrapper = @ptrCast(@alignCast(wrapper_opaque));
            self.receiver = &wrapper.receiver;
        }

        // Fallback for compatibility
        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            _ = commands;
            _ = self;
            return error.EventReaderRequiresSystemContext;
        }

        pub fn deinit(self: *Self) void {
            // Don't deinit the receiver - it's owned by the registry
            self.receiver = null;
        }

        pub fn recv(self: Self) !T {
            if (self.receiver == null) return error.EventNotInitialized;
            return self.receiver.?.recv();
        }

        pub fn tryRecv(self: Self) ?T {
            if (self.receiver == null) return null;
            return self.receiver.?.tryRecv();
        }

        pub fn next(self: Self) ?T {
            if (self.receiver == null) return null;
            return self.receiver.?.next();
        }
    };
}
