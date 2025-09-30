const std = @import("std");

const channel_mod = @import("phasor-channel");
const Channel = channel_mod.Channel;

const phasor_actor = @import("phasor-actor");
const Actor = phasor_actor.Actor;
const Signal = phasor_actor.Signal;

test "Actor: doubler" {
    const Command = struct {
        value: i32,
    };

    const Response = struct {
        value: i32,
    };

    const DoublerActor = Actor(Command, Response);

    const Worker = struct {
        pub fn work(
            _: *@This(),
            inbox: *DoublerActor.Inbox,
            outbox: *DoublerActor.Outbox,
            stop_signal: Signal(bool),
        ) !void {
            while (!stop_signal.get()) {
                // Try to receive a command
                if (try inbox.tryRecv()) |cmd| {
                    // Process the command
                    const result = cmd.value * 2;
                    // Send the response
                    try outbox.send(Response{ .value = result });
                    continue;
                } else {
                    std.Thread.sleep(1);
                    continue;
                }
            }
        }
    };

    const allocator = std.testing.allocator;
    var context = Worker{}; // borrowed by the actor

    var a = DoublerActor.init(allocator);
    var actor = try a.spawn(
        &context, // pass pointer; actor borrows your context
        .{
            .inbox_capacity = 4,
            .outbox_capacity = 4,
        },
    );
    defer actor.deinit();

    // Send commands
    try actor.send(.{ .value = 10 });
    try actor.send(.{ .value = 25 });

    // Receive responses
    const resp1 = try actor.recv();
    try std.testing.expectEqual(@as(i32, 20), resp1.value);

    const resp2 = try actor.recv();
    try std.testing.expectEqual(@as(i32, 50), resp2.value);

    // Stop the actor with a 1 second timeout
    try actor.waitForStop(1000);
}
