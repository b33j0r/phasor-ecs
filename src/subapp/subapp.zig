pub const SubAppOptions = struct {
    inbox_capacity: usize = 1024,
    outbox_capacity: usize = 1024,
};

const SubAppWorker = struct {
    pub fn work(
        _: *@This(),
        inbox: *InboxReceiver,
        outbox: *OutboxSender,
        stop_signal: Signal(bool),
        stopped_signal: Signal(bool),
    ) !void {
        while (!stop_signal.get()) {
            std.Thread.sleep(10);
        }
        stopped_signal.set(true);
    }
};

/// A SubApp is an isolated application module that runs in its own thread.
/// It has its own ECS world, schedules, and plugins, and communicates with
/// the main app via message passing (inbox/outbox).
pub fn SubApp(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        allocator: std.mem.Allocator,
        app: App,
        handle: ActorType.Handle,
        worker: *SubAppWorker,

        const Self = @This();
        const ActorType = Actor(InboxT, OutboxT);

        pub fn init(allocator: std.mem.Allocator, options: SubAppOptions) !Self {
            const app = App.init(allocator);
            var actor = ActorType.init(allocator);
            const worker = try allocator.create(SubAppWorker);
            return Self{
                .allocator = allocator,
                .app = app,
                .handle = try actor.spawn(worker, .{
                    .inbox_capacity = options.inbox_capacity,
                    .outbox_capacity = options.outbox_capacity,
                }),
                .worker = worker,
            };
        }

        pub fn deinit(self: *Self) void {
            self.handle.waitForStop(5000) catch {
                std.log.err("Timed out waiting for SubApp to stop during deinit", .{});
            };
            self.handle.deinit();
            self.app.deinit();
            self.allocator.destroy(self.worker);
        }

        pub const SubAppParentResource = struct {
            inbox: ActorType.InboxChannel.Sender,
            outbox: ActorType.OutboxChannel.Receiver,
        };

        pub const SubAppChildResource = struct {
            inbox: ActorType.InboxChannel.Receiver,
            outbox: ActorType.OutboxChannel.Sender,
        };
    };
}

// Imports
const std = @import("std");

const root = @import("../root.zig");
const App = root.App;

const phasor_actor = @import("phasor-actor");
const Actor = phasor_actor.Actor;
const Signal = phasor_actor.Signal;

pub const SubAppLifecycle = @import("SubAppLifecycle.zig");

const subapp_system_params = @import("subapp_system_params.zig");
pub const InboxSender = subapp_system_params.InboxSender;
pub const OutboxReceiver = subapp_system_params.OutboxReceiver;
pub const InboxReceiver = subapp_system_params.InboxReceiver;
pub const OutboxSender = subapp_system_params.OutboxSender;
