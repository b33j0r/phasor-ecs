allocator: std.mem.Allocator,
systems: std.ArrayListUnmanaged(System) = .empty,
label: []const u8 = "",

const std = @import("std");
const root = @import("root.zig");
const System = root.System;

const phasor_db = @import("phasor-db");
const Commands = root.Commands;

const Schedule = @This();

pub fn init(allocator: std.mem.Allocator) Schedule {
    return Schedule{
        .allocator = allocator,
        .systems = .empty,
        .label = "",
    };
}

pub fn initWithLabel(allocator: std.mem.Allocator, label: []const u8) !Schedule {
    // duplicate label to own memory; freed in deinit
    const owned = try allocator.dupe(u8, label);
    return Schedule{
        .allocator = allocator,
        .systems = .empty,
        .label = owned,
    };
}

pub fn deinit(self: *Schedule) void {
    if (self.label.len != 0) {
        self.allocator.free(self.label);
        self.label = "";
    }
    self.systems.deinit(self.allocator);
    self.systems = .empty;
}

pub fn add(self: *Schedule, comptime system_fn: anytype) !void {
    const system = try System.from(system_fn);
    try self.systems.append(self.allocator, system);
}

pub fn run(self: *const Schedule, commands: *Commands) !void {
    for (self.systems.items) |system| {
        try system.run(commands);
    }
}
