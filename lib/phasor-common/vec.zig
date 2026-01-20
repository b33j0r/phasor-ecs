const std = @import("std");

pub const Vec2 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub fn splat(value: f32) Vec2 {
        return .{ .x = value, .y = value };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vec2, factor: f32) Vec2 {
        return .{ .x = self.x * factor, .y = self.y * factor };
    }

    pub fn length_squared(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub fn length(self: Vec2) f32 {
        return std.math.sqrt(self.length_squared());
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0.0) {
            return self;
        }
        return self.scale(1.0 / len);
    }

    pub fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn toVec3(self: Vec2, z: f32) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = z };
    }

    pub fn fromVec3(v: Vec3) Vec2 {
        return .{ .x = v.x, .y = v.y };
    }
};

pub const Vec3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn splat(value: f32) Vec3 {
        return .{ .x = value, .y = value, .z = value };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn scale(self: Vec3, factor: f32) Vec3 {
        return .{ .x = self.x * factor, .y = self.y * factor, .z = self.z * factor };
    }

    pub fn length_squared(self: Vec3) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    pub fn length(self: Vec3) f32 {
        return std.math.sqrt(self.length_squared());
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        if (len == 0.0) {
            return self;
        }
        return self.scale(1.0 / len);
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn toVec2(self: Vec3) Vec2 {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn fromVec2(v: Vec2, z: f32) Vec3 {
        return .{ .x = v.x, .y = v.y, .z = z };
    }
};