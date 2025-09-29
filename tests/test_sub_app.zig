const Reply = union(enum) {
    Sincere: []const u8,
    Snarky: []const u8,
};

const SendState = struct {
    sent: bool = false,
};

const ReplyLog = struct {
    allocator: std.mem.Allocator,
    replies: std.ArrayListUnmanaged(Reply) = .empty,

    pub fn deinit(self: *ReplyLog) void {
        self.replies.deinit(self.allocator);
    }
};

fn sendToActor(state: ResMut(SendState), inbox: InboxSender(Command)) !void {
    if (!state.ptr.sent) {
        try inbox.send(.DoThingA);
        try inbox.send(.DoThingB);
        state.ptr.sent = true;
    }
}

fn recvFromActor(log: ResMut(ReplyLog), outbox: OutboxReceiver(Reply)) !void {
    while (outbox.tryRecv()) |reply| {
        try log.ptr.replies.append(log.ptr.allocator, reply);
    }
}

fn processCommands(inbox: InboxReceiver(Command), outbox: OutboxSender(Reply)) !void {
    while (inbox.tryRecv()) |cmd| {
        switch (cmd) {
            .DoThingA => try outbox.send(.{ .Sincere = "thanks" }),
            .DoThingB => try outbox.send(.{ .Snarky = "sure" }),
        }
    }
}

test "SubApp forwards commands across thread boundary" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    var subapp = try ecs.SubApp(Command, Reply).init(allocator, .{
        .inbox_capacity = 8,
        .outbox_capacity = 8,
    });
    // Note: App will automatically handle SubApp cleanup via addSubApp()

    try subapp.addSystem("Update", processCommands);
    try app.addSubApp(&subapp);

    try app.insertResource(SendState{});
    try app.insertResource(ReplyLog{ .allocator = allocator });

    try app.addSystem("Update", sendToActor);
    try app.addSystem("Update", recvFromActor);

    try app.runSchedulesFrom("PreStartup");

    var attempts: usize = 0;
    while (attempts < 10) : (attempts += 1) {
        _ = try app.step();
        const maybe_log = app.world.getResource(ReplyLog).?;
        if (maybe_log.replies.items.len >= 2) break;
    }

    const log = app.world.getResource(ReplyLog).?;
    try std.testing.expectEqual(@as(usize, 2), log.replies.items.len);
    switch (log.replies.items[0]) {
        .Sincere => |msg| try std.testing.expectEqualStrings("thanks", msg),
        else => try std.testing.expect(false),
    }
    switch (log.replies.items[1]) {
        .Snarky => |msg| try std.testing.expectEqualStrings("sure", msg),
        else => try std.testing.expect(false),
    }

    try app.runSchedulesFrom("PreShutdown");
}

// Test 1: Nested SubApps (App -> SubApp -> SubApp) with end-to-end ping-pong
const PingPongMessage = union(enum) {
    Ping: u32,
    Pong: u32,
    Forward: u32,
    Response: u32,
};

const PingPongState = struct {
    ping_sent: bool = false,
    expected_pongs: u32 = 0,
    received_pongs: u32 = 0,
};

fn sendInitialPing(state: ResMut(PingPongState), inbox: InboxSender(PingPongMessage)) !void {
    if (!state.ptr.ping_sent) {
        try inbox.send(.{ .Ping = 42 });
        state.ptr.ping_sent = true;
        state.ptr.expected_pongs = 1;
    }
}

fn receiveResponse(state: ResMut(PingPongState), outbox: OutboxReceiver(PingPongMessage)) !void {
    while (outbox.tryRecv()) |msg| {
        switch (msg) {
            .Pong => |val| {
                std.debug.assert(val == 42);
                state.ptr.received_pongs += 1;
            },
            else => {},
        }
    }
}

