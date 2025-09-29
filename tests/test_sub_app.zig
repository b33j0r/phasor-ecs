const std = @import("std");
const ecs = @import("phasor-ecs");

const App = ecs.App;
const InboxSender = ecs.InboxSender;
const OutboxReceiver = ecs.OutboxReceiver;
const InboxReceiver = ecs.InboxReceiver;
const OutboxSender = ecs.OutboxSender;
const ResMut = ecs.ResMut;

// ---------- Small util: stepUntil with timeout ----------
fn stepUntil(app: *App, ns_budget: u64, max_steps: usize, predicate: fn (*App) bool) !bool {
    var steps: usize = 0;
    const start = std.time.nanoTimestamp();
    while (steps < max_steps and (std.time.nanoTimestamp() - start) < ns_budget) : (steps += 1) {
        _ = try app.step();
        if (predicate(app)) return true;
        std.Thread.sleep(500_000); // 0.5ms
    }
    return false;
}

// =====================================================================================
// Test 0: SubApp round trip
// =====================================================================================

const Command = enum { DoThingA, DoThingB };
const Reply = union(enum) { Sincere: []const u8, Snarky: []const u8 };

const SendState = struct { sent: bool = false };
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
    while (inbox.tryRecv()) |cmd| switch (cmd) {
        .DoThingA => try outbox.send(.{ .Sincere = "thanks" }),
        .DoThingB => try outbox.send(.{ .Snarky = "sure" }),
    };
}

test "SubApp forwards commands across thread boundary (precise payloads, order)" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    var subapp = try ecs.SubApp(Command, Reply).init(allocator, .{ .inbox_capacity = 8, .outbox_capacity = 8 });
    try subapp.addSystem("Update", processCommands);
    try app.addSubApp(&subapp);

    try app.insertResource(SendState{});
    try app.insertResource(ReplyLog{ .allocator = allocator });
    try app.addSystem("Update", sendToActor);
    try app.addSystem("Update", recvFromActor);

    // Explicit start
    try subapp.start(&app);

    const ok = try stepUntil(&app, 250_000_000, 100, struct {
        fn pred(app_: *App) bool {
            const log = app_.world.getResource(ReplyLog).?;
            return log.replies.items.len >= 2;
        }
    }.pred);
    try std.testing.expect(ok);

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

    // App.deinit() will handle subapp cleanup automatically
}

// =====================================================================================
// Test 1: Nested SubApps
// =====================================================================================

const P3Msg = union(enum) { Ping: u32, Fwd: u32, Resp: u32, Pong: u32 };
const P3State = struct { sent: u32 = 0, want: u32 = 0, got: u32 = 0 };

fn p3_sender(state: ResMut(P3State), mid_in: InboxSender(P3Msg)) !void {
    if (state.ptr.want == 0) {
        var i: u32 = 0;
        while (i < 64) : (i += 1) {
            try mid_in.send(.{ .Ping = i });
            state.ptr.sent += 1;
        }
        state.ptr.want = 64;
    }
}
fn p3_recv(state: ResMut(P3State), mid_out: OutboxReceiver(P3Msg)) !void {
    while (mid_out.tryRecv()) |m| switch (m) {
        .Pong => |_| state.ptr.got += 1,
        else => {},
    };
}
fn middle_forward_down(inbox: InboxReceiver(P3Msg), leaf_in: InboxSender(P3Msg)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Ping => |v| try leaf_in.send(.{ .Fwd = v }),
        else => {},
    };
}
fn middle_forward_up(leaf_out: OutboxReceiver(P3Msg), outbox: OutboxSender(P3Msg)) !void {
    while (leaf_out.tryRecv()) |m| switch (m) {
        .Resp => |v| try outbox.send(.{ .Pong = v }),
        else => {},
    };
}
fn leaf_echo(inbox: InboxReceiver(P3Msg), outbox: OutboxSender(P3Msg)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Fwd => |v| try outbox.send(.{ .Resp = v }),
        else => {},
    };
}

test "Nested SubApps: App→Middle→Leaf ping flood" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    var leaf = try ecs.SubApp(P3Msg, P3Msg).init(allocator, .{ .inbox_capacity = 4, .outbox_capacity = 4 });
    try leaf.addSystem("Update", leaf_echo);

    var middle = try ecs.SubApp(P3Msg, P3Msg).init(allocator, .{ .inbox_capacity = 4, .outbox_capacity = 4 });
    try middle.addSubApp(&leaf);
    try middle.addSystem("Update", middle_forward_down);
    try middle.addSystem("Update", middle_forward_up);

    try app.addSubApp(&middle);

    try app.insertResource(P3State{});
    try app.addSystem("Update", p3_sender);
    try app.addSystem("Update", p3_recv);

    try leaf.start(&middle.app);
    try middle.start(&app);

    const done = try stepUntil(&app, 2_000_000_000, 4000, struct {
        fn pred(app_: *App) bool {
            const s = app_.world.getResource(P3State).?;
            return (s.want > 0) and (s.got == s.want);
        }
    }.pred);
    try std.testing.expect(done);

    // App.deinit() will handle subapp cleanup automatically
}

// =====================================================================================
// Test 2: Two independent worker SubApps
// =====================================================================================

const WorkerAMessage = union(enum) { Task: []const u8 };
const WorkerAReply = union(enum) { Result: []const u8 };
const WorkerBMessage = union(enum) { Task: []const u8 };
const WorkerBReply = union(enum) { Result: []const u8 };

