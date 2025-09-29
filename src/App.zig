allocator: std.mem.Allocator,
plugins: std.ArrayListUnmanaged(Plugin) = .empty,
schedules: ScheduleManager,
world: World,
subapps: std.ArrayListUnmanaged(SubAppHandle) = .empty,
step_start_schedule_name: []const u8 = "BeginFrame",

const App = @This();

pub const Error = error{
    PluginAlreadyAdded,
};

pub const Exit = struct {
    code: u8,
};

/// `default` adds the default schedules and plugins to the app.
pub fn default(allocator: std.mem.Allocator) !App {
    var app = App.init(allocator);

    // Add default schedules
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

pub fn init(allocator: std.mem.Allocator) App {
    return App{
        .allocator = allocator,
        .plugins = .empty,
        .schedules = ScheduleManager.init(allocator),
        .world = World.init(allocator),
    };
}

pub fn deinit(self: *App) void {
    // Stop and deinitialize all SubApps first
    for (self.subapps.items) |subapp_handle| {
        subapp_handle.stop();
        subapp_handle.deinit();
    }
    self.subapps.deinit(self.allocator);

    // Call cleanup on all plugins, then destroy their instances
    for (self.plugins.items) |*plugin| {
        plugin.cleanup(self);
        plugin.deinit();
    }
    self.plugins.deinit(self.allocator);

    // Deinitialize schedules and database
    self.schedules.deinit();
    self.world.deinit();
}

/// Adds a plugin to the app, enforcing uniqueness if required,
/// and immediately calls its `build` function.
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

/// Add or get a schedule by name
pub fn addSchedule(self: *App, name: []const u8) !*Schedule {
    return try self.schedules.addSchedule(name);
}

pub fn removeSchedule(self: *App, name: []const u8) !void {
    return self.schedules.removeSchedule(name);
}

/// Add a system function to a schedule by name
pub fn addSystem(self: *App, schedule_name: []const u8, comptime system_fn: anytype) !void {
    try self.schedules.addSystem(schedule_name, system_fn);
}

/// Constrain schedule execution order: name must run before other
pub fn scheduleBefore(self: *App, name: []const u8, other: []const u8) !void {
    try self.schedules.scheduleBefore(name, other);
}

/// Constrain schedule execution order: name must run after other
pub fn scheduleAfter(self: *App, name: []const u8, other: []const u8) !void {
    try self.schedules.scheduleAfter(name, other);
}

/// Constrain schedule execution order: name must run after first and before last
pub fn scheduleBetween(self: *App, name: []const u8, first: []const u8, last: []const u8) !void {
    try self.schedules.scheduleBetween(name, first, last);
}

/// Add a new schedule and constrain its execution order between first and last
pub fn addScheduleBetween(self: *App, name: []const u8, first: []const u8, last: []const u8) !*Schedule {
    return try self.schedules.addScheduleBetween(name, first, last);
}

pub fn runSchedulesFrom(self: *App, start: []const u8) !void {
    // If starting from PreStartup, start all SubApps first
    if (std.mem.eql(u8, start, "PreStartup")) {
        for (self.subapps.items) |subapp_handle| {
            try subapp_handle.start(self);
        }
    }
    
    var schedule_iter = try self.schedules.iterator(start);
    defer schedule_iter.deinit();
    while (schedule_iter.next()) |schedule| {
        try schedule.run(&self.world);
    }
}

/// Advances the app by one tick/frame.
pub fn step(self: *App) !?Exit {
    try self.runSchedulesFrom(self.step_start_schedule_name);
    if (self.world.getResource(Exit)) |exit| {
        return exit.*;
    }
    try self.runSchedulesFrom("BetweenFrames");
    return null;
}

/// Calls step repeatedly in a loop.
pub fn run(self: *App) !u8 {
    try self.runSchedulesFrom("PreStartup");
    const exit_res: Exit = blk: while (true) {
        if (try self.step()) |exit| {
            break :blk exit;
        }
    };
    try self.runSchedulesFrom("PreShutdown");
    return exit_res.code;
}

/// Adds a resource to the world.
pub fn insertResource(self: *App, resource: anytype) !void {
    try self.world.insertResource(resource);
}

/// Gets a resource from the world, returning null if it doesn't exist.
pub fn getResource(self: *App, comptime T: type) ?*T {
    return self.world.getResource(T);
}

pub fn hasResource(self: *App, comptime T: type) bool {
    return self.world.hasResource(T);
}

pub fn removeResource(self: *App, comptime T: type) bool {
    return self.world.removeResource(T);
}

/// Registers an event type in the world. Under the hood this
/// simply inserts an `Events(T)` resource.
pub fn registerEvent(self: *App, comptime T: type, capacity: usize) !void {
    try self.world.registerEvent(T, capacity);
}

/// Adds a SubApp to be managed by this App. SubApps will be started
/// automatically during the PreStartup phase.
pub fn addSubApp(self: *App, subapp: anytype) !void {
    const handle = subapp.toHandle();
    try self.subapps.append(self.allocator, handle);
}


// Imports
const std = @import("std");

const root = @import("root.zig");
const Plugin = root.Plugin;
const ScheduleManager = root.ScheduleManager;
const Schedule = root.Schedule;
const World = root.World;
const Events = root.Events;
const SubApp = root.SubApp;
const SubAppHandle = root.SubAppHandle;