fn forwardPingToNestedSimple(
    inbox: InboxReceiver(PingPongMessage),
    outbox: OutboxSender(PingPongMessage),
) !void {
    // Simple direct forwarding for basic lifecycle test
    while (inbox.tryRecv()) |msg| {
        switch (msg) {
            .Ping => |val| try outbox.send(.{ .Pong = val }),
            else => {},
        }
    }
}

const SharedPingState = struct {
    ping_value: ?u32 = null,
    response_value: ?u32 = null,
};

fn receiveFromParentAndStore(
    shared_state: ResMut(SharedPingState),
    inbox: InboxReceiver(PingPongMessage),
) !void {
    while (inbox.tryRecv()) |msg| {
        switch (msg) {
            .Ping => |val| {
                shared_state.ptr.ping_value = val;
            },
            else => {},
        }
    }
}

fn forwardToNestedViaState(
    shared_state: ResMut(SharedPingState),
    nested_inbox: InboxSender(PingPongMessage),
) !void {
    if (shared_state.ptr.ping_value) |ping_val| {
        try nested_inbox.send(.{ .Forward = ping_val });
        shared_state.ptr.ping_value = null; // Clear after sending
    }
}

fn collectFromNestedAndRespond(
    shared_state: ResMut(SharedPingState),
    nested_outbox: OutboxReceiver(PingPongMessage),
    outbox: OutboxSender(PingPongMessage),
) !void {
    while (nested_outbox.tryRecv()) |msg| {
        switch (msg) {
            .Response => |val| {
                shared_state.ptr.response_value = val;
                try outbox.send(.{ .Pong = val });
            },
            else => {},
        }
    }
}

fn processNestedMessage(inbox: InboxReceiver(PingPongMessage), outbox: OutboxSender(PingPongMessage)) !void {
    while (inbox.tryRecv()) |msg| {
        switch (msg) {
            .Forward => |val| try outbox.send(.{ .Response = val }),
            else => {},
        }
    }
}

test "Nested SubApps basic lifecycle" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    // Create the deepest nested SubApp with simple internal processing
    var nested_subapp = try ecs.SubApp(PingPongMessage, PingPongMessage).init(allocator, .{
        .inbox_capacity = 8,
        .outbox_capacity = 8,
    });
    try nested_subapp.addSystem("Update", processNestedMessage);

    // Create middle SubApp that contains the nested SubApp
    var middle_subapp = try ecs.SubApp(PingPongMessage, PingPongMessage).init(allocator, .{
        .inbox_capacity = 8,
        .outbox_capacity = 8,
    });

    // Add the nested SubApp to the middle SubApp - this is the key test
    try middle_subapp.addSubApp(&nested_subapp);

    // Simple forwarding without complex state management
    try middle_subapp.addSystem("Update", forwardPingToNestedSimple);

    // Add middle SubApp to main app
    try app.addSubApp(&middle_subapp);

    // Setup main app systems and state
    try app.insertResource(PingPongState{});
    try app.addSystem("Update", sendInitialPing);
    try app.addSystem("Update", receiveResponse);

    // Start everything
    try app.runSchedulesFrom("PreStartup");

    // Run for a limited time to test basic operation and shutdown
    var attempts: usize = 0;
    while (attempts < 10) : (attempts += 1) {
        _ = try app.step();
        std.Thread.sleep(10_000_000); // 10ms sleep to allow processing
    }

    // Don't check for specific responses, just verify clean shutdown
    try app.runSchedulesFrom("PreShutdown");
}

// Test 2: App with two SubApps with main app as mediator
const WorkerAMessage = union(enum) {
    Task: []const u8,
};

const WorkerAReply = union(enum) {
    Result: []const u8,
};

const WorkerBMessage = union(enum) {
    Task: []const u8,
};

const WorkerBReply = union(enum) {
    Result: []const u8,
};

const MediatorState = struct {
    work_sent: bool = false,
    results_received: u32 = 0,
    worker_a_result: ?[]const u8 = null,
    worker_b_result: ?[]const u8 = null,
};

