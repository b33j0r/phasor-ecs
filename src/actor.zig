//! Actors are sub-applications with their own ECS worlds, connected
//! to the parent app via event queues defined in events.zig.

const std = @import("std");
const ecs = @import("root.zig");

const Commands = ecs.Commands;
const Events = ecs.Events;
const EventReader = ecs.EventReader;
const EventWriter = ecs.EventWriter;
const LinkedEvents = ecs.LinkedEvents;

/// Defines a sub-application with its own ECS `App`, typed with Inbox/Outbox.
pub fn Actor(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        app: ecs.App,
        thread: ?std.Thread = null,
        should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        // Synchronization primitives for deterministic wake-up
        mutex: std.Thread.Mutex = .{},
        condition: std.Thread.Condition = .{},

        const Self = @This();

        pub const Inbox = InboxT;
        pub const Outbox = OutboxT;

        pub fn init(allocator: std.mem.Allocator) !Self {
            const app = try ecs.App.default(allocator);
            return .{ .app = app };
        }

        pub fn start(self: *Self) !void {
            if (self.thread != null) return; // Already running

            self.should_stop.store(false, .monotonic);
            self.thread = try std.Thread.spawn(.{}, Self.runActor, .{self});
        }

        pub fn stop(self: *Self) void {
            if (self.thread == null) return; // Not running

            // Signal shutdown
            self.should_stop.store(true, .monotonic);

            // Wake up the actor thread using condition variable
            self.mutex.lock();
            self.condition.signal();
            self.mutex.unlock();

            // Close the inbox to wake up any blocking recv()
            if (self.app.getResource(LinkedEvents(InboxT, OutboxT))) |linked| {
                linked.inbox.close();
            }

            // Wait for thread to finish
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
        }

        fn runActor(self: *Self) void {
            // Run the actor's app until shutdown is requested
            while (!self.should_stop.load(.monotonic)) {
                // Only run app.step() if we're not being asked to stop
                if (!self.should_stop.load(.monotonic)) {
                    if (self.app.step()) |maybe_exit| {
                        if (maybe_exit) |exit| {
                            _ = exit; // Actor finished normally
                            break;
                        }
                    } else |_| {
                        // TODO: Error occurred
                    }
                }

                // Always check should_stop flag after any operations
                if (self.should_stop.load(.monotonic)) {
                    break;
                }

                // Use condition variable with timeout for deterministic wake-up
                // This replaces the non-deterministic sleep-based polling
                self.mutex.lock();
                defer self.mutex.unlock();

                // Wait for up to 1us or until signaled by stop()
                _ = self.condition.timedWait(&self.mutex, 1_000_000) catch {};
            }
        }

        pub fn deinit(self: *Self) void {
            self.stop(); // Ensure thread is stopped
            self.app.deinit();
        }
    };
}

pub fn ActorInbox(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        link: ?*LinkedEvents(InboxT, OutboxT) = null,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.link = commands.getResource(LinkedEvents(InboxT, OutboxT));
            if (self.link == null) return error.EventMustBeRegistered;
        }

        pub fn next(self: Self) ?InboxT {
            if (self.link == null) return null;
            var reader = self.link.?.reader();

            // Use non-blocking tryRecv() to avoid infinite blocking
            // This will return null if no message is available
            const result = reader.tryRecv() catch null;
            return result;
        }
    };
}

pub fn ActorOutbox(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        link: ?*LinkedEvents(InboxT, OutboxT) = null,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.link = commands.getResource(LinkedEvents(InboxT, OutboxT));
            if (self.link == null) return error.EventMustBeRegistered;
        }

        pub fn send(self: Self, event: OutboxT) !void {
            if (self.link == null) return error.EventNotInitialized;
            var writer = self.link.?.writer();
            try writer.trySend(event);
        }

        pub fn trySend(self: Self, event: OutboxT) !void {
            if (self.link == null) return error.EventNotInitialized;
            var writer = self.link.?.writer();
            try writer.trySend(event);
        }
    };
}
