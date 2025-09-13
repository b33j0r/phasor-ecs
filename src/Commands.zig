//! Queues commands to be run on the Database.
command_buffer: CommandBuffer,
world: *World,

const std = @import("std");

const root = @import("root.zig");
const CommandBuffer = root.CommandBuffer;
const World = root.World;
const Entity = root.db.Entity;

const Commands = @This();

pub fn init(allocator: std.mem.Allocator, world: *World) Commands {
    return Commands{
        .command_buffer = CommandBuffer.init(allocator),
        .world = world,
    };
}

pub fn deinit(self: *Commands) void {
    self.command_buffer.deinit();
}

pub fn apply(self: *Commands) !void {
    // Flush the queued commands into the provided world
    try self.command_buffer.flush(self.world);
}

fn reserveEntityId(self: *Commands) Entity.Id {
    return self.world.entities.reserveEntityId();
}

pub fn createEntity(self: *Commands, components: anytype) !Entity.Id {
    const entity_id = self.reserveEntityId();

    const CreateEntityContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            _ = try world.entities.createEntityWithId(ctx.entity_id, ctx.components);
        }
    };

    try self.command_buffer.queueContext(CreateEntityContext{
        .entity_id = entity_id,
        .components = components,
    });

    return entity_id;
}

pub fn removeEntity(self: *Commands, entity_id: Entity.Id) !void {
    const RemoveEntityContext = struct {
        entity_id: Entity.Id,

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            _ = try world.entities.removeEntity(ctx.entity_id);
        }
    };

    try self.command_buffer.queueContext(RemoveEntityContext{
        .entity_id = entity_id,
    });
}

pub fn insertResource(self: *Commands, resource_ptr: anytype) !void {
    try self.world.insertResource(resource_ptr);
}

pub fn removeResource(self: *Commands, comptime T: type) bool {
    return self.world.removeResource(T);
}

pub fn getResource(self: *Commands, comptime T: type) ?*T {
    return self.world.getResource(T);
}

pub fn hasResource(self: *Commands, comptime T: type) bool {
    return self.world.hasResource(T);
}
