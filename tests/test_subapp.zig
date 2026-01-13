const std = @import("std");
const ecs = @import("phasor-ecs");

const App = ecs.App;
const ResMut = ecs.ResMut;
const Commands = ecs.Commands;
const SubApp = ecs.SubApp;

test "SubApp: main -> echo -> main" {
    const child_allocator = std.testing.allocator;
    var thread_safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = child_allocator };
    const allocator = thread_safe_allocator.allocator();

    const ChildCommand = union(enum) {
        echo: u32,
    };

    const ChildEvent = union(enum) {
        echoed: u32,
    };

    const ChildApp = SubApp(ChildCommand, ChildEvent);
    const InboxReceiver = ChildApp.InboxReceiver;
    const OutboxSender = ChildApp.OutboxSender;
    const InboxSender = ChildApp.InboxSender;
    const OutboxReceiver = ChildApp.OutboxReceiver;

    const ChildAppSystems = struct {
        pub fn startup() !void {
            std.log.info("ChildApp: Startup", .{});
        }
        pub fn shutdown() !void {
            std.log.info("ChildApp: Shutdown", .{});
        }
        pub fn echo(inbox: InboxReceiver, outbox: OutboxSender) !void {
            while (try inbox.tryRecv()) |msg| {
                switch (msg) {
                    .echo => |value| {
                        std.log.info("ChildApp: Received echo {d}", .{value});
                        try outbox.send(.{ .echoed = value });
                    },
                }
            }
        }
    };

    const MainAppSystems = struct {
        pub fn startup() !void {
            std.log.info("MainApp: Startup", .{});
        }
        pub fn shutdown() !void {
            std.log.info("MainApp: Shutdown", .{});
        }
        pub fn send_echo(inbox: InboxSender) !void {
            try inbox.send(.{ .echo = 42 });
            std.log.info("MainApp: Sent echo 42", .{});
        }
        pub fn receive_echo(commands: *Commands, outbox: OutboxReceiver) !void {
            while (try outbox.tryRecv()) |msg| {
                switch (msg) {
                    .echoed => |value| {
                        std.log.info("MainApp: Received echoed {d}", .{value});
                        try std.testing.expect(value == 42);
                        // Exit after receiving the echoed message
                        try commands.insertResource(App.Exit{ .code = @intCast(value) });
                    },
                }
            }
        }
    };

    // Initialize the child app
    var child_app = try ChildApp.init(allocator, .{
        .inbox_capacity = 10,
        .outbox_capacity = 10,
    });
    defer child_app.deinit();

    try child_app.app.addSystem("Update", ChildAppSystems.echo);

    // Initialize the main app
    var app = try App.default(allocator);
    defer app.deinit();

    // Debug systems
    try app.addSystem("Startup", MainAppSystems.startup);
    try app.addSystem("Shutdown", MainAppSystems.shutdown);
    try child_app.app.addSystem("Startup", ChildAppSystems.startup);
    try child_app.app.addSystem("Shutdown", ChildAppSystems.shutdown);

    try app.addSystem("Startup", MainAppSystems.send_echo);
    try app.addSystem("Update", MainAppSystems.receive_echo);

    // Add the child app as a SubApp by adding the Plugin
    try app.addPlugin(ChildApp.Plugin{ .subapp = &child_app });

    // Run the main app
    const exit = try app.run();
    try std.testing.expect(exit == 42);
}