const MediatorState = struct { sent: bool = false, results: u32 = 0, ra: ?[]const u8 = null, rb: ?[]const u8 = null };

fn med_send(s: ResMut(MediatorState), a_in: InboxSender(WorkerAMessage), b_in: InboxSender(WorkerBMessage)) !void {
    if (!s.ptr.sent) {
        try a_in.send(.{ .Task = "task_a" });
        try b_in.send(.{ .Task = "task_b" });
        s.ptr.sent = true;
    }
}
fn med_recv(s: ResMut(MediatorState), a_out: OutboxReceiver(WorkerAReply), b_out: OutboxReceiver(WorkerBReply)) !void {
    while (a_out.tryRecv()) |m| switch (m) {
        .Result => |r| {
            s.ptr.ra = r;
            s.ptr.results += 1;
        },
    };
    while (b_out.tryRecv()) |m| switch (m) {
        .Result => |r| {
            s.ptr.rb = r;
            s.ptr.results += 1;
        },
    };
}
fn workerA(inbox: InboxReceiver(WorkerAMessage), outbox: OutboxSender(WorkerAReply)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |t| if (std.mem.eql(u8, t, "task_a")) try outbox.send(.{ .Result = "completed_a" }),
    };
}
fn workerB(inbox: InboxReceiver(WorkerBMessage), outbox: OutboxSender(WorkerBReply)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |t| if (std.mem.eql(u8, t, "task_b")) try outbox.send(.{ .Result = "completed_b" }),
    };
}

test "Main mediates two concurrent SubApps with exact result join" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    var a = try ecs.SubApp(WorkerAMessage, WorkerAReply).init(allocator, .{ .inbox_capacity = 2, .outbox_capacity = 2 });
    var b = try ecs.SubApp(WorkerBMessage, WorkerBReply).init(allocator, .{ .inbox_capacity = 2, .outbox_capacity = 2 });
    try a.addSystem("Update", workerA);
    try b.addSystem("Update", workerB);

    try app.addSubApp(&a);
    try app.addSubApp(&b);

    try app.insertResource(MediatorState{});
    try app.addSystem("Update", med_send);
    try app.addSystem("Update", med_recv);

    try a.start(&app);
    try b.start(&app);

    const ok = try stepUntil(&app, 500_000_000, 200, struct {
        fn pred(app_: *App) bool {
            const s = app_.world.getResource(MediatorState).?;
            return s.results >= 2;
        }
    }.pred);
    try std.testing.expect(ok);

    // App.deinit() will handle subapp cleanup automatically
}

// =====================================================================================
// Test 3: Burst 1,000 tasks
// =====================================================================================

const BurstMsg = union(enum) { Task: u32, Done: void };
const BurstRep = union(enum) { Ok: u32, Ack: void };
const BurstState = struct { issued: u32 = 0, received: u32 = 0, finished: bool = false };

fn burst_issue(s: ResMut(BurstState), mid_in: InboxSender(BurstMsg)) !void {
    if (s.ptr.issued == 0) {
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            try mid_in.send(.{ .Task = i });
            s.ptr.issued += 1;
        }
        try mid_in.send(.Done);
    }
}
fn burst_collect(s: ResMut(BurstState), mid_out: OutboxReceiver(BurstRep)) !void {
    while (mid_out.tryRecv()) |m| switch (m) {
        .Ok => |_| s.ptr.received += 1,
        .Ack => s.ptr.finished = true,
    };
}
fn mid_burst_down(inbox: InboxReceiver(BurstMsg), leaf_in: InboxSender(BurstMsg)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |v| try leaf_in.send(.{ .Task = v }),
        .Done => try leaf_in.send(.Done),
    };
}
fn mid_burst_up(leaf_out: OutboxReceiver(BurstRep), outbox: OutboxSender(BurstRep)) !void {
    while (leaf_out.tryRecv()) |m| switch (m) {
        .Ok => |v| try outbox.send(.{ .Ok = v }),
        .Ack => try outbox.send(.Ack),
    };
}
fn leaf_burst(inbox: InboxReceiver(BurstMsg), outbox: OutboxSender(BurstRep)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |v| try outbox.send(.{ .Ok = v }),
        .Done => try outbox.send(.Ack),
    };
}

test "Backpressure stress: 1,000 message burst across nested threads with tiny queues" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    var leaf = try ecs.SubApp(BurstMsg, BurstRep).init(allocator, .{ .inbox_capacity = 8, .outbox_capacity = 8 });
    try leaf.addSystem("Update", leaf_burst);

    var mid = try ecs.SubApp(BurstMsg, BurstRep).init(allocator, .{ .inbox_capacity = 8, .outbox_capacity = 8 });
    try mid.addSubApp(&leaf);
    try mid.addSystem("Update", mid_burst_down);
    try mid.addSystem("Update", mid_burst_up);

    try app.addSubApp(&mid);

    try app.insertResource(BurstState{});
    try app.addSystem("Update", burst_issue);
    try app.addSystem("Update", burst_collect);

    try leaf.start(&mid.app);
    try mid.start(&app);

    const ok = try stepUntil(&app, 3_000_000_000, 10_000, struct {
        fn pred(app_: *App) bool {
            const s = app_.world.getResource(BurstState).?;
            return s.finished and s.received == s.issued and s.issued == 1000;
        }
    }.pred);
    try std.testing.expect(ok);

    // App.deinit() will handle subapp cleanup automatically
}
