const Health = struct {
    current: i32,
    max: i32,
};

const Player = struct {};

test "System with no params" {
    var world = try World.init(std.testing.allocator);
    defer world.deinit();

    const system_with_no_params_fn = struct {
        pub fn system_with_no_params() !void {}
    }.system_with_no_params;

    const allocator = std.testing.allocator;

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_no_params_fn, world);
}

test "System with transaction system param" {
    const system_with_tx_param_fn = struct {
        pub fn system_with_tx_param(commands: *Commands) !void {
            // Add an entity via commands
            _ = try commands.createEntity(.{Player{}});
        }
    }.system_with_tx_param;

    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_tx_param_fn, world);
    try schedule.run(world);

    var query_result = try world.entities.query(.{Player});
    defer query_result.deinit();
    try std.testing.expect(query_result.count() == 1);
}

test "System with Query(.{T}) param" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    // Create one Player entity so the query sees it
    _ = try world.entities.createEntity(.{Player{}});

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    const system_with_query_param_fn = struct {
        pub fn system_with_query_param(q: Query(.{Player})) !void {
            // Should see exactly one Player entity
            try std.testing.expectEqual(@as(usize, 1), q.count());

            var iter = q.iterator();
            var total: usize = 0;
            while (iter.next()) |_| total += 1;
            try std.testing.expectEqual(@as(usize, 1), total);
        }
    }.system_with_query_param;

    try schedule.addWithWorld(system_with_query_param_fn, world);
    try schedule.run(world);
}

test "System with GroupBy(Trait) param" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                pub const __group_key__ = N;
                pub const __trait__ = ComponentN;
            };
        }
        pub const ComponentN = struct {};
    };
    const Component = ComponentTypeFactory.Component;
    const ComponentN = ComponentTypeFactory.ComponentN;

    const Component1 = Component(1);
    const Component2 = Component(2);

    // Create entities with different components so that groups exist
    _ = try world.entities.createEntity(.{Component1{}});
    _ = try world.entities.createEntity(.{Component1{}});
    _ = try world.entities.createEntity(.{Component2{}});

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    const system_with_groupby_param_fn = struct {
        pub fn system_with_groupby_param(groups: GroupBy(ComponentN)) !void {
            // Should see exactly two groups: key 1 and key 2
            try std.testing.expectEqual(@as(usize, 2), groups.count());

            var it = groups.iterator();
            const g1 = it.next().?;
            const g2 = it.next().?;
            try std.testing.expectEqual(null, it.next());

            try std.testing.expectEqual(@as(i32, 1), g1.key);
            try std.testing.expectEqual(@as(i32, 2), g2.key);
        }
    }.system_with_groupby_param;

    try schedule.addWithWorld(system_with_groupby_param_fn, world);
    try schedule.run(world);
}

test "System with combination of params" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    // Create one Player entity so the query sees it
    _ = try world.entities.createEntity(.{Player{}});
    try world.insertResource(Health{ .current = 50, .max = 100 });

    const system_with_combined_params_fn = struct {
        pub fn system_with_combined_params(
            commands: *Commands,
            res: ResMut(Health),
            q: Query(.{Player}),
        ) !void {
            // Should see exactly one Player entity
            try std.testing.expectEqual(@as(usize, 1), q.count());

            // Modify the resource
            res.ptr.current += 25;
            try std.testing.expectEqual(@as(i32, 75), res.ptr.current);

            // Add another Player entity via commands
            _ = try commands.createEntity(.{Player{}});
        }
    }.system_with_combined_params;

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_combined_params_fn, world);
    try schedule.run(world);

    const health_res = world.getResource(Health) orelse unreachable;
    try std.testing.expect(health_res.current == 75);

    var query_result = try world.entities.query(.{Player});
    defer query_result.deinit();
    try std.testing.expect(query_result.count() == 2);
}

test "System with Res(T) param" {
    // Use Health as a resource for this test
    const system_with_res_param_fn = struct {
        pub fn system_with_res_param(res: Res(Health)) !void {
            // Check the resource value
            try std.testing.expectEqual(@as(i32, 80), res.ptr.current);
        }
    }.system_with_res_param;

    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    try world.insertResource(Health{ .current = 80, .max = 100 });

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_res_param_fn, world);
    try schedule.run(world);
}

test "System with ResMut(T) param" {
    // Use Health as a resource for this test
    const system_with_res_param_fn = struct {
        pub fn system_with_res_param(res: ResMut(Health)) !void {
            // Modify the resource
            res.ptr.current += 10;
        }
    }.system_with_res_param;

    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    try world.insertResource(Health{ .current = 93, .max = 100 });

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_res_param_fn, world);
    try schedule.run(world);

    // No entity changes queued; no need to apply commands

    const health_res = world.getResource(Health) orelse unreachable;
    try std.testing.expect(health_res.current == 103);
}

test "System with ResOpt(T) param" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator);
    defer world.deinit();

    // No Health resource inserted yet

    const system_with_resopt_param_fn = struct {
        pub fn system_with_resopt_param(res_opt: ResOpt(Health)) !void {
            // Resource is absent; ptr should be null
            try std.testing.expect(res_opt.ptr == null);
        }
    }.system_with_resopt_param;

    var schedule = try Schedule.init(allocator, "Test");
    defer schedule.deinit();

    try schedule.addWithWorld(system_with_resopt_param_fn, world);
    try schedule.run(world);
}

// Imports
const std = @import("std");

const ecs = @import("phasor-ecs");
const Query = ecs.Query;
const Res = ecs.Res;
const ResMut = ecs.ResMut;
const ResOpt = ecs.ResOpt;
const Schedule = ecs.Schedule;
const System = ecs.System;
const Without = ecs.Without;
const GroupBy = ecs.GroupBy;
const World = ecs.World;
const Commands = ecs.Commands;
