//! Inspired by Bevy's Plugin system: a plugin encapsulates setup logic
//! (adding systems, resources, etc) and participates in the app lifecycle.

const std = @import("std");
const root = @import("root.zig");
const App = root.App;

const Plugin = @This();

pub const Error = error{
    BuildFailed,
};

pub const VTable = struct {
    // Thunks that receive an erased self pointer
    build: ?*const fn (*anyopaque, *App) Error!void,
    ready: ?*const fn (*anyopaque, *const App) bool,
    finish: ?*const fn (*anyopaque, *App) void,
    cleanup: ?*const fn (*anyopaque, *App) void,
    destroy: *const fn (std.mem.Allocator, *anyopaque) void, // no-op when user provides instance
};

name: []const u8,
is_unique: bool,
self_ptr: *anyopaque,
vtable: VTable,
allocator: std.mem.Allocator,

/// Create a `Plugin` from a user-provided plugin pointer.
/// The plugin type can have:
///   - Optional `pub const name: []const u8` (defaults to type name)
///   - Optional `pub const is_unique: bool` (defaults to true)
///   - Optional `pub fn build(self: *T, app: *App) !void`
///   - Optional `pub fn ready(self: *const T, app: *const App) bool`
///   - Optional `pub fn finish(self: *T, app: *App) void`
///   - Optional `pub fn cleanup(self: *T, app: *App) void`
pub fn from(allocator: std.mem.Allocator, plugin_ptr: anytype) Plugin {
    const PtrT = @TypeOf(plugin_ptr);
    const info = @typeInfo(PtrT);
    comptime {
        if (info != .Pointer) @compileError("Plugin.from expects a pointer to a plugin instance");
    }
    const T = info.Pointer.child;

    const name_val: []const u8 = if (@hasDecl(T, "name"))
        T.name
    else
        @typeName(T);

    const is_unique_val: bool = if (@hasDecl(T, "is_unique"))
        T.is_unique
    else
        true;

    return Plugin{
        .name = name_val,
        .is_unique = is_unique_val,
        .self_ptr = @as(*anyopaque, @ptrCast(plugin_ptr)),
        .vtable = .{
            .build = null,
            .ready = null,
            .finish = null,
            .cleanup = null,
            .destroy = destroyNoop,
        },
        .allocator = allocator,
    };
}

pub fn build(self: *const Plugin, app: *App) !void {
    if (self.vtable.build) |f| return f(self.self_ptr, app);
}

pub fn ready(self: *const Plugin, app: *const App) bool {
    if (self.vtable.ready) |f| return f(self.self_ptr, app);
    return true;
}

pub fn finish(self: *const Plugin, app: *App) void {
    if (self.vtable.finish) |f| f(self.self_ptr, app);
}

pub fn cleanup(self: *const Plugin, app: *App) void {
    if (self.vtable.cleanup) |f| f(self.self_ptr, app);
}

pub fn deinit(self: *Plugin) void {
    self.vtable.destroy(self.allocator, self.self_ptr);
}

fn destroyNoop(_: std.mem.Allocator, _: *anyopaque) void {}
