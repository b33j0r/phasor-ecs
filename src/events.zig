//! Implements a thread-safe event broadcast system with multiple readers.
//! Each EventReader maintains its own cursor into the event buffer.
//!
//! IMPORTANT: BroadcastChannel keeps events in memory until ALL readers consume them.
//! This means if you have multiple EventReaders for the same event type, and some
//! systems are inactive (e.g., different game states), you MUST drain events in ALL
//! systems every frame to prevent unbounded memory growth. Use reader.drain() or
//! a while loop with tryRecv() in systems that don't need to process events when
//! inactive.

const std = @import("std");
const phasor_channel = @import("phasor-channel");

const root = @import("root.zig");
const World = root.World;
const Commands = root.Commands;

pub fn Events(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        cap: usize,

        sender: Channel.Sender,
        controller: Channel.Controller,
        // Per-Events subscription registry (per-world)
        subs: std.AutoHashMap(u64, SubscriptionEntry),
        mutex: std.Thread.Mutex = .{},

        const Channel = phasor_channel.BroadcastChannel(T);
        const Self = @This();

        const SubscriptionEntry = struct { ptr: *anyopaque, deinit_fn: *const fn (*anyopaque) void };

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
                .subs = std.AutoHashMap(u64, SubscriptionEntry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // Clean up all subscriptions first
            self.mutex.lock();
            var it = self.subs.valueIterator();
            while (it.next()) |entry| {
                entry.deinit_fn(entry.ptr);
            }
            self.subs.deinit();
            self.mutex.unlock();

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

        pub fn getSubscriptionCount(self: *Self) usize {
            return self.controller.getSubscriptionCount();
        }

        /// Generate a unique key for a system function + this event type
        pub fn makeKey(comptime system_fn: anytype) u64 {
            const system_ptr = @intFromPtr(&system_fn);
            const type_hash = comptime blk: {
                const name = @typeName(T);
                var hash: u64 = 0;
                for (name) |c| hash = hash *% 31 +% c;
                break :blk hash;
            };
            return system_ptr ^ type_hash;
        }

        /// Store a subscription for a given key with its cleanup function
        pub fn store(self: *Self, key: u64, subscription: *anyopaque, deinit_fn: *const fn (*anyopaque) void) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.subs.put(key, .{ .ptr = subscription, .deinit_fn = deinit_fn });
        }

        /// Retrieve a subscription for a given key
        pub fn get(self: *Self, key: u64) ?*anyopaque {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.subs.get(key)) |entry| return entry.ptr;
            return null;
        }

        /// Remove and cleanup a subscription for a given key
        pub fn remove(self: *Self, key: u64) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.subs.fetchRemove(key)) |kv| {
                kv.value.deinit_fn(kv.value.ptr);
                return true;
            }
            return false;
        }
    };
}

pub fn EventWriter(comptime T: type) type {
    return struct {
        events: ?*Events(T),

        const Self = @This();

        pub fn init_system_param(self: *Self, comptime _: anytype, commands: *Commands) !void {
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

        /// One-time initialization per system - creates and stores subscription in the owning Events(T)
        pub fn register_system_param(comptime system_fn: anytype, world: *World) !void {
            const events = world.getResource(Events(T)) orelse return error.EventMustBeRegistered;

            // Generate unique key for this system + event type combo
            const key = Events(T).makeKey(system_fn);

            // Check if already subscribed
            if (events.get(key)) |_| {
                return; // Already initialized
            }

            // Create a wrapper that holds both the receiver and allocator
            const Wrapper = struct {
                receiver: Events(T).Channel.Receiver,
                allocator: std.mem.Allocator,
            };

            const alloc = world.allocator;
            const wrapper_ptr = try alloc.create(Wrapper);
            errdefer alloc.destroy(wrapper_ptr);

            wrapper_ptr.* = .{
                .receiver = try events.subscribe(),
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

            // Store in events registry with cleanup function
            try events.store(key, @ptrCast(wrapper_ptr), cleanupFn);
        }

        /// Per-frame initialization - looks up subscription from the owning Events(T)
        pub fn init_system_param(self: *Self, comptime system_fn: anytype, commands: *Commands) !void {
            const Wrapper = struct {
                receiver: Events(T).Channel.Receiver,
                allocator: std.mem.Allocator,
            };

            const events = commands.getResource(Events(T)) orelse return error.EventMustBeRegistered;

            const key = Events(T).makeKey(system_fn);

            const wrapper_opaque = events.get(key) orelse
                return error.EventReaderNotSubscribed;

            const wrapper: *Wrapper = @ptrCast(@alignCast(wrapper_opaque));
            self.receiver = &wrapper.receiver;
        }

        pub fn deinit(self: *Self) void {
            // Don't deinit the receiver - it's owned by the registry
            self.receiver = null;
        }

        /// Automatic cleanup hook: ECS calls when system removed or schedule deinitialized
        pub fn unregister_system_param(comptime system_fn: anytype, world: *World) !void {
            const events = world.getResource(Events(T)) orelse return; // If events gone, nothing to clean
            const key = Events(T).makeKey(system_fn);
            _ = events.remove(key);
        }

        /// Drain all pending events without processing them.
        pub fn drain(self: Self) void {
            if (self.receiver == null) return;
            while (self.receiver.?.tryRecv()) |_| {}
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
            return self.receiver.?.tryRecv();
        }
    };
}
