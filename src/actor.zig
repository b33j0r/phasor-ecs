//! Actors are sub-applications with their own ECS worlds, connected
//! to the parent app via event queues defined in events.zig.

const std = @import("std");
const ecs = @import("root.zig");

const Commands = ecs.Commands;
const Events = ecs.Events;
const EventReader = ecs.EventReader;
const EventWriter = ecs.EventWriter;

pub fn Actor(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        app: ecs.App,

        const Self = @This();

        pub const Inbox = InboxT;
        pub const Outbox = OutboxT;

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .app = ecs.App.init(allocator) };
        }
    };
}

pub fn ActorInbox(comptime T: type) type {
    // TODO
}

pub fn ActorOutbox(comptime T: type) type {
    // TODO
}
