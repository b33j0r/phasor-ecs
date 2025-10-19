allocator: std.mem.Allocator,
app: *App,
plugins: std.ArrayListUnmanaged(Plugin) = .empty,
temporary_systems: std.ArrayListUnmanaged(TemporarySystemBinding) = .empty,
enter_schedule: *Schedule,
update_schedule: *Schedule,
exit_schedule: *Schedule,

pub const Plugin = struct {
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    build_fn: ?*const fn (*anyopaque, *PhaseContext) anyerror!void,
    cleanup_fn: ?*const fn (*anyopaque, *PhaseContext) anyerror!void,
    destroy_fn: *const fn (*anyopaque, std.mem.Allocator) void,
};

/// A temporary binding of a system to a schedule within a phase context.
/// It will be removed after the phase context is destroyed.
pub const TemporarySystemBinding = struct {
    schedule_label: []const u8,
    system: *System,
};

const PhaseContext = @This();

pub fn init(alloc: std.mem.Allocator, app: *App) !PhaseContext {
    const world = app.world;
    const enter_schedule = try alloc.create(Schedule);
    errdefer alloc.destroy(enter_schedule);
    enter_schedule.* = try Schedule.init(alloc, "EnterPhase", world);

    const update_schedule = try alloc.create(Schedule);
    errdefer alloc.destroy(update_schedule);
    update_schedule.* = try Schedule.init(alloc, "UpdatePhase", world);

    const exit_schedule = try alloc.create(Schedule);
    errdefer alloc.destroy(exit_schedule);
    exit_schedule.* = try Schedule.init(alloc, "ExitPhase", world);

    return .{
        .allocator = alloc,
        .app = app,
        .enter_schedule = enter_schedule,
        .update_schedule = update_schedule,
        .exit_schedule = exit_schedule,
    };
}

pub fn deinit(self: *PhaseContext) void {
    // Remove all temporarily added systems from the app
    for (self.temporary_systems.items) |binding| {
        self.app.removeSystemObject(binding.schedule_label, binding.system) catch {};
    }
    self.temporary_systems.deinit(self.allocator);

    // Free all plugins
    for (self.plugins.items) |plugin| {
        plugin.destroy_fn(plugin.ptr, plugin.allocator);
    }
    self.plugins.deinit(self.allocator);

    self.enter_schedule.deinit();
    self.allocator.destroy(self.enter_schedule);

    self.update_schedule.deinit();
    self.allocator.destroy(self.update_schedule);

    self.exit_schedule.deinit();
    self.allocator.destroy(self.exit_schedule);
}

fn addPluginInternal(self: *PhaseContext, plugin: Plugin) !void {
    try self.plugins.append(self.allocator, plugin);
}

pub fn addPlugin(self: *PhaseContext, plugin: anytype) !void {
    const T = @TypeOf(plugin);
    const boxed = try self.allocator.create(T);
    boxed.* = plugin;

    const p = Plugin{
        .ptr = boxed,
        .allocator = self.allocator,
        .build_fn = if (@hasDecl(T, "build")) &struct {
            fn call(ptr: *anyopaque, ctx: *PhaseContext) anyerror!void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                return self_ptr.build(ctx);
            }
        }.call else null,
        .cleanup_fn = if (@hasDecl(T, "cleanup")) &struct {
            fn call(ptr: *anyopaque, ctx: *PhaseContext) anyerror!void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                return self_ptr.cleanup(ctx);
            }
        }.call else null,
        .destroy_fn = &struct {
            fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                alloc.destroy(self_ptr);
            }
        }.destroy,
    };
    try addPluginInternal(self, p);
}

pub fn addEnterSystem(self: *PhaseContext, system: anytype) !void {
    try self.enter_schedule.*.add(system);
}
pub fn addUpdateSystem(self: *PhaseContext, system: anytype) !void {
    try self.update_schedule.*.add(system);
}
pub fn addExitSystem(self: *PhaseContext, system: anytype) !void {
    try self.exit_schedule.*.add(system);
}

/// Add a system directly to a schedule on the App, tracking it for removal on phase exit
pub fn addSystem(self: *PhaseContext, schedule_label: []const u8, system: anytype) !void {
    try self.app.addSystem(schedule_label, system);
    const sys = self.app.getSystem(schedule_label, system) orelse
        {
            return error.SystemNotFound;
        };

    try self.temporary_systems.append(self.allocator, .{
        .schedule_label = schedule_label,
        .system = sys,
    });
}

pub fn runEnter(self: *PhaseContext, world: *World) !void {
    for (self.plugins.items) |plugin| {
        if (plugin.build_fn) |f| {
            try f(plugin.ptr, self);
        }
    }
    try self.enter_schedule.*.run(world);
}
pub fn runExit(self: *PhaseContext, world: *World) !void {
    try self.exit_schedule.*.run(world);

    // TODO: run in reverse order?
    for (self.plugins.items) |plugin| {
        if (plugin.cleanup_fn) |f| {
            try f(plugin.ptr, self);
        }
    }
}
pub fn update(self: *PhaseContext, world: *World) !void {
    try self.update_schedule.*.run(world);
}

// Imports
const std = @import("std");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Schedule = phasor_ecs.Schedule;
const World = phasor_ecs.World;
const System = phasor_ecs.System;
