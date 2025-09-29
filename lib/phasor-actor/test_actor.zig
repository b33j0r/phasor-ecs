const std = @import("std");

const channel_mod = @import("phasor-channel");
const Channel = channel_mod.Channel;

const actor_mod = @import("phasor-actor");
const Actor = actor_mod.Actor;

test "Actor: doubler" {
    const Command = struct {
        value: i32,
    };

    const Response = struct {
        value: i32,
    };

    const DoublerActor = Actor(Command, Response);

    const Worker = struct {
        pub fn step(_: *@This(), cmd: *const Command, outbox: *DoublerActor.Outbox) void {
            outbox.send(Response{ .value = cmd.value * 2 }) catch {
                std.log.err("DoublerActor outbox closed", .{});
            };
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
