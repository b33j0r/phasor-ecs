const Foo = struct { x: i32 };

// Test a simple command context that flips flags on execute/cleanup
const FlagContext = struct {
    executed: *bool,
    cleaned: *bool,

    pub fn execute(self: *@This(), world: *ecs.World) anyerror!void {
        _ = world;
        self.executed.* = true;
    }

    pub fn cleanup(self: *@This(), allocator: std.mem.Allocator) void {
        _ = allocator; // Command will always destroy the context allocation
        self.cleaned.* = true;
    }
};

// Test that Command.from builds a command that can execute and cleanup
test "Command.from executes and cleanup is called" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var executed = false;
    var cleaned = false;

    var cmd = try Command.from(allocator, FlagContext{ .executed = &executed, .cleaned = &cleaned });
    try cmd.execute(world);
    try std.testing.expect(executed);
    // cleanup should be invoked manually or by a buffer; call directly here
    cmd.cleanup();
    try std.testing.expect(cleaned);
}

// Test that CommandBuffer queues and flushes commands in order
test "CommandBuffer queues and flushes in order" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var buffer = CommandBuffer.init(allocator);
    defer buffer.deinit();

    var log = std.ArrayListUnmanaged([]const u8){};
    defer log.deinit(allocator);

    const Ctx = struct {
        log: *std.ArrayListUnmanaged([]const u8),
        name: []const u8,
        pub fn execute(self: *@This(), world_ptr: *ecs.World) anyerror!void {
            _ = world_ptr;
            try self.log.append(std.testing.allocator, self.name);
        }
        pub fn cleanup(self: *@This(), alloc: std.mem.Allocator) void {
            _ = self;
            _ = alloc;
        }
    };

    try buffer.queueContext(Ctx{ .log = &log, .name = "A" });
    try buffer.queueContext(Ctx{ .log = &log, .name = "B" });

    try buffer.flush(world);

    try std.testing.expectEqual(@as(usize, 2), log.items.len);
    try std.testing.expect(std.mem.eql(u8, log.items[0], "A"));
    try std.testing.expect(std.mem.eql(u8, log.items[1], "B"));
}

// Test that Commands can reserve IDs and create entities via queued commands
test "Commands createEntity" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    const id1 = try cmds.createEntity(.{Foo{ .x = 1 }});
    const id2 = try cmds.createEntity(.{Foo{ .x = 2 }});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(world.entities.getEntityCount() == 0);
    try cmds.apply();
    try std.testing.expect(world.entities.getEntityCount() == 2);
    const e1 = world.entities.getEntity(id1) orelse unreachable;
    const e2 = world.entities.getEntity(id2) orelse unreachable;

    try std.testing.expect(e1.get(Foo).?.x == 1);
    try std.testing.expect(e2.get(Foo).?.x == 2);
}

test "Commands removeEntity" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    const id1 = try world.entities.createEntity(.{Foo{ .x = 1 }});
    const id2 = try world.entities.createEntity(.{Foo{ .x = 2 }});

    try std.testing.expect(world.entities.getEntityCount() == 2);

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    try cmds.removeEntity(id1);
    try cmds.removeEntity(id2);

    try std.testing.expect(world.entities.getEntityCount() == 2);
    try cmds.apply();
    try std.testing.expect(world.entities.getEntityCount() == 0);
}

test "Commands addComponents" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    // Define test components
    const Player = struct {};
    const Health = struct { value: i32 };

    // Create an entity immediately in the database
    const id = try world.entities.createEntity(.{Foo{ .x = 0 }});

    // Verify initial state
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Foo).?.x == 0);
        try std.testing.expect(e.get(Player) == null);
        try std.testing.expect(e.get(Health) == null);
    }

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    // Queue adding components; should be deferred until apply()
    try cmds.addComponents(id, .{ Player{}, Health{ .value = 100 } });

    // Not applied yet; nothing should change
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Player) == null);
        try std.testing.expect(e.get(Health) == null);
    }

    try cmds.apply();

    // After apply, components should be present with correct values
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Player) != null);
        try std.testing.expect(e.get(Health).?.value == 100);
        try std.testing.expect(e.get(Foo) != null); // Original component remains
    }
}

test "Commands removeComponents" {
    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    // Define test components
    const Player = struct {};
    const Health = struct { value: i32 };

    // Create an entity with multiple components
    const id = try world.entities.createEntity(.{ Foo{ .x = 5 }, Player{}, Health{ .value = 250 } });

    // Precondition check
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Foo).?.x == 5);
        try std.testing.expect(e.get(Player) != null);
        try std.testing.expect(e.get(Health).?.value == 250);
    }

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    // Queue component removals by type
    try cmds.removeComponents(id, .{ Player, Health });

    // Not applied yet; nothing should change
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Player) != null);
        try std.testing.expect(e.get(Health) != null);
    }

    try cmds.apply();

    // After apply, removed components should be gone; Foo should remain
    {
        const e = world.entities.getEntity(id) orelse unreachable;
        try std.testing.expect(e.get(Player) == null);
        try std.testing.expect(e.get(Health) == null);
        try std.testing.expect(e.get(Foo).?.x == 5);
    }
}

test "Commands query" {
    const Player = struct {};

    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    _ = try world.entities.createEntity(.{Foo{ .x = 10 }});
    _ = try world.entities.createEntity(.{Foo{ .x = 20 }});
    _ = try world.entities.createEntity(.{Player{}});

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    var query = try cmds.query(.{Foo});
    defer query.deinit();

    try std.testing.expectEqual(2, query.count());

    var iterator = query.iterator();

    var first_result = iterator.next();
    try std.testing.expect(first_result.?.get(Foo).?.x == 10);

    var second_result = iterator.next();
    try std.testing.expect(second_result.?.get(Foo).?.x == 20);

    try std.testing.expect(iterator.next() == null);
}

test "Commands scope" {
    const Marker = struct {};

    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    var scoped = try cmds.scoped(Marker);
    const entity_id = try scoped.createEntity(.{Foo{ .x = 42 }});

    try cmds.apply();

    // check that the entity exists and has the Marker component
    const e = world.entities.getEntity(entity_id) orelse unreachable;
    try std.testing.expect(e.get(Marker) != null);
}

test "Commands addComponent (singular)" {
    const Health = struct { value: i32 };

    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    const id = try world.entities.createEntity(.{Foo{ .x = 99 }});

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    try cmds.addComponent(id, Health{ .value = 75 });

    try cmds.apply();

    const e = world.entities.getEntity(id) orelse unreachable;
    try std.testing.expect(e.get(Health).?.value == 75);
}

test "Commands removeComponent (singular)" {
    const Health = struct { value: i32 };

    const allocator = std.testing.allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    const id = try world.entities.createEntity(.{ Foo{ .x = 88 }, Health{ .value = 150 } });

    var cmds = Commands.init(allocator, world);
    defer cmds.deinit();

    try cmds.removeComponent(id, Health);

    try cmds.apply();

    const e = world.entities.getEntity(id) orelse unreachable;
    try std.testing.expect(e.get(Health) == null);
}

// Imports
const std = @import("std");
const ecs = @import("phasor-ecs");

const Command = ecs.Command;
const CommandBuffer = ecs.CommandBuffer;
const Commands = ecs.Commands;
