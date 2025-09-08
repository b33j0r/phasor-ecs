const std = @import("std");

const phasor_db = @import("phasor-db");
const Database = phasor_db.Database;
const Entity = phasor_db.Entity;
const Transaction = phasor_db.Transaction;

const root = @import("phasor-ecs");
const Query = root.Query;
const Res = root.Res;
const Schedule = root.Schedule;
const System = root.System;
const Without = root.Without;
const GroupBy = root.GroupBy;

const Health = struct {
    current: i32,
    max: i32,
};

const Player = struct {};

test "System with no params is an error" {
    const system_with_no_params_fn = struct {
        pub fn system_with_no_params() !void {}
    }.system_with_no_params;

    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    schedule.add(system_with_no_params_fn) catch {
        // expect to fail because system has no parameters
        return;
    };
    try std.testing.expect(false);
}

test "System with transaction system param" {
    const system_with_tx_param_fn = struct {
        pub fn system_with_tx_param(tx: *Transaction) !void {
            // Add an entity to the transaction
            _ = try tx.createEntity(.{Player{}});
        }
    }.system_with_tx_param;

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    try schedule.add(system_with_tx_param_fn);
    try schedule.run(&tx);

    try tx.execute();

    var query_result = try db.query(.{Player});
    defer query_result.deinit();
    try std.testing.expect(query_result.count() == 1);
}

test "System with Res(T) param" {
    // Use Health as a resource for this test
    const system_with_res_param_fn = struct {
        pub fn system_with_res_param(res: Res(Health)) !void {
            // Modify the resource
            res.ptr.current += 10;
        }
    }.system_with_res_param;

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.insertResource(Health{ .current = 93, .max = 100 });

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    try schedule.add(system_with_res_param_fn);
    try schedule.run(&tx);

    try tx.execute();

    const health_res = db.getResource(Health) orelse unreachable;
    try std.testing.expect(health_res.current == 103);
}

test "System with Query(.{T}) param" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create one Player entity so the query sees it
    _ = try db.createEntity(.{Player{}});

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    const system_with_query_param_fn = struct {
        pub fn system_with_query_param(q: Query(.{Player})) !void {
            // Should see exactly one Player entity
            try std.testing.expectEqual(@as(usize, 1), q.count());

            var iter = q.iterator();
            var total: usize = 0;
            while (iter.next()) |_| total += 1;
            try std.testing.expectEqual(@as(usize, 1), total);

            // Explicitly deinit the query to free resources
            var q_mut = q; // make a mutable copy to call deinit
            q_mut.deinit();
        }
    }.system_with_query_param;

    try schedule.add(system_with_query_param_fn);
    try schedule.run(&tx);
}

test "System with GroupBy(Trait) param" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

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
    _ = try db.createEntity(.{Component1{}});
    _ = try db.createEntity(.{Component1{}});
    _ = try db.createEntity(.{Component2{}});

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

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

            // Explicitly deinit the groups to free resources
            var groups_mut = groups;
            groups_mut.deinit();
        }
    }.system_with_groupby_param;

    try schedule.add(system_with_groupby_param_fn);
    try schedule.run(&tx);
}

test "System with combination of params" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create one Player entity so the query sees it
    _ = try db.createEntity(.{Player{}});
    try db.insertResource(Health{ .current = 50, .max = 100 });

    const system_with_combined_params_fn = struct {
        pub fn system_with_combined_params(
            tx: *Transaction,
            res: Res(Health),
            q: Query(.{Player}),
        ) !void {
            // Should see exactly one Player entity
            try std.testing.expectEqual(@as(usize, 1), q.count());

            // Modify the resource
            res.ptr.current += 25;
            try std.testing.expectEqual(@as(i32, 75), res.ptr.current);

            // Add another Player entity to the transaction
            _ = try tx.createEntity(.{Player{}});

            // Explicitly deinit the query to free resources
            var q_mut = q; // make a mutable copy to call deinit
            q_mut.deinit();
        }
    }.system_with_combined_params;

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    try schedule.add(system_with_combined_params_fn);
    try schedule.run(&tx);

    try tx.execute();

    const health_res = db.getResource(Health) orelse unreachable;
    try std.testing.expect(health_res.current == 75);

    var query_result = try db.query(.{Player});
    defer query_result.deinit();
    try std.testing.expect(query_result.count() == 2);
}
