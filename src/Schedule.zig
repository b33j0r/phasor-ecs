allocator: std.mem.Allocator,
systems: std.ArrayListUnmanaged(System) = .empty,
label: []const u8 = "",
world: *World,

const Schedule = @This();

pub fn init(allocator: std.mem.Allocator, label: []const u8, world: *World) !Schedule {
    // duplicate label to own memory; freed in deinit
    const owned = try allocator.dupe(u8, label);
    return Schedule{
        .allocator = allocator,
        .systems = .empty,
        .label = owned,
        .world = world,
    };
}

pub fn deinit(self: *Schedule) void {
    if (self.label.len != 0) {
        self.allocator.free(self.label);
        self.label = "";
    }
    // Unregister all systems
    for (self.systems.items) |*system| {
        system.unregister(self.world) catch |err| {
            std.log.err("Error during system unregistration: {any}", .{err});
        };
    }
    self.systems.deinit(self.allocator);
    self.systems = .empty;
}

/// Add a system to the schedule and register it with the world
pub fn add(self: *Schedule, comptime system_fn: anytype) !void {
    const system = try System.from(system_fn);

    // Call the registration function with the world
    try system.register(self.world);

    try self.systems.append(self.allocator, system);
}

/// Get the index of a system in the schedule by its function
pub fn getSystemIndex(self: *const Schedule, comptime system_fn: anytype) ?usize {
    // Build a temporary System for comparison
    const target = System.from(system_fn) catch return null;
    for (self.systems.items, 0..) |system, idx| {
        if (system.run == target.run) {
            return idx;
        }
    }
    return null;
}

/// Remove a system from the schedule and unregister it from the world
pub fn remove(self: *Schedule, comptime system_fn: anytype) !void {
    const idx = self.getSystemIndex(system_fn) orelse return;

    const system = self.systems.items[idx];

    // Unregister the system from the world
    try system.unregister(self.world);

    // Remove the system from the schedule
    _ = self.systems.swapRemove(idx);
}

/// Remove a system by reference to the System object itself
pub fn removeSystemObject(self: *Schedule, system: *System) !void {
    var found_idx: ?usize = null;
    for (self.systems.items, 0..) |item, idx| {
        if (item.run == system.run) {
            found_idx = idx;
            break;
        }
    }
    const idx = found_idx orelse return;

    // Unregister the system from the world
    try system.unregister(self.world);

    // Remove the system from the schedule
    _ = self.systems.swapRemove(idx);
}

/// Run all systems in the schedule
pub fn run(self: *const Schedule, world: *World) !void {
    for (self.systems.items) |system| {
        var commands = world.commands();
        defer commands.deinit();

        try system.run(&commands);

        try commands.apply();
    }
}

// Imports
const std = @import("std");
const root = @import("root.zig");
const System = root.System;
const World = root.World;

const phasor_db = @import("phasor-db");
const Commands = root.Commands;