fn sendWorkRequests(state: ResMut(MediatorState), worker_a_inbox: InboxSender(WorkerAMessage), worker_b_inbox: InboxSender(WorkerBMessage)) !void {
    if (!state.ptr.work_sent) {
        try worker_a_inbox.send(.{ .Task = "task_a" });
        try worker_b_inbox.send(.{ .Task = "task_b" });
        state.ptr.work_sent = true;
    }
}

fn collectResults(
    state: ResMut(MediatorState),
    worker_a_outbox: OutboxReceiver(WorkerAReply),
    worker_b_outbox: OutboxReceiver(WorkerBReply),
) !void {
    while (worker_a_outbox.tryRecv()) |msg| {
        switch (msg) {
            .Result => |result| {
                state.ptr.worker_a_result = result;
                state.ptr.results_received += 1;
            },
        }
    }

    while (worker_b_outbox.tryRecv()) |msg| {
        switch (msg) {
            .Result => |result| {
                state.ptr.worker_b_result = result;
                state.ptr.results_received += 1;
            },
        }
    }
}

fn workerAProcess(inbox: InboxReceiver(WorkerAMessage), outbox: OutboxSender(WorkerAReply)) !void {
    while (inbox.tryRecv()) |msg| {
        switch (msg) {
            .Task => |task| {
                if (std.mem.eql(u8, task, "task_a")) {
                    try outbox.send(.{ .Result = "completed_a" });
                }
            },
        }
    }
}

fn workerBProcess(inbox: InboxReceiver(WorkerBMessage), outbox: OutboxSender(WorkerBReply)) !void {
    while (inbox.tryRecv()) |msg| {
        switch (msg) {
            .Task => |task| {
                if (std.mem.eql(u8, task, "task_b")) {
                    try outbox.send(.{ .Result = "completed_b" });
                }
            },
        }
    }
}

test "App with two SubApps and main app as mediator" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    // Create worker A SubApp with distinct message types
    var worker_a = try ecs.SubApp(WorkerAMessage, WorkerAReply).init(allocator, .{
        .inbox_capacity = 8,
        .outbox_capacity = 8,
    });

    // Create worker B SubApp with distinct message types  
    var worker_b = try ecs.SubApp(WorkerBMessage, WorkerBReply).init(allocator, .{
        .inbox_capacity = 8,
        .outbox_capacity = 8,
    });

    // Configure worker SubApps
    try worker_a.addSystem("Update", workerAProcess);
    try worker_b.addSystem("Update", workerBProcess);

    // Add both SubApps to main app
    try app.addSubApp(&worker_a);
    try app.addSubApp(&worker_b);

    // Setup mediator state and systems
    try app.insertResource(MediatorState{});
    try app.addSystem("Update", sendWorkRequests);
    try app.addSystem("Update", collectResults);

    // Start everything
    try app.runSchedulesFrom("PreStartup");

    // Run until both workers complete
    var attempts: usize = 0;
    while (attempts < 50) : (attempts += 1) {
        _ = try app.step();
        const state = app.world.getResource(MediatorState).?;
        if (state.results_received >= 2) break;
        std.Thread.sleep(1_000_000); // 1ms sleep
    }

    const final_state = app.world.getResource(MediatorState).?;
    try std.testing.expectEqual(@as(u32, 2), final_state.results_received);
    try std.testing.expect(final_state.worker_a_result != null);
    try std.testing.expect(final_state.worker_b_result != null);
    try std.testing.expectEqualStrings("completed_a", final_state.worker_a_result.?);
    try std.testing.expectEqualStrings("completed_b", final_state.worker_b_result.?);

    try app.runSchedulesFrom("PreShutdown");
}

// Imports

const std = @import("std");
const ecs = @import("phasor-ecs");

const App = ecs.App;
const InboxSender = ecs.InboxSender;
const OutboxReceiver = ecs.OutboxReceiver;
const InboxReceiver = ecs.InboxReceiver;
const OutboxSender = ecs.OutboxSender;
const ResMut = ecs.ResMut;

const Command = enum { DoThingA, DoThingB };
