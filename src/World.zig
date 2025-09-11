allocator: std.mem.Allocator,
entities: Database,
resources: ResourceManager,

const std = @import("std");
const root = @import("root.zig");
const Database = root.db.Database;
const ResourceManager = root.ResourceManager;
const Commands = root.Commands;

const World = @This();

pub fn init(allocator: std.mem.Allocator) World {
    return World{
        .allocator = allocator,
        .entities = Database.init(allocator),
        .resources = ResourceManager.init(allocator),
    };
}

pub fn deinit(self: *World) void {
    self.entities.deinit();
    self.resources.deinit();
}

pub fn commands(self: *World) Commands {
    return Commands.init(self.allocator, self);
}

pub fn insertResource(self: *World, resource: anytype) !void {
    try self.resources.insert(resource);
}

pub fn removeResource(self: *World, comptime T: type) bool {
    return self.resources.remove(T);
}

pub fn hasResource(self: *World, comptime T: type) bool {
    return self.resources.get(T) != null;
}

pub fn getResource(self: *World, comptime T: type) ?*T {
    return self.resources.get(T);
}

pub fn getResourceMut(self: *World, comptime T: type) ?*T {
    return self.resources.get(T);
}
