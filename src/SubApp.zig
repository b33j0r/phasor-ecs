const std = @import("std");

const root = @import("root.zig");
const App = root.App;
const Commands = root.Commands;

const phasor_actor = @import("phasor-actor");
const phasor_channel = @import("phasor-channel");

const ChannelError = error{MissingSubAppResource};

/// ─────────────────────────────────────────────────────────────────────────────
/// Type-erased handle for managing SubApp lifecycle
pub const SubAppHandle = struct {
    const State = enum(u8) { Initialized = 0, Started = 1, Stopped = 2 };
    
    ptr: *anyopaque,
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(State.Initialized)),
    startFn: *const fn (*anyopaque, *App) anyerror!void,
    stopFn: *const fn (*anyopaque) void,
    deinitFn: *const fn (*anyopaque) void,

    pub fn start(self: *SubAppHandle, parent_app: *App) !void {
        const expected: u8 = @intFromEnum(State.Initialized);
        const new_state: u8 = @intFromEnum(State.Started);
        if (self.state.cmpxchgWeak(expected, new_state, .acq_rel, .acquire)) |actual| {
            if (actual == @intFromEnum(State.Started)) return error.AlreadyStarted;
            return error.AlreadyStarted; // Any other state means we can't start
        }
        self.startFn(self.ptr, parent_app) catch |err| {
            self.state.store(@intFromEnum(State.Initialized), .release);
            return err;
        };
    }
    pub fn stop(self: *SubAppHandle) void {
        const expected: u8 = @intFromEnum(State.Started);
        const new_state: u8 = @intFromEnum(State.Stopped);
        if (self.state.cmpxchgWeak(expected, new_state, .acq_rel, .acquire)) |_| return;
        self.stopFn(self.ptr);
    }
    pub fn deinit(self: *SubAppHandle) void {
        // Only call stop if we're actually started
        const current_state = self.state.load(.acquire);
        if (current_state == @intFromEnum(State.Started)) {
            self.stop();
        }
        self.deinitFn(self.ptr);
    }
};

