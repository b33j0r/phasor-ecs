const std = @import("std");
const ecs = @import("phasor-ecs");
const App = ecs.App;
const Res = ecs.Res;

/// A simple recorder resource that logs events in order.
const Recorder = struct {
    log: std.ArrayListUnmanaged([]const u8) = .empty,
};

/// Creates a system that appends a marker string to the recorder.
fn appendMark(comptime name: []const u8) fn (Res(Recorder)) anyerror!void {
    return struct {
        pub fn run(rec: Res(Recorder)) !void {
            try rec.ptr.log.append(std.testing.allocator, name);
        }
    }.run;
}

/// Utility: cleanup the recorder’s allocated log.
fn cleanupRecorder(app: *App) void {
    var rec_mut = app.world.getResourceMut(Recorder).?;
    rec_mut.log.deinit(app.allocator);
}

test "default schedules execute in expected game order" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    // Add systems into the default frame loop
    try app.addSystem("Startup", appendMark("startup"));
    try app.addSystem("BeginFrame", appendMark("begin"));
    try app.addSystem("Update", appendMark("update"));
    try app.addSystem("Render", appendMark("render"));
    try app.addSystem("EndFrame", appendMark("end"));
    try app.addSystem("Shutdown", appendMark("shutdown"));

    // Run one frame only
    try app.runSchedulesFrom("Startup");
    try app.step(); // runs BeginFrame -> Update -> Render -> EndFrame
    try app.runSchedulesFrom("Shutdown");

    const rec = app.world.getResource(Recorder).?;
    try std.testing.expectEqual(@as(usize, 6), rec.log.items.len);
    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "startup"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "begin"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[2], "update"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[3], "render"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[4], "end"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[5], "shutdown"));

    cleanupRecorder(&app);
}

test "custom game schedule fits between default ones" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    // Add a custom schedule (e.g. physics)
    _ = try app.addSchedule("Physics");

    // Ensure it runs after Update but before Render
    try app.scheduleAfter("Physics", "Update");
    try app.scheduleBefore("Physics", "Render");

    try app.addSystem("Update", appendMark("update"));
    try app.addSystem("Physics", appendMark("physics"));
    try app.addSystem("Render", appendMark("render"));

    try app.step();

    const rec = app.world.getResource(Recorder).?;
    try std.testing.expectEqual(@as(usize, 3), rec.log.items.len);
    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "update"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "physics"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[2], "render"));

    cleanupRecorder(&app);
}

test "between frames schedule runs every tick" {
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    try app.addSystem("BetweenFrames", appendMark("between"));

    // Run two ticks
    try app.step();
    try app.runSchedulesFrom("BetweenFrames");
    try app.step();
    try app.runSchedulesFrom("BetweenFrames");

    const rec = app.world.getResource(Recorder).?;
    // We only added to BetweenFrames, so we should see two entries.
    try std.testing.expectEqual(@as(usize, 2), rec.log.items.len);
    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "between"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "between"));

    cleanupRecorder(&app);
}

test "App plugins can be registered" {
    const allocator = std.testing.allocator;

    const MyPlugin = struct {
        build_called: bool = false,
        ready_called: bool = false,
        finish_called: bool = false,
        cleanup_called: bool = false,

        pub const Self = @This();
        pub fn build(self: *Self, _: *App) anyerror!void {
            self.build_called = true;
        }
        pub fn cleanup(self: *Self, _: *App) void {
            self.cleanup_called = true;
        }
    };

    var my_plugin = MyPlugin{};

    var app = try App.default(allocator);
    try app.addPlugin(&my_plugin);
    app.deinit();

    try std.testing.expect(my_plugin.build_called);
    try std.testing.expect(my_plugin.cleanup_called);
}

test "App plugins can be added as inline structs" {
    const allocator = std.testing.allocator;

    const BuildCalled = struct {};

    const MyPlugin = struct {
        pub const Self = @This();
        pub fn build(_: *Self, app: *App) anyerror!void {
            try app.insertResource(BuildCalled{});
        }
    };

    var app = try App.default(allocator);
    try app.addPlugin(MyPlugin{});
    defer app.deinit();

    try std.testing.expect(app.world.hasResource(BuildCalled));
}

test "App respects Exit resource" {
    // Run an app with a system that adds the Exit resource
    const allocator = std.testing.allocator;
    var app = try App.default(allocator);
    defer app.deinit();

    const exit_system = struct {
        pub fn run(commands: *ecs.Commands) !void {
            _ = try commands.insertResource(App.Exit{ .code = 42 });
        }
    }.run;

    try app.addSystem("Update", exit_system);
    const exit_code = try app.run();
    try std.testing.expectEqual(exit_code, 42);
}
