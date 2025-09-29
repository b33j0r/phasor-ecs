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
        // tiny sleep to allow subapp threads to run without burning CPU
        std.Thread.sleep(500_000); // 0.5ms
    }
    return false;
}

// =====================================================================================
// Test 0: SubApp round trip (simple Command/Reply)
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
}

// =====================================================================================
// Test 1: Nested SubApps — Producer (leaf) ↔ Middleman (nested) ↔ Consumer (main)
// =====================================================================================

// Consumer → Middleman
const ConsumerToMiddle = union(enum) { Produce: u32 };
// Middleman → Consumer
const MiddleToConsumer = union(enum) { Done: u32 };

// Middleman → Producer
const MiddleToProducer = union(enum) { Work: u32 };
// Producer → Middleman
const ProducerToMiddle = union(enum) { Result: u32 };

const PipelineState = struct { sent: u32 = 0, want: u32 = 0, got: u32 = 0 };

fn consumer_send(state: ResMut(PipelineState), mid_in: InboxSender(ConsumerToMiddle)) !void {
    if (state.ptr.want == 0) {
        var i: u32 = 0;
        while (i < 64) : (i += 1) {
            try mid_in.send(.{ .Produce = i });
            state.ptr.sent += 1;
        }
        state.ptr.want = 64;
    }
}
fn consumer_recv(state: ResMut(PipelineState), mid_out: OutboxReceiver(MiddleToConsumer)) !void {
    while (mid_out.tryRecv()) |m| switch (m) {
        .Done => |_| state.ptr.got += 1,
    };
}

// Middleman: forward down to Producer
fn middle_forward_down(
    inbox_from_consumer: InboxReceiver(ConsumerToMiddle),
    to_producer: InboxSender(MiddleToProducer),
) !void {
    while (inbox_from_consumer.tryRecv()) |m| switch (m) {
        .Produce => |v| try to_producer.send(.{ .Work = v }),
    };
}

// Middleman: forward up to Consumer
fn middle_forward_up(
    from_producer: OutboxReceiver(ProducerToMiddle),
    outbox_to_consumer: OutboxSender(MiddleToConsumer),
) !void {
    while (from_producer.tryRecv()) |m| switch (m) {
        .Result => |v| try outbox_to_consumer.send(.{ .Done = v }),
    };
}

// Producer: echo work -> result
fn producer_echo(inbox: InboxReceiver(MiddleToProducer), outbox: OutboxSender(ProducerToMiddle)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Work => |v| try outbox.send(.{ .Result = v }),
    };
}

test "Nested SubApps: Consumer→Middleman→Producer ping flood with distinct message types" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    // Producer (leaf)
    var producer = try ecs.SubApp(MiddleToProducer, ProducerToMiddle).init(allocator, .{ .inbox_capacity = 4, .outbox_capacity = 4 });
    try producer.addSystem("Update", producer_echo);

    // Middleman (nested)
    var middle = try ecs.SubApp(ConsumerToMiddle, MiddleToConsumer).init(allocator, .{ .inbox_capacity = 4, .outbox_capacity = 4 });
    try middle.addSubApp(&producer);
    try middle.addSystem("Update", middle_forward_down);
    try middle.addSystem("Update", middle_forward_up);

    // Consumer (main)
    try app.addSubApp(&middle);

    try app.insertResource(PipelineState{});
    try app.addSystem("Update", consumer_send);
    try app.addSystem("Update", consumer_recv);

    // Start leaf within middle; then middle within app
    try producer.start(&middle.app);
    try middle.start(&app);

    const done = try stepUntil(&app, 2_000_000_000, 4000, struct {
        fn pred(app_: *App) bool {
            const s = app_.world.getResource(PipelineState).?;
            return (s.want > 0) and (s.got == s.want);
        }
    }.pred);
    try std.testing.expect(done);
}

// =====================================================================================
// Test 2: Two independent worker SubApps (already distinct types; minor polish)
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
            return s.results >= 2 and s.ra != null and s.rb != null;
        }
    }.pred);
    try std.testing.expect(ok);
}

// =====================================================================================
// Test 3: Burst 1,000 tasks across nested SubApps (distinct types per hop)
// =====================================================================================

// Consumer → Middleman
const Burst_ConsumerToMiddle = union(enum) { Task: u32, Done: void };
// Middleman → Consumer
const Burst_MiddleToConsumer = union(enum) { Ok: u32, Ack: void };

// Middleman → Producer
const Burst_MiddleToProducer = union(enum) { Task: u32, Done: void };
// Producer → Middleman
const Burst_ProducerToMiddle = union(enum) { Ok: u32, Ack: void };

const BurstState = struct { issued: u32 = 0, received: u32 = 0, finished: bool = false };

fn burst_issue(s: ResMut(BurstState), mid_in: InboxSender(Burst_ConsumerToMiddle)) !void {
    if (s.ptr.issued == 0) {
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            try mid_in.send(.{ .Task = i });
            s.ptr.issued += 1;
        }
        try mid_in.send(.Done);
    }
}
fn burst_collect(s: ResMut(BurstState), mid_out: OutboxReceiver(Burst_MiddleToConsumer)) !void {
    while (mid_out.tryRecv()) |m| switch (m) {
        .Ok => |_| s.ptr.received += 1,
        .Ack => s.ptr.finished = true,
    };
}
fn mid_burst_down(inbox: InboxReceiver(Burst_ConsumerToMiddle), leaf_in: InboxSender(Burst_MiddleToProducer)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |v| try leaf_in.send(.{ .Task = v }),
        .Done => try leaf_in.send(.Done),
    };
}
fn mid_burst_up(leaf_out: OutboxReceiver(Burst_ProducerToMiddle), outbox: OutboxSender(Burst_MiddleToConsumer)) !void {
    while (leaf_out.tryRecv()) |m| switch (m) {
        .Ok => |v| try outbox.send(.{ .Ok = v }),
        .Ack => try outbox.send(.Ack),
    };
}
fn leaf_burst(inbox: InboxReceiver(Burst_MiddleToProducer), outbox: OutboxSender(Burst_ProducerToMiddle)) !void {
    while (inbox.tryRecv()) |m| switch (m) {
        .Task => |v| try outbox.send(.{ .Ok = v }),
        .Done => try outbox.send(.Ack),
    };
}

test "Backpressure stress: 1,000 message burst across nested threads with tiny queues (distinct Ts)" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    var producer = try ecs.SubApp(Burst_MiddleToProducer, Burst_ProducerToMiddle).init(allocator, .{ .inbox_capacity = 8, .outbox_capacity = 8 });
    try producer.addSystem("Update", leaf_burst);

    var middle = try ecs.SubApp(Burst_ConsumerToMiddle, Burst_MiddleToConsumer).init(allocator, .{ .inbox_capacity = 8, .outbox_capacity = 8 });
    try middle.addSubApp(&producer);
    try middle.addSystem("Update", mid_burst_down);
    try middle.addSystem("Update", mid_burst_up);

    try app.addSubApp(&middle);

    try app.insertResource(BurstState{});
    try app.addSystem("Update", burst_issue);
    try app.addSystem("Update", burst_collect);

    try producer.start(&middle.app);
    try middle.start(&app);

    const ok = try stepUntil(&app, 3_000_000_000, 10_000, struct {
        fn pred(app_: *App) bool {
            const s = app_.world.getResource(BurstState).?;
            return s.finished and s.received == s.issued and s.issued == 1000;
        }
    }.pred);
    try std.testing.expect(ok);
}
