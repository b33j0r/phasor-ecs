//! 4x4 Matrix for homogeneous 3D transformations
//! Column-major layout for compatibility with Vulkan/OpenGL
//!
//! Matrix operations follow the standard transformation order:
//! Translation -> Rotation -> Scale -> Projection
//!
//! IMPORTANT: When composing transformations in window/pixel space before
//! converting to clip space, perform rotation BEFORE aspect ratio scaling
//! to preserve orthonormality and avoid shear artifacts.

const Mat4 = @This();

// Column-major storage: m[column][row]
// | m[0][0]  m[1][0]  m[2][0]  m[3][0] |
// | m[0][1]  m[1][1]  m[2][1]  m[3][1] |
// | m[0][2]  m[1][2]  m[2][2]  m[3][2] |
// | m[0][3]  m[1][3]  m[2][3]  m[3][3] |
m: [4][4]f32,

/// Create an identity matrix
pub fn identity() Mat4 {
    return .{
        .m = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

/// Create a translation matrix
pub fn translate(x: f32, y: f32, z: f32) Mat4 {
    return .{
        .m = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ x, y, z, 1 },
        },
    };
}

/// Create a translation matrix from Vec3
pub fn translateVec3(v: Vec3) Mat4 {
    return translate(v.x, v.y, v.z);
}

/// Create a scale matrix
pub fn scale(x: f32, y: f32, z: f32) Mat4 {
    return .{
        .m = .{
            .{ x, 0, 0, 0 },
            .{ 0, y, 0, 0 },
            .{ 0, 0, z, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

/// Create a uniform scale matrix
pub fn scaleUniform(s: f32) Mat4 {
    return scale(s, s, s);
}

/// Create a scale matrix from Vec3
pub fn scaleVec3(v: Vec3) Mat4 {
    return scale(v.x, v.y, v.z);
}

/// Create a rotation matrix around the Z axis (for 2D rotation)
/// Angle in radians, counter-clockwise when viewed from +Z axis
pub fn rotateZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .m = .{
            .{ c, s, 0, 0 },
            .{ -s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

/// Create a rotation matrix around the X axis
pub fn rotateX(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .m = .{
            .{ 1, 0, 0, 0 },
            .{ 0, c, s, 0 },
            .{ 0, -s, c, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

/// Create a rotation matrix around the Y axis
pub fn rotateY(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .m = .{
            .{ c, 0, -s, 0 },
            .{ 0, 1, 0, 0 },
            .{ s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

/// Create a rotation matrix from a quaternion
pub fn fromQuaternion(q: Quat) Mat4 {
    const xx = q.x * q.x;
    const yy = q.y * q.y;
    const zz = q.z * q.z;
    const xy = q.x * q.y;
    const xz = q.x * q.z;
    const yz = q.y * q.z;
    const wx = q.w * q.x;
    const wy = q.w * q.y;
    const wz = q.w * q.z;

    return .{
        .m = .{
            .{ 1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0 },
            .{ 2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0 },
            .{ 2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        },
    };
}

/// Multiply two matrices: result = a * b
pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;
    for (0..4) |col| {
        for (0..4) |row| {
            result.m[col][row] = a.m[0][row] * b.m[col][0] +
                a.m[1][row] * b.m[col][1] +
                a.m[2][row] * b.m[col][2] +
                a.m[3][row] * b.m[col][3];
        }
    }
    return result;
}

/// Transform a Vec2 point (treats z=0, w=1 for homogeneous coordinates)
/// Returns only the x,y components after transformation
pub fn transformVec2(self: Mat4, v: Vec2) Vec2 {
    const x = self.m[0][0] * v.x + self.m[1][0] * v.y + self.m[3][0];
    const y = self.m[0][1] * v.x + self.m[1][1] * v.y + self.m[3][1];
    return .{ .x = x, .y = y };
}

/// Transform a Vec3 point (treats w=1 for homogeneous coordinates)
pub fn transformVec3(self: Mat4, v: Vec3) Vec3 {
    const x = self.m[0][0] * v.x + self.m[1][0] * v.y + self.m[2][0] * v.z + self.m[3][0];
    const y = self.m[0][1] * v.x + self.m[1][1] * v.y + self.m[2][1] * v.z + self.m[3][1];
    const z = self.m[0][2] * v.x + self.m[1][2] * v.y + self.m[2][2] * v.z + self.m[3][2];
    return .{ .x = x, .y = y, .z = z };
}

/// Apply 2D rotation to a point in place (optimized, doesn't build full matrix)
/// This is the operation we use for sprite rotation in window space
pub fn rotate2DPoint(x: f32, y: f32, angle: f32) struct { x: f32, y: f32 } {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .x = x * c - y * s,
        .y = x * s + y * c,
    };
}

/// Create an orthographic projection matrix
/// Maps the box [left, right] x [bottom, top] x [near, far] to clip space [-1, 1]³
pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
    const w = right - left;
    const h = top - bottom;
    const d = far - near;
    return .{
        .m = .{
            .{ 2.0 / w, 0, 0, 0 },
            .{ 0, 2.0 / h, 0, 0 },
            .{ 0, 0, -2.0 / d, 0 },
            .{ -(right + left) / w, -(top + bottom) / h, -(far + near) / d, 1 },
        },
    };
}

/// Create a perspective projection matrix
/// Angle in radians
pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / @tan(fovy / 2.0);
    const d = far - near;
    return .{
        .m = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, -(far + near) / d, -1 },
            .{ 0, 0, -(2.0 * far * near) / d, 0 },
        },
    };
}

/// Create a 2D orthographic projection (near=-1, far=1)
pub fn orthographic2D(left: f32, right: f32, bottom: f32, top: f32) Mat4 {
    return orthographic(left, right, bottom, top, -1.0, 1.0);
}

// Imports
const std = @import("std");
const Vec2 = @import("root.zig").Vec2;
const Vec3 = @import("root.zig").Vec3;
const Quat = @import("root.zig").Quat;