/// ─────────────────────────────────────────────────────────────────────────────
/// Resource wrappers (parent <-> child ends)
pub fn ParentInboxResource(comptime InboxT: type) type {
    return struct {
        sender: phasor_channel.Channel(InboxT).Sender,
        pub fn deinit(self: *@This()) void {
            self.sender.close();
            self.sender.deinit();
        }
    };
}
pub fn ParentOutboxResource(comptime OutboxT: type) type {
    return struct {
        receiver: phasor_channel.Channel(OutboxT).Receiver,
        pub fn deinit(self: *@This()) void {
            self.receiver.close();
            self.receiver.deinit();
        }
    };
}
pub fn SubAppInboxResource(comptime InboxT: type) type {
    return struct {
        receiver: phasor_channel.Channel(InboxT).Receiver,
        pub fn deinit(self: *@This()) void {
            self.receiver.close();
            self.receiver.deinit();
        }
    };
}
pub fn SubAppOutboxResource(comptime OutboxT: type) type {
    return struct {
        sender: phasor_channel.Channel(OutboxT).Sender,
        pub fn deinit(self: *@This()) void {
            self.sender.close();
            self.sender.deinit();
        }
    };
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Core SubApp
pub fn SubApp(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        const Self = @This();
        const InboxChannel = phasor_channel.Channel(InboxT);
        const OutboxChannel = phasor_channel.Channel(OutboxT);

        const Context = struct {
            sub_app: *Self,
            pub fn work(self: *Context, inbox: *InboxChannel.Receiver, outbox: *OutboxChannel.Sender) void {
                self.sub_app.workerMain(inbox, outbox) catch |err| {
                    std.debug.print("[SubApp.workerMain] Worker failed: {any}\n", .{err});
                };
            }
        };

        const ActorType = phasor_actor.Actor(Context, InboxT, OutboxT);

        allocator: std.mem.Allocator,
        app: App,
        actor: ActorType,
        handle: ?ActorType.ActorHandle = null,
        context: Context = undefined,
        parent: ?*App = null,
        options: Options,

        ready: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub const Options = struct {
            inbox_capacity: usize = 64,
            outbox_capacity: usize = 64,
        };

        pub const Error = error{
            AlreadyStarted,
            WorkerFailed,
            WorkerNeverReady,
        };

        pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
            std.debug.print("[SubApp.init] {s}\n", .{@typeName(Self)});
            return Self{
                .allocator = allocator,
                .app = try App.default(allocator),
                .actor = ActorType.init(allocator),
                .options = options,
            };
        }

        pub fn deinit(self: *Self) void {
            std.debug.print("[SubApp.deinit] {s}\n", .{@typeName(Self)});
            self.stop();
            if (self.parent == null) self.app.deinit();
        }

        pub fn stop(self: *Self) void {
            std.debug.print("[SubApp.stop] {s}\n", .{@typeName(Self)});
            self.stop_flag.store(true, .release);

            // Stop children first before cleaning up our own resources
            for (self.app.subapps.items) |*child| child.stop();

            if (self.handle) |*handle| {
                if (self.parent) |parent_app| {
                    _ = parent_app.world.removeResource(ParentInboxResource(InboxT));
                    _ = parent_app.world.removeResource(ParentOutboxResource(OutboxT));
                    self.parent = null;
                }
                handle.inbox.close();
                handle.outbox.close();
                handle.thread.join();
                handle.inbox.deinit();
                handle.outbox.deinit();
                self.handle = null;
            }

            self.ready.store(false, .release);
        }

        pub fn start(self: *Self, parent_app: *App) !void {
            std.debug.print("[SubApp.start] {s}\n", .{@typeName(Self)});
            if (self.handle != null) return Error.AlreadyStarted;

            self.parent = parent_app;
            self.ready.store(false, .release);

            self.context = .{ .sub_app = self };
            var handle = try self.actor.spawn(
                &self.context,
                self.options.inbox_capacity,
                self.options.outbox_capacity,
            );

            // Insert parent-side resources immediately
            try parent_app.world.insertResource(ParentInboxResource(InboxT){ .sender = handle.inbox.clone() });
            try parent_app.world.insertResource(ParentOutboxResource(OutboxT){ .receiver = handle.outbox.clone() });

            self.handle = handle;

            // Start children recursively
            for (self.app.subapps.items) |*child| {
                child.start(&self.app) catch |err| switch (err) {
                    error.AlreadyStarted => {},
                    else => return err,
                };
            }

            // Wait for worker to insert its own resources
            var waited: usize = 0;
            while (!self.ready.load(.acquire)) {
                std.Thread.sleep(1_000_000); // 1ms
                waited += 1;
                if (waited > 5000) return Error.WorkerNeverReady;
            }
        }

        fn workerMain(self: *Self, inbox: *InboxChannel.Receiver, outbox: *OutboxChannel.Sender) !void {
            _ = try self.app.world.insertResource(SubAppInboxResource(InboxT){ .receiver = inbox.clone() });
            _ = try self.app.world.insertResource(SubAppOutboxResource(OutboxT){ .sender = outbox.clone() });

            self.ready.store(true, .release);

            _ = try self.app.runSchedulesFrom("PreStartup");
            while (!self.stop_flag.load(.acquire)) {
                if (self.app.step() catch null) |_| break;
                std.Thread.sleep(0);
            }
            _ = try self.app.runSchedulesFrom("PreShutdown");
        }

        // Delegations to inner App
        pub fn addPlugin(self: *Self, plugin: anytype) !void {
            try self.app.addPlugin(plugin);
        }
        pub fn addSystem(self: *Self, schedule: []const u8, comptime f: anytype) !void {
            try self.app.addSystem(schedule, f);
        }
        pub fn addSchedule(self: *Self, name: []const u8) !*root.Schedule {
            return try self.app.addSchedule(name);
        }
        pub fn scheduleAfter(self: *Self, name: []const u8, other: []const u8) !void {
            try self.app.scheduleAfter(name, other);
        }
        pub fn scheduleBefore(self: *Self, name: []const u8, other: []const u8) !void {
            try self.app.scheduleBefore(name, other);
        }
        pub fn scheduleBetween(self: *Self, name: []const u8, first: []const u8, last: []const u8) !void {
            try self.app.scheduleBetween(name, first, last);
        }
        pub fn addScheduleBetween(self: *Self, name: []const u8, first: []const u8, last: []const u8) !*root.Schedule {
            return try self.app.addScheduleBetween(name, first, last);
        }
        pub fn insertResource(self: *Self, res: anytype) !void {
            try self.app.insertResource(res);
        }
        pub fn registerEvent(self: *Self, comptime T: type, cap: usize) !void {
            try self.app.registerEvent(T, cap);
        }
        pub fn world(self: *Self) *root.World {
            return &self.app.world;
        }
        pub fn addSubApp(self: *Self, sub: anytype) !void {
            try self.app.addSubApp(sub);
        }

        pub fn toHandle(self: *Self) SubAppHandle {
            const startWrapper = struct {
                fn f(ptr: *anyopaque, parent: *App) anyerror!void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    return subapp.start(parent);
                }
            }.f;
            const stopWrapper = struct {
                fn f(ptr: *anyopaque) void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    subapp.stop();
                }
            }.f;
            const deinitWrapper = struct {
                fn f(ptr: *anyopaque) void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    subapp.deinit();
                }
            }.f;

            return SubAppHandle{ .ptr = self, .startFn = startWrapper, .stopFn = stopWrapper, .deinitFn = deinitWrapper };
        }
    };
}

