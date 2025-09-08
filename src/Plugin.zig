//! This inspired by Bevy's Plugin system
name: []const u8,
is_unique: bool,

const std = @import("std");
const root = @import("root.zig");
const App = root.App;

pub const Error = error{
    BuildFailed,
};

pub const VTable = struct {
    build: *const fn (app: *App) Error!void,
    ready: *const fn (app: *const App) bool,
    finish: *const fn (app: *App) void,
    cleanup: *const fn (app: *App) void,
};
