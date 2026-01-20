const std = @import("std");
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;
const Vec3 = vec.Vec3;
const Mat4 = @import("mat4.zig").Mat4;
const Quat = @import("root.zig").Quat;

pub const Transform2d = extern struct {
    translation: Vec2 = .{ .x = 0.0, .y = 0.0 },
    scale: Vec2 = .{ .x = 1.0, .y = 1.0 },
    rotation: f32 = 0.0, // radians

    pub fn identity() Transform2d {
        return .{};
    }

    pub fn toMat4(self: Transform2d) Mat4 {
        const t = Mat4.translate(self.translation.x, self.translation.y, 0.0);
        const r = Mat4.rotateZ(self.rotation);
        const s = Mat4.scale(self.scale.x, self.scale.y, 1.0);

        // Result = T * R * S
        return t.mul(r.mul(s));
    }
};

pub const Transform3d = extern struct {
    translation: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    rotation: Quat = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
    scale: Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },

    pub fn identity() Transform3d {
        return .{};
    }

    pub fn toMat4(self: Transform3d) Mat4 {
        const t = Mat4.translateVec3(self.translation);
        const r = Mat4.fromQuaternion(self.rotation);
        const s = Mat4.scaleVec3(self.scale);

        // Result = T * R * S
        return t.mul(r.mul(s));
    }
};

test "Transform2d toMat4" {
    const t2 = Transform2d{
        .translation = .{ .x = 10, .y = 20 },
        .rotation = std.math.pi / 2.0,
        .scale = .{ .x = 2, .y = 3 },
    };
    const m = t2.toMat4();

    // Point (1, 0)
    // Scale: (2, 0)
    // Rotate 90deg: (0, 2)
    // Translate: (10, 22)
    const p = Vec2{ .x = 1.0, .y = 0.0 };
    const p_transformed = m.transformVec2(p);

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), p_transformed.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 22.0), p_transformed.y, 0.0001);
}

test "Transform3d toMat4" {
    const t3 = Transform3d{
        .translation = .{ .x = 1, .y = 2, .z = 3 },
        .scale = .{ .x = 2, .y = 2, .z = 2 },
    };
    const m = t3.toMat4();

    const p = Vec3{ .x = 1, .y = 0, .z = 0 };
    const p_transformed = m.transformVec3(p);

    // Scale: (2, 0, 0)
    // No rotation
    // Translate: (3, 2, 3)
    try std.testing.expectEqual(@as(f32, 3), p_transformed.x);
    try std.testing.expectEqual(@as(f32, 2), p_transformed.y);
    try std.testing.expectEqual(@as(f32, 3), p_transformed.z);
}
