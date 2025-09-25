test "Actor definition" {
    const CalculatorCommand = union(enum) {
        Add: i32,
        Subtract: i32,
    };

    const CalculatorEvent = struct {
        result: i32,
    };

    const CalculatorTotal = struct {
        total: i32 = 0,
        steps: usize = 0,
    };

    // The run() function will tear down the apps and their worlds, so we use
    // an indirect resource to be able to check the totals after run() returns.
    const IndirectCalculatorTotal = struct {
        total: *CalculatorTotal,
    };

    const CalculatorActor = ecs.Actor(CalculatorCommand, CalculatorEvent);

    const CalculatorActorSystems = struct {
        pub fn calculate(
            r_total: ecs.ResMut(IndirectCalculatorTotal),
            inbox: ecs.ActorInbox(CalculatorCommand),
            outbox: ecs.ActorOutbox(CalculatorEvent),
        ) !void {
            var total = r_total.ptr.total;
            while (inbox.next()) |cmd| {
                switch (cmd) {
                    .Add => |value| {
                        total.total += value;
                    },
                    .Subtract => |value| {
                        total.total -= value;
                    },
                }
                total.steps += 1;
                try outbox.send(CalculatorEvent{ .result = total.total });
            }
        }
    };

    const MainAppSystems = struct {
        pub fn sendCommands(cmd_writer: ecs.EventWriter(CalculatorCommand)) !void {
            try cmd_writer.send(CalculatorCommand{ .Add = 5 });
            try cmd_writer.send(CalculatorCommand{ .Subtract = 2 });
        }
        pub fn receiveEvents(commands: *ecs.Commands, evt_reader: ecs.EventReader(CalculatorEvent), r_total: ecs.ResMut(IndirectCalculatorTotal)) !void {
            var total = r_total.ptr.total;
            while (try evt_reader.tryRecv()) |evt| {
                total.total = evt.result;
                total.steps += 1;

                if (total.steps == 2) {
                    try commands.insertResource(ecs.Exit{ .code = 33 });
                }
            }
        }
    };

    var actor_total = CalculatorTotal{};
    var app_total = CalculatorTotal{};

    const allocator = std.testing.allocator;
    var actor = CalculatorActor.init(allocator);
    try actor.app.insertResource(IndirectCalculatorTotal{ .total = &actor_total });
    try actor.app.addSystem("Update", CalculatorActorSystems.calculate);

    var main_app = ecs.App.init(allocator);
    try main_app.insertResource(IndirectCalculatorTotal{ .total = &app_total });
    try main_app.addSystem("Update", MainAppSystems.sendCommands);
    try main_app.addSystem("Update", MainAppSystems.receiveEvents);

    try main_app.addActor("Calculator", &actor);

    // Send and receive messages between main app and actor
    const status = try main_app.run();
    try std.testing.expect(status == 33);

    // Check the totals and steps
    try std.testing.expect(app_total.total == 3);
    try std.testing.expect(app_total.steps == 2);

    try std.testing.expect(actor_total.total == 3);
    try std.testing.expect(actor_total.steps == 2);
}

// Imports
const std = @import("std");

const ecs = @import("phasor-ecs");
