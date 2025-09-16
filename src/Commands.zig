//! Queues commands to be run on the Database.
command_buffer: CommandBuffer,
world: *World,

const std = @import("std");

const root = @import("root.zig");
const CommandBuffer = root.CommandBuffer;
const World = root.World;
const Entity = root.db.Entity;
const QueryResult = root.db.QueryResult;

const meta = @import("meta.zig");
const Cons = meta.Cons;
const consValue = meta.consValue;

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

pub fn addComponents(self: *Commands, entity_id: Entity.Id, components: anytype) !void {
    const AddComponentsContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.entities.addComponents(ctx.entity_id, ctx.components);
        }
    };

    try self.command_buffer.queueContext(AddComponentsContext{
        .entity_id = entity_id,
        .components = components,
    });
}

pub fn removeComponents(self: *Commands, entity_id: Entity.Id, components: anytype) !void {
    const RemoveComponentsContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.entities.removeComponents(ctx.entity_id, ctx.components);
        }
    };

    try self.command_buffer.queueContext(RemoveComponentsContext{
        .entity_id = entity_id,
        .components = components,
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

pub fn query(self: *Commands, comptime Parts: anytype) !QueryResult {
    return try self.world.entities.query(Parts);
}

/// Creates a wrapper that adds a DefaultComponentT to every
/// newly created entity.
pub fn Scoped(comptime DefaultComponentT: anytype) type {
    return struct {
        commands: ?*Commands = null,

        const Self = @This();

        pub fn init(c: *Commands) !Self {
            return Self{
                .commands = c,
            };
        }

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.commands = commands;
        }

        pub fn createEntity(self: Self, components: anytype) !Entity.Id {
            if (self.commands == null) {
                return error.NotInitialized;
            }
            const combined_components = consValue(
                DefaultComponentT{},
                components,
            );
            return try self.commands.?.createEntity(combined_components);
        }

        pub fn removeEntity(self: Self, entity_id: Entity.Id) !void {
            if (self.commands == null) {
                return error.NotInitialized;
            }
            return try self.commands.?.removeEntity(entity_id);
        }

        pub fn addComponents(self: Self, entity_id: Entity.Id, components: anytype) !void {
            if (self.commands == null) {
                return error.NotInitialized;
            }
            return try self.commands.?.addComponents(entity_id, components);
        }

        pub fn removeComponents(self: Self, entity_id: Entity.Id, components: anytype) !void {
            if (self.commands == null) {
                return error.NotInitialized;
            }
            return try self.commands.?.removeComponents(entity_id, components);
        }
    };
}

pub fn scoped(self: *Commands, comptime DefaultComponentT: anytype) !Scoped(DefaultComponentT) {
    const ScopedCommands = Scoped(DefaultComponentT);
    return try ScopedCommands.init(self);
}
