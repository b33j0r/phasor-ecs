allocator: std.mem.Allocator,
plugins: std.ArrayListUnmanaged(Plugin) = .empty,
schedules: ScheduleManager,
db: Database,
is_running: bool = false,

const std = @import("std");
const root = @import("root.zig");
const Plugin = root.Plugin;
const ScheduleManager = root.ScheduleManager;
const Schedule = root.Schedule;
const Database = root.db.Database;

const App = @This();

pub const Error = error{
    PluginAlreadyAdded,
};

/// `default` adds the default schedules and plugins to the app.
pub fn default(allocator: std.mem.Allocator) !App {
    var app = App.init(allocator);

    // Add default schedules
    _ = try app.addSchedule("Update");

    // Add default plugins
    try app.addPlugin(&root.FramePlugin{});

    return app;
}

pub fn init(allocator: std.mem.Allocator) App {
    return App{
        .allocator = allocator,
        .plugins = .empty,
        .schedules = ScheduleManager.init(allocator),
        .db = Database.init(allocator),
    };
}

pub fn deinit(self: *App) void {
    // Call cleanup on all plugins, then destroy their instances
    for (self.plugins.items) |*plugin| {
        plugin.cleanup(self);
        plugin.deinit();
    }
    self.plugins.deinit(self.allocator);

    // Deinitialize schedules and database
    self.schedules.deinit();
    self.db.deinit();
}

/// Adds a plugin to the app, enforcing uniqueness if required,
/// and immediately calls its `build` function.
pub fn addPlugin(self: *App, plugin_ptr: anytype) !void {
    const plugin = Plugin.from(self.allocator, plugin_ptr);

    if (plugin.is_unique) {
        for (self.plugins.items) |existing_plugin| {
            if (std.mem.eql(u8, existing_plugin.name, plugin.name)) {
                // no instance to destroy; return error
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

/// Calls step repeatedly in a loop.
pub fn run(self: *App) !void {
    self.is_running = true;
    while (self.is_running) {
        try self.step();
    }
    self.is_running = false;
}

/// Advances the app by one tick/frame.
pub fn step(self: *App) !void {
    var tx = self.db.transaction();

    var schedule_iter = try self.schedules.iterator();
    defer schedule_iter.deinit();
    while (true) {
        const schedule = schedule_iter.next() orelse break;
        try schedule.run(&tx);
    }

    try tx.execute();
}
