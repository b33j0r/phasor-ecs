//! Inspired by Bevy's Plugin system: a plugin encapsulates setup logic
//! (adding systems, resources, etc) and participates in the app lifecycle.
//!
//! - `is_unique` controls whether the same plugin type can be added multiple times.
//! - Ownership is explicit: use `fromInstance` if you keep the instance,
//!   or `fromOwned` if you want the app to own and destroy it.

const std = @import("std");
const root = @import("root.zig");
const App = root.App;

const Plugin = @This();

pub const VTable = struct {
    // Thunks that receive an erased self pointer
    build: ?*const fn (*anyopaque, *App) anyerror!void,
    cleanup: ?*const fn (*anyopaque, *App) void,

    // Always called on deinit; either frees or does nothing depending on ownership.
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,
};

name: []const u8,
is_unique: bool,
self_ptr: *anyopaque,
vtable: VTable,
allocator: std.mem.Allocator,

/// Smart constructor: decides whether to use fromInstance or fromOwned.
/// - If passed a pointer, uses fromInstance.
/// - If passed a value, allocates and uses fromOwned.
pub fn from(allocator: std.mem.Allocator, plugin_or_ptr: anytype) !Plugin {
    const T = @TypeOf(plugin_or_ptr);
    const info = @typeInfo(T);

    return switch (info) {
        .pointer => fromInstance(allocator, plugin_or_ptr),
        else => fromOwned(allocator, plugin_or_ptr),
    };
}

/// Create a `Plugin` from a user-provided plugin instance (not owned).
/// The app will call lifecycle hooks, but will not free the instance.
pub fn fromInstance(allocator: std.mem.Allocator, plugin_ptr: anytype) Plugin {
    return make(plugin_ptr, allocator, false);
}

/// Create a `Plugin` from a user-provided plugin instance (owned).
/// The app will call lifecycle hooks and free the instance when deinit is called.
pub fn fromOwned(allocator: std.mem.Allocator, plugin: anytype) !Plugin {
    const boxed = try allocator.create(@TypeOf(plugin));
    boxed.* = plugin;
    return make(boxed, allocator, true);
}

fn make(plugin_ptr: anytype, allocator: std.mem.Allocator, owned: bool) Plugin {
    const PtrT = @TypeOf(plugin_ptr);
    const info = @typeInfo(PtrT);
    comptime {
        if (info != .pointer) @compileError("Plugin.make expects a pointer to a plugin instance");
    }
    const T = info.pointer.child;

    const name_val: []const u8 = if (@hasDecl(T, "name")) T.name else @typeName(T);
    const is_unique_val: bool = if (@hasDecl(T, "is_unique")) T.is_unique else true;

    const wrappers = struct {
        fn build(ptr: *anyopaque, app: *App) anyerror!void {
            return (@as(*T, @ptrCast(@alignCast(ptr)))).build(app);
        }
        fn cleanup(ptr: *anyopaque, app: *App) void {
            return (@as(*T, @ptrCast(@alignCast(ptr)))).cleanup(app);
        }
        fn destroyOwned(allocator_: std.mem.Allocator, ptr: *anyopaque) void {
            allocator_.destroy(@as(*T, @ptrCast(@alignCast(ptr))));
        }
        fn destroyNoop(_: std.mem.Allocator, _: *anyopaque) void {}
    };

    const vtable = VTable{
        .build = if (@hasDecl(T, "build")) &wrappers.build else null,
        .cleanup = if (@hasDecl(T, "cleanup")) &wrappers.cleanup else null,
        .destroy = if (owned) &wrappers.destroyOwned else &wrappers.destroyNoop,
    };

    return Plugin{
        .name = name_val,
        .is_unique = is_unique_val,
        .self_ptr = @as(*anyopaque, @constCast(plugin_ptr)),
        .vtable = vtable,
        .allocator = allocator,
    };
}

pub fn build(self: *const Plugin, app: *App) !void {
    if (self.vtable.build) |f| return f(self.self_ptr, app);
}

pub fn cleanup(self: *const Plugin, app: *App) void {
    if (self.vtable.cleanup) |f| return f(self.self_ptr, app);
}

pub fn deinit(self: *Plugin) void {
    self.vtable.destroy(self.allocator, self.self_ptr);
}
