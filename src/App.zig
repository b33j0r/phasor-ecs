const std = @import("std");

const root = @import("root.zig");
const Plugin = root.Plugin;
const ScheduleManager = root.ScheduleManager;
const Schedule = root.Schedule;
const World = root.World;
const Events = root.Events;

allocator: std.mem.Allocator,
plugins: std.ArrayListUnmanaged(Plugin) = .empty,
schedules: ScheduleManager,
world: World,
step_start_schedule_name: []const u8 = "BeginFrame",

const App = @This();

pub const Error = error{
    PluginAlreadyAdded,
};

pub const Exit = struct { code: u8 };

/// Default schedules
pub fn default(allocator: std.mem.Allocator) !App {
    var app = App.initEmpty(allocator);

    _ = try app.addSchedule("PreStartup");
    _ = try app.addSchedule("Startup");
    _ = try app.addSchedule("PostStartup");
    try app.scheduleAfter("Startup", "PreStartup");
    try app.scheduleAfter("PostStartup", "Startup");

    _ = try app.addSchedule("PreShutdown");
    _ = try app.addSchedule("Shutdown");
    _ = try app.addSchedule("PostShutdown");
    try app.scheduleAfter("Shutdown", "PreShutdown");
    try app.scheduleAfter("PostShutdown", "Shutdown");

    _ = try app.addSchedule("BetweenFrames");

    _ = try app.addSchedule("BeginFrame");
    _ = try app.addSchedule("Update");
    _ = try app.addSchedule("Render");
    _ = try app.addSchedule("EndFrame");

    try app.scheduleAfter("Update", "BeginFrame");
    try app.scheduleBefore("Render", "EndFrame");
    try app.scheduleAfter("Render", "Update");

    return app;
}

pub fn initEmpty(allocator: std.mem.Allocator) App {
    return App{
        .allocator = allocator,
        .plugins = .empty,
        .schedules = ScheduleManager.init(allocator),
        .world = World.init(allocator),
    };
}

pub fn deinit(self: *App) void {
    for (self.plugins.items) |*plugin| {
        plugin.cleanup(self) catch |err| {
            std.log.err("Error during plugin cleanup: {any}", .{err});
        };
        plugin.deinit();
    }
    self.plugins.deinit(self.allocator);

    self.schedules.deinit();
    self.world.deinit();
}

pub fn addPlugin(self: *App, plugin_or_ptr: anytype) !void {
    const plugin = try Plugin.from(self.allocator, plugin_or_ptr);

    if (plugin.is_unique) {
        for (self.plugins.items) |existing_plugin| {
            if (std.mem.eql(u8, existing_plugin.name, plugin.name)) {
                return Error.PluginAlreadyAdded;
            }
        }
    }

    try self.plugins.append(self.allocator, plugin);
    try self.plugins.items[self.plugins.items.len - 1].build(self);
}

pub fn addSchedule(self: *App, name: []const u8) !*Schedule {
    return try self.schedules.addSchedule(name);
}
pub fn removeSchedule(self: *App, name: []const u8) !void {
    return self.schedules.removeSchedule(name);
}
pub fn addSystem(self: *App, schedule_name: []const u8, comptime system_fn: anytype) !void {
    try self.schedules.addSystem(schedule_name, system_fn, &self.world);
}
pub fn scheduleBefore(self: *App, name: []const u8, other: []const u8) !void {
    try self.schedules.scheduleBefore(name, other);
}
pub fn scheduleAfter(self: *App, name: []const u8, other: []const u8) !void {
    try self.schedules.scheduleAfter(name, other);
}
pub fn scheduleBetween(self: *App, name: []const u8, first: []const u8, last: []const u8) !void {
    try self.schedules.scheduleBetween(name, first, last);
}
pub fn addScheduleBetween(self: *App, name: []const u8, first: []const u8, last: []const u8) !*Schedule {
    return try self.schedules.addScheduleBetween(name, first, last);
}

pub fn runSchedulesFrom(self: *App, start: []const u8) !void {
    var iter = try self.schedules.iterator(start);
    defer iter.deinit();
    while (iter.next()) |schedule| {
        try schedule.run(&self.world);
    }
}

pub fn runStartupSchedules(self: *App) !void {
    try self.runSchedulesFrom("PreStartup");
}

pub fn runShutdownSchedules(self: *App) !void {
    try self.runSchedulesFrom("PreShutdown");
}

pub fn run(self: *App) !u8 {
    try self.runStartupSchedules();
    const exit_res: Exit = blk: while (true) {
        if (try self.step()) |exit| break :blk exit;
    };
    try self.runShutdownSchedules();
    return exit_res.code;
}

pub fn step(self: *App) !?Exit {
    try self.runSchedulesFrom(self.step_start_schedule_name);
    if (self.world.getResource(Exit)) |exit| return exit.*;
    try self.runSchedulesFrom("BetweenFrames");
    return null;
}

pub fn insertResource(self: *App, resource: anytype) !void {
    try self.world.insertResource(resource);
}
pub fn getResource(self: *App, comptime T: type) ?*T {
    return self.world.getResource(T);
}
pub fn hasResource(self: *App, comptime T: type) bool {
    return self.world.hasResource(T);
}
pub fn removeResource(self: *App, comptime T: type) bool {
    return self.world.removeResource(T);
}
pub fn registerEvent(self: *App, comptime T: type, capacity: usize) !void {
    try self.world.registerEvent(T, capacity);
}
