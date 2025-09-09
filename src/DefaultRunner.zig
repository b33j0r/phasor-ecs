//! Default runner for phasor-ecs.
//! Runs the app once by invoking all plugin `ready` checks, then executing an update cycle.

const std = @import("std");
const root = @import("root.zig");
const App = root.App;
const Plugin = root.Plugin;

pub fn run(app: *const App) App.Error!void {
    // Verify all plugins are "ready" before proceeding.
    for (app.plugins.items) |plugin| {
        if (!plugin.ready(app)) {
            return App.Error.RunnerFailed;
        }
    }

    // In the minimal runner, we just log and exit.
    // Replace this with a loop for a real game/application.
    std.debug.print("DefaultRunner: app ran successfully\n", .{});
    return;
}
