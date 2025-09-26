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

    var subapp = try App.subapp(allocator, Command, Reply);
    defer subapp.deinit();

    try subapp.addSystem("Update", processCommands);
    try subapp.start(&app, .{ .inbox_capacity = 8, .outbox_capacity = 8 });

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
