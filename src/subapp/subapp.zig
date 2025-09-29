pub const SubAppOptions = struct {
    inbox_capacity: usize = 1024,
    outbox_capacity: usize = 1024,
};

/// A SubApp is an isolated application module that runs in its own thread.
/// It has its own ECS world, schedules, and plugins, and communicates with
/// the main app via message passing (inbox/outbox).
pub fn SubApp(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        allocator: std.mem.Allocator,

        const Self = @This();
        const ActorType = Actor(InboxT, OutboxT);
    };
}

// Imports
const std = @import("std");

const phasor_actor = @import("phasor-actor");
const Actor = phasor_actor.Actor;
const ActorError = phasor_actor.ActorError;

pub const SubAppLifecycle = @import("SubAppLifecycle.zig");

const subapp_system_params = @import("subapp_system_params.zig");
pub const InboxSender = subapp_system_params.InboxSender;
pub const OutboxReceiver = subapp_system_params.OutboxReceiver;
pub const InboxReceiver = subapp_system_params.InboxReceiver;
pub const OutboxSender = subapp_system_params.OutboxSender;
