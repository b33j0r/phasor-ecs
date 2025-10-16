allocator: std.mem.Allocator,
entities: Database,
resources: ResourceManager,
subscriptions: SubscriptionManager,

const std = @import("std");
const root = @import("root.zig");
const Database = root.db.Database;
const ResourceManager = root.ResourceManager;
const Commands = root.Commands;
const Events = root.Events;
const SubscriptionManager = root.SubscriptionManager;

const World = @This();

pub fn init(allocator: std.mem.Allocator) !*World {
    const world = try allocator.create(World);
    errdefer allocator.destroy(world);

    const entities = Database.init(allocator);
    const subscriptions = SubscriptionManager.init(allocator);
    world.* = .{
        .allocator = allocator,
        .entities = entities,
        .resources = ResourceManager.init(allocator),
        .subscriptions = subscriptions,
    };
    return world;
}

pub fn deinit(self: *World) void {
    self.entities.deinit();
    self.resources.deinit();
    self.subscriptions.deinit();
    self.allocator.destroy(self);
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

pub fn registerEvent(self: *World, comptime T: type, capacity: usize) !void {
    if (self.hasResource(Events(T))) {
        return error.EventAlreadyRegistered;
    }
    const events = try Events(T).init(self.allocator, capacity);
    try self.insertResource(events);
}
