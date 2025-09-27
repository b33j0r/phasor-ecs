test "Bundle Entity.get works with arbitrary structs" {
    const Position = struct {
        x: f32,
        y: f32,
    };

    const Velocity = struct {
        dx: f32,
        dy: f32,
    };

    const Movable = struct {
        pos: Position,
        vel: Velocity,
    };

    const allocator = std.testing.allocator;
    var db = phasor_db.Database.init(allocator);
    defer db.deinit();

    const entity_id = try db.createEntity(.{
        Position{ .x = 1.0, .y = 2.0 },
        Velocity{ .dx = 0.5, .dy = 0.5 },
    });
    const entity = db.getEntity(entity_id) orelse {
        return error.EntityNotFound;
    };
    const owned_movable = entity.getAlloc(allocator, Movable) orelse {
        return error.BundleNotFound;
    };
    defer owned_movable.deinit();
    const movable = owned_movable.ptr;

    try std.testing.expect(movable.pos.x == 1.0);
    try std.testing.expect(movable.pos.y == 2.0);
    try std.testing.expect(movable.vel.dx == 0.5);
    try std.testing.expect(movable.vel.dy == 0.5);
}

const std = @import("std");
const phasor_db = @import("phasor-db");
