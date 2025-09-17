//! Implements a thread-safe event queue with multiple producers and a single consumer.
//! The queue blocks producers when full and the consumer when empty. trySend and tryRecv
//! methods are also provided for non-blocking operations.

const std = @import("std");
const root = @import("root.zig");
const Commands = root.Commands;

pub fn Events(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        // one ref for Sender, one for Receiver (clones retain/release)
        ref_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(2),

        mutex: std.Thread.Mutex = .{},
        not_full: std.Thread.Condition = .{},
        not_empty: std.Thread.Condition = .{},

        buf: []T,
        cap: usize,
        head: usize = 0, // next pop
        tail: usize = 0, // next push
        len: usize = 0,

        closed: bool = false,

        const Self = @This();

        pub const Error = error{
            QueueClosed,
            QueueFull,
        };

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return Self{
                .allocator = allocator,
                .buf = allocator.alloc(T, capacity) catch return error.OutOfMemory,
                .cap = capacity,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buf);
            // No need to destroy condition/mutex: POD
        }

        inline fn isFull(self: *Self) bool {
            return self.len == self.cap;
        }
        inline fn isEmpty(self: *Self) bool {
            return self.len == 0;
        }
        inline fn pushAssumeLock(self: *Self, value: T) void {
            self.buf[self.tail] = value;
            self.tail = (self.tail + 1) % self.cap;
            self.len += 1;
        }
        inline fn popAssumeLock(self: *Self) T {
            const v = self.buf[self.head];
            self.head = (self.head + 1) % self.cap;
            self.len -= 1;
            return v;
        }

        /// Blocking send: waits while full unless closed.
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for space or close
            while (self.isFull() and !self.closed) {
                self.not_full.wait(&self.mutex);
            }
            if (self.closed) return Error.QueueClosed;

            self.pushAssumeLock(value);
            // Wake a waiting receiver
            self.not_empty.signal();
        }

        /// Non-blocking send: error if full or closed.
        pub fn trySend(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return Error.QueueClosed;
            if (self.isFull()) return Error.QueueFull;

            self.pushAssumeLock(value);
            self.not_empty.signal();
        }

        /// Blocking recv: waits while empty unless closed (panics if closed+empty).
        /// Matches the given signature (no error return). Do not call after close/empty.
        pub fn recv(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.isEmpty() and !self.closed) {
                self.not_empty.wait(&self.mutex);
            }
            if (self.isEmpty() and self.closed) {
                @panic("Events.recv called on closed and empty queue");
            }
            const v = self.popAssumeLock();
            // Wake a waiting producer
            self.not_full.signal();
            return v;
        }

        /// Non-blocking recv: returns null if empty (closed or not).
        pub fn tryRecv(self: *Self) !?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.isEmpty()) return null;

            const v = self.popAssumeLock();
            self.not_full.signal();
            return v;
        }

        /// Optional helper to mark closed; wakes all waiters.
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed = true;
            self.not_full.broadcast();
            self.not_empty.broadcast();
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
