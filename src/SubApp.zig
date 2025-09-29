const std = @import("std");

const root = @import("root.zig");
const App = root.App;
const Commands = root.Commands;

const phasor_actor = @import("phasor-actor");
const phasor_channel = @import("phasor-channel");

const ChannelError = error{MissingSubAppResource};

/// Type-erased handle for managing SubApp lifecycle
pub const SubAppHandle = struct {
    ptr: *anyopaque,
    startFn: *const fn (ptr: *anyopaque, parent_app: *App) anyerror!void,
    stopFn: *const fn (ptr: *anyopaque) void,
    deinitFn: *const fn (ptr: *anyopaque) void,

    pub fn start(self: SubAppHandle, parent_app: *App) !void {
        try self.startFn(self.ptr, parent_app);
    }

    pub fn stop(self: SubAppHandle) void {
        self.stopFn(self.ptr);
    }

    pub fn deinit(self: SubAppHandle) void {
        self.deinitFn(self.ptr);
    }
};

/// Wrapper type to expose the parent-side sender for a subapp inbox as a
/// system parameter.
pub fn InboxSender(comptime InboxT: type) type {
    return struct {
        sender: *phasor_channel.Channel(InboxT).Sender,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(ParentInboxResource(InboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.sender = &res.sender;
        }

        pub fn send(self: Self, value: InboxT) !void {
            try self.sender.send(value);
        }

        pub fn trySend(self: Self, value: InboxT) !bool {
            return try self.sender.trySend(value);
        }

        pub fn close(self: Self) void {
            self.sender.close();
        }
    };
}

/// Wrapper type to expose the parent-side receiver for a subapp outbox as a
/// system parameter.
pub fn OutboxReceiver(comptime OutboxT: type) type {
    return struct {
        receiver: *phasor_channel.Channel(OutboxT).Receiver,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(ParentOutboxResource(OutboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.receiver = &res.receiver;
        }

        pub fn recv(self: Self) !OutboxT {
            return try self.receiver.recv();
        }

        pub fn tryRecv(self: Self) ?OutboxT {
            return self.receiver.tryRecv();
        }

        pub fn next(self: Self) ?OutboxT {
            return self.receiver.next();
        }

        pub fn close(self: Self) void {
            self.receiver.close();
        }
    };
}

/// Wrapper type to expose the subapp-side receiver for commands coming from
/// the parent.
pub fn InboxReceiver(comptime InboxT: type) type {
    return struct {
        receiver: *phasor_channel.Channel(InboxT).Receiver,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(SubAppInboxResource(InboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.receiver = &res.receiver;
        }

        pub fn recv(self: Self) !InboxT {
            return try self.receiver.recv();
        }

        pub fn tryRecv(self: Self) ?InboxT {
            return self.receiver.tryRecv();
        }

        pub fn next(self: Self) ?InboxT {
            return self.receiver.next();
        }

        pub fn close(self: Self) void {
            self.receiver.close();
        }
    };
}

/// Wrapper type to expose the subapp-side sender for replies back to the
/// parent.
pub fn OutboxSender(comptime OutboxT: type) type {
    return struct {
        sender: *phasor_channel.Channel(OutboxT).Sender,

        const Self = @This();

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            const res = commands.world.getResourceMut(SubAppOutboxResource(OutboxT)) orelse
                return ChannelError.MissingSubAppResource;
            self.sender = &res.sender;
        }

        pub fn send(self: Self, value: OutboxT) !void {
            try self.sender.send(value);
        }

        pub fn trySend(self: Self, value: OutboxT) !bool {
            return try self.sender.trySend(value);
        }

        pub fn close(self: Self) void {
            self.sender.close();
        }
    };
}

pub fn ParentInboxResource(comptime InboxT: type) type {
    return struct {
        sender: phasor_channel.Channel(InboxT).Sender,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.sender.close();
            self.sender.deinit();
        }
    };
}

pub fn ParentOutboxResource(comptime OutboxT: type) type {
    return struct {
        receiver: phasor_channel.Channel(OutboxT).Receiver,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.receiver.close();
            self.receiver.deinit();
        }
    };
}

pub fn SubAppInboxResource(comptime InboxT: type) type {
    return struct {
        receiver: phasor_channel.Channel(InboxT).Receiver,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.receiver.close();
            self.receiver.deinit();
        }
    };
}

pub fn SubAppOutboxResource(comptime OutboxT: type) type {
    return struct {
        sender: phasor_channel.Channel(OutboxT).Sender,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.sender.close();
            self.sender.deinit();
        }
    };
}

