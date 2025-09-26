test "Actor map/echo: doubles incoming ints and forwards them" {
    const Doubler = struct {
        pub fn work(_: *@This(), inbox: *Channel(usize).Receiver, outbox: *Channel(usize).Sender) void {
            while (inbox.next()) |v| {
                _ = outbox.send(v * 2) catch unreachable;
            }
        }
    };
    const DoublerActor = Actor(Doubler, usize, usize);

    var actor = DoublerActor.init(std.testing.allocator);
    var impl = Doubler{};
    var h = try actor.spawn(&impl, 16, 16);
    defer h.deinit();

    // Send 1..=10
    var i: usize = 1;
    while (i <= 10) : (i += 1) {
        try h.inbox.send(i);
    }
    h.inbox.close();

    // Drain outputs
    var got_sum: usize = 0;
    var count: usize = 0;
    while (h.outbox.next()) |v| {
        got_sum += v;
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 10), count);
    try std.testing.expectEqual(@as(usize, 110), got_sum); // 2*(1..10)
}

test "Actor reduce/sum: consumes ints and emits a single total" {
    const Summer = struct {
        pub fn work(_: *@This(), inbox: *Channel(i32).Receiver, outbox: *Channel(i32).Sender) void {
            var total: i32 = 0;
            while (inbox.next()) |r| {
                total += r;
            }
            _ = outbox.send(total) catch {};
        }
    };

    const A = Actor(Summer, i32, i32);

    var actor = A.init(std.testing.allocator);
    var impl = Summer{};
    var h = try actor.spawn(&impl, 8, 1);
    defer h.deinit();

    // Send -5..=5 -> sum = 0
    var x: i32 = -5;
    while (x <= 5) : (x += 1) {
        try h.inbox.send(x);
    }
    h.inbox.close();

    const first = h.outbox.recv();
    try std.testing.expect(first != Channel(i32).Error.Closed);
    const val = first catch unreachable;
    try std.testing.expectEqual(@as(i32, 0), val);

    const second = h.outbox.recv();
    try std.testing.expect(second == Channel(i32).Error.Closed);
}

// Imports
const std = @import("std");

const channel_mod = @import("phasor-channel");
const Channel = channel_mod.Channel;

const actor_mod = @import("phasor-actor");
const Actor = actor_mod.Actor;
