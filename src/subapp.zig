pub const SubAppOptions = struct {
    inbox_capacity: usize = 1024,
    outbox_capacity: usize = 1024,
};

pub fn SubApp(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        allocator: std.mem.Allocator,
        app: App,
        handle: Handle,
        thread: ?std.Thread = null,

        const InboxChannel = Channel(InboxT);
        const OutboxChannel = Channel(OutboxT);

        const Control = enum { Start, Stop, Started, Stopped };
        const ControlChannel = Channel(Control);

        const Status = enum { Started, Stopped };
        const StatusChannel = Channel(Status);

        /// Resource held by child (Actor)
        pub const Actor = struct {
            inbox_receiver: InboxChannel.Receiver,
            outbox_sender: OutboxChannel.Sender,
            ctrl_rx: ControlChannel.Receiver,
            status_tx: StatusChannel.Sender,

            pub fn deinit(self: *Actor) void {
                self.inbox_receiver.deinit();
                self.outbox_sender.deinit();
                self.ctrl_rx.deinit();
                self.status_tx.deinit();
            }
        };

        /// Resource held by parent (Handle)
        pub const Handle = struct {
            inbox_sender: InboxChannel.Sender,
            outbox_receiver: OutboxChannel.Receiver,
            ctrl_tx: ControlChannel.Sender,
            status_rx: StatusChannel.Receiver,

            pub fn deinit(self: *Handle) void {
                self.inbox_sender.deinit();
                self.outbox_receiver.deinit();
                self.ctrl_tx.deinit();
                self.status_rx.deinit();
            }
        };

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, opts: SubAppOptions) !Self {
            const inbox = try InboxChannel.create(allocator, opts.inbox_capacity);
            const outbox = try OutboxChannel.create(allocator, opts.outbox_capacity);
            const ctrl = try ControlChannel.create(allocator, 8);
            const status = try StatusChannel.create(allocator, 8);

            var app = try App.default(allocator);

            const actor = Actor{
                .inbox_receiver = inbox.receiver,
                .outbox_sender = outbox.sender,
                .ctrl_rx = ctrl.receiver,
                .status_tx = status.sender,
            };

            const handle = Handle{
                .inbox_sender = inbox.sender,
                .outbox_receiver = outbox.receiver,
                .ctrl_tx = ctrl.sender,
                .status_rx = status.receiver,
            };

            try app.insertResource(actor);

            return .{
                .allocator = allocator,
                .app = app,
                .handle = handle,
                .thread = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.app.deinit();
        }

        fn subAppThread(app: *App) !void {
            const actor = app.getResource(Actor) orelse {
                return error.MissingActorResource;
            };

            // child startup
            try app.runStartupSchedules();

            // Notify main we’re ready
            try actor.status_tx.send(.Started);

            // Main loop: never touch data inbox here — let systems do it.
            while (true) {
                // If main asks us to stop, exit the app loop
                if (actor.ctrl_rx.tryRecv()) |ctrl| {
                    if (ctrl == .Stop) {
                        break;
                    }
                }

                if (try app.step()) |exit| {
                    std.log.info("SubApp exiting with code {d}", .{exit.code});
                    break;
                }

                // Be nice to the scheduler
                try std.Thread.yield();
            }

            // child shutdown
            try app.runShutdownSchedules();

            // Signal we’re done
            try actor.status_tx.send(.Stopped);
        }

        fn start(self: *Self) !void {
            if (self.thread != null) return error.AlreadyStarted;
            const th = try std.Thread.spawn(.{}, Self.subAppThread, .{&self.app});
            self.thread = th;

            // Wait for child to signal it's started
            const status = self.handle.status_rx.recv() catch return error.ChildStartFailed;
            switch (status) {
                .Started => return,
                .Stopped => return error.FailedToStart,
            }
        }

        fn stop(self: *Self) !void {
            if (self.thread) |th| {
                // Check if the thread is still running and check if it already stopped.
                // Try to send Stop in case it wasn't sent
                _ = self.handle.ctrl_tx.send(.Stop) catch {};

                // If stopSubApp system already ran, it already waited for .Stopped.
                // If it didn't run (e.g. app crashed), we might need to wait here.
                // However, joining the thread is the ultimate blocking synchronization.
                // We only recv if we see a message waiting, to avoid double-consuming
                // or blocking if already consumed.
                if (self.handle.status_rx.tryRecv()) |status| {
                    if (status != .Stopped) return error.UnexpectedStatus;
                }

                th.join();
                self.thread = null;
            }
        }

        pub const Plugin = struct {
            subapp: *Self,

            pub fn build(self: *Plugin, app: *App) !void {
                // Make child halves visible to child app (already inserted in init)
                // Make main halves visible to main app
                try app.insertResource(self.subapp.handle);

                // Start the child thread right away
                try self.subapp.start();

                // Add shutdown system to PreShutdown so children shut down before parent
                try app.addSystem("PreShutdown", stopSubApp);
            }

            fn stopSubApp(commands: *Commands) !void {
                const handle = commands.getResource(Handle) orelse return;
                // Send stop signal
                try handle.ctrl_tx.send(.Stop);

                // Wait for child to signal it's stopped.
                // This ensures ChildApp: Shutdown happens before MainApp: Shutdown.
                const status = handle.status_rx.recv() catch return error.ChildStopFailed;
                if (status != .Stopped) return error.UnexpectedStatus;
            }

            pub fn cleanup(self: *Plugin, _: *App) !void {
                // Ensure the child is stopped and thread joined
                try self.subapp.stop();
            }
        };

        pub const InboxSender = struct {
            chan: ?InboxChannel.Sender = null,

            pub fn init_system_param(self: *InboxSender, comptime _: anytype, commands: *Commands) !void {
                const handle = commands.getResource(Handle).?;
                self.chan = handle.inbox_sender;
            }

            pub fn send(self: *const InboxSender, msg: InboxT) !void {
                if (self.chan) |c| return c.send(msg);
                return error.NotInitialized;
            }
        };

        pub const OutboxReceiver = struct {
            chan: ?OutboxChannel.Receiver = null,

            pub fn init_system_param(self: *OutboxReceiver, comptime _: anytype, commands: *Commands) !void {
                const handle = commands.getResource(Handle).?;
                self.chan = handle.outbox_receiver;
            }

            pub fn tryRecv(self: *const OutboxReceiver) !?OutboxT {
                if (self.chan) |c| return c.tryRecv();
                return error.NotInitialized;
            }
        };

        pub const OutboxSender = struct {
            chan: ?OutboxChannel.Sender = null,

            pub fn init_system_param(self: *OutboxSender, comptime _: anytype, commands: *Commands) !void {
                const actor = commands.getResource(Actor).?;
                self.chan = actor.outbox_sender;
            }

            pub fn send(self: *const OutboxSender, msg: OutboxT) !void {
                if (self.chan) |c| return c.send(msg);
                return error.NotInitialized;
            }
        };

        pub const InboxReceiver = struct {
            chan: ?InboxChannel.Receiver = null,

            pub fn init_system_param(self: *InboxReceiver, comptime _: anytype, commands: *Commands) !void {
                const actor = commands.getResource(Actor).?;
                self.chan = actor.inbox_receiver;
            }

            pub fn tryRecv(self: *const InboxReceiver) !?InboxT {
                if (self.chan) |c| return c.tryRecv();
                return error.NotInitialized;
            }
        };
    };
}

// Imports
const std = @import("std");

const root = @import("root.zig");
const App = root.App;
const Commands = root.Commands;
const World = root.World;

const phasor_channel = @import("phasor-channel");
const Channel = phasor_channel.Channel;