pub fn SubApp(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        const Self = @This();
        const InboxChannel = phasor_channel.Channel(InboxT);
        const OutboxChannel = phasor_channel.Channel(OutboxT);

        const Context = struct {
            sub_app: *Self,

            pub fn work(
                self: *Context,
                inbox: *InboxChannel.Receiver,
                outbox: *OutboxChannel.Sender,
            ) void {
                self.sub_app.workerMain(inbox, outbox);
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
        worker_error: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        worker_done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub const Options = struct {
            inbox_capacity: usize = 64,
            outbox_capacity: usize = 64,
        };

        pub const Error = error{
            AlreadyStarted,
            WorkerFailed,
        };

        pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
            return Self{
                .allocator = allocator,
                .app = try App.default(allocator),
                .actor = ActorType.init(allocator),
                .options = options,
            };
        }

        pub fn deinit(self: *Self) void {
            self.stop();
            // Only deinit our app if we're not managed by a parent
            // (parent App will handle cleanup of managed SubApps)
            if (self.parent == null) {
                self.app.deinit();
            }
        }

        pub fn stop(self: *Self) void {
            if (self.handle) |*handle| {
                self.stop_flag.store(true, .release);
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
            } else if (self.parent) |parent_app| {
                _ = parent_app.world.removeResource(ParentInboxResource(InboxT));
                _ = parent_app.world.removeResource(ParentOutboxResource(OutboxT));
                self.parent = null;
            }

            self.ready.store(false, .release);
            self.stop_flag.store(false, .release);
            self.worker_error.store(0, .release);
            self.worker_done.store(false, .release);
        }

        pub fn start(self: *Self, parent_app: *App) !void {
            if (self.handle != null) {
                return Error.AlreadyStarted;
            }

            self.parent = parent_app;
            self.ready.store(false, .release);
            self.stop_flag.store(false, .release);
            self.worker_error.store(0, .release);
            self.worker_done.store(false, .release);

            self.context = .{ .sub_app = self };

            var handle = try self.actor.spawn(&self.context, self.options.inbox_capacity, self.options.outbox_capacity);
            errdefer {
                handle.inbox.close();
                handle.outbox.close();
                handle.thread.join();
                handle.inbox.deinit();
                handle.outbox.deinit();
            }

            const parent_inbox = handle.inbox.clone();
            errdefer {
                var tmp = parent_inbox;
                tmp.close();
                tmp.deinit();
            }

            const parent_outbox = handle.outbox.clone();
            errdefer {
                var tmp = parent_outbox;
                tmp.close();
                tmp.deinit();
            }

            try parent_app.world.insertResource(ParentInboxResource(InboxT){ .sender = parent_inbox });
            errdefer {
                _ = parent_app.world.removeResource(ParentInboxResource(InboxT));
            }

            try parent_app.world.insertResource(ParentOutboxResource(OutboxT){ .receiver = parent_outbox });
            errdefer {
                _ = parent_app.world.removeResource(ParentOutboxResource(OutboxT));
            }

            self.handle = handle;

            while (!self.ready.load(.acquire)) {
                std.Thread.yield() catch {};
            }

            const err_code = self.worker_error.load(.acquire);
            if (err_code != 0) {
                self.stop();
                return Error.WorkerFailed;
            }
        }

        fn recordWorkerError(self: *Self, err: anyerror) void {
            self.worker_error.store(@intFromError(err), .release);
        }

        fn workerMain(self: *Self, inbox: *InboxChannel.Receiver, outbox: *OutboxChannel.Sender) void {
            var inserted_inbox = false;
            var inserted_outbox = false;
            defer {
                if (inserted_inbox) {
                    _ = self.app.world.removeResource(SubAppInboxResource(InboxT));
                }
                if (inserted_outbox) {
                    _ = self.app.world.removeResource(SubAppOutboxResource(OutboxT));
                }
                self.worker_done.store(true, .release);
            }

            const inbox_clone = inbox.*.clone();
            self.app.world.insertResource(SubAppInboxResource(InboxT){ .receiver = inbox_clone }) catch |err| {
                self.recordWorkerError(err);
                self.ready.store(true, .release);
                return;
            };
            inserted_inbox = true;

            const outbox_clone = outbox.*.clone();
            self.app.world.insertResource(SubAppOutboxResource(OutboxT){ .sender = outbox_clone }) catch |err| {
                self.recordWorkerError(err);
                self.ready.store(true, .release);
                return;
            };
            inserted_outbox = true;

            self.ready.store(true, .release);

            var ran_prestartup = false;

            self.app.runSchedulesFrom("PreStartup") catch |err| {
                self.recordWorkerError(err);
                return;
            };
            ran_prestartup = true;

            while (!self.stop_flag.load(.acquire)) {
                const exit_res = self.app.step() catch |err| {
                    self.recordWorkerError(err);
                    break;
                };

                if (exit_res != null) {
                    break;
                }
            }

            if (ran_prestartup) {
                self.app.runSchedulesFrom("PreShutdown") catch |err| {
                    self.recordWorkerError(err);
                };
            }
        }

        pub fn addPlugin(self: *Self, plugin: anytype) !void {
            try self.app.addPlugin(plugin);
        }

        pub fn addSystem(self: *Self, schedule_name: []const u8, comptime system_fn: anytype) !void {
            try self.app.addSystem(schedule_name, system_fn);
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

        pub fn insertResource(self: *Self, resource: anytype) !void {
            try self.app.insertResource(resource);
        }

        pub fn registerEvent(self: *Self, comptime T: type, capacity: usize) !void {
            try self.app.registerEvent(T, capacity);
        }

        pub fn world(self: *Self) *root.World {
            return &self.app.world;
        }

        /// Create a type-erased handle for lifecycle management
        pub fn toHandle(self: *Self) SubAppHandle {
            const startWrapper = struct {
                fn start(ptr: *anyopaque, parent_app: *App) anyerror!void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    return subapp.start(parent_app);
                }
            }.start;

            const stopWrapper = struct {
                fn stop(ptr: *anyopaque) void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    subapp.stop();
                }
            }.stop;

            const deinitWrapper = struct {
                fn deinit(ptr: *anyopaque) void {
                    const subapp: *Self = @ptrCast(@alignCast(ptr));
                    subapp.deinit();
                }
            }.deinit;

            return SubAppHandle{
                .ptr = self,
                .startFn = startWrapper,
                .stopFn = stopWrapper,
                .deinitFn = deinitWrapper,
            };
        }
    };
}