// System Params

/// ─────────────────────────────────────────────────────────────────────────────
/// Parent-side sender for a subapp inbox
pub fn InboxSender(comptime InboxT: type) type {
    return struct {
        sender: *phasor_channel.Channel(InboxT).Sender,
        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(ParentInboxResource(InboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.sender = &res.sender;
        }
        pub fn send(self: *const Self, value: InboxT) !void {
            try self.sender.send(value);
        }
        pub fn trySend(self: *const Self, value: InboxT) !bool {
            return try self.sender.trySend(value);
        }
        pub fn close(self: *const Self) void {
            self.sender.close();
        }
    };
}

/// Parent-side receiver for a subapp outbox
pub fn OutboxReceiver(comptime OutboxT: type) type {
    return struct {
        receiver: *phasor_channel.Channel(OutboxT).Receiver,
        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(ParentOutboxResource(OutboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.receiver = &res.receiver;
        }
        pub fn recv(self: *const Self) !OutboxT {
            return try self.receiver.recv();
        }
        pub fn tryRecv(self: *const Self) ?OutboxT {
            return self.receiver.tryRecv();
        }
        pub fn next(self: *const Self) ?OutboxT {
            return self.receiver.next();
        }
        pub fn close(self: *const Self) void {
            self.receiver.close();
        }
    };
}

/// Subapp-side receiver (parent → child)
pub fn InboxReceiver(comptime InboxT: type) type {
    return struct {
        receiver: *phasor_channel.Channel(InboxT).Receiver,
        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(SubAppInboxResource(InboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.receiver = &res.receiver;
        }
        pub fn recv(self: *const Self) !InboxT {
            return try self.receiver.recv();
        }
        pub fn tryRecv(self: *const Self) ?InboxT {
            return self.receiver.tryRecv();
        }
        pub fn next(self: *const Self) ?InboxT {
            return self.receiver.next();
        }
        pub fn close(self: *const Self) void {
            self.receiver.close();
        }
    };
}

/// Subapp-side sender (child → parent)
pub fn OutboxSender(comptime OutboxT: type) type {
    return struct {
        sender: *phasor_channel.Channel(OutboxT).Sender,
        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(SubAppOutboxResource(OutboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.sender = &res.sender;
        }
        pub fn send(self: *const Self, value: OutboxT) !void {
            try self.sender.send(value);
        }
        pub fn trySend(self: *const Self, value: OutboxT) !bool {
            return try self.sender.trySend(value);
        }
        pub fn close(self: *const Self) void {
            self.sender.close();
        }
    };
}
