const std = @import("std");
const root = @import("root.zig");
const Plugin = root.Plugin;

const App = @This();

pub const RunnerFn = *const fn (app: *const App) Error!void;

pub const Error = error{
    PluginAlreadyAdded,
    NoRunnerFunction,
    RunnerFailed,
};

allocator: std.mem.Allocator,
plugins: std.ArrayListUnmanaged(Plugin) = .empty,
runner_fn: ?RunnerFn,

pub fn init(allocator: std.mem.Allocator) App {
    return App{
        .allocator = allocator,
        .plugins = .empty,
        .runner_fn = null,
    };
}

pub fn deinit(self: *App) void {
    // Call cleanup on all plugins, then destroy their instances
    for (self.plugins.items) |*plugin| {
        plugin.cleanup(self);
        plugin.deinit();
    }
    self.plugins.deinit(self.allocator);
}

pub fn setRunner(self: *App, runnerFn: RunnerFn) void {
    self.runner_fn = runnerFn;
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

/// Runs the app with the configured runner, then calls
/// `finish()` on all plugins once the runner completes.
pub fn run(self: *App) !void {
    if (self.runner_fn) |runner| {
        try runner(self);
    } else {
        return Error.NoRunnerFunction;
    }

    for (self.plugins.items) |plugin| {
        plugin.finish(self);
    }
}
