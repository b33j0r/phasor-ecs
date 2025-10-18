x: f32,
y: f32,
width: f32,
height: f32,

const Bounds = @This();

pub const Int32 = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn fromBounds(b: Bounds) Int32 {
        return Int32{
            .x = @intFromFloat(b.x),
            .y = @intFromFloat(b.y),
            .width = @intFromFloat(b.width),
            .height = @intFromFloat(b.height),
        };
    }
};

/// Returns the center point of the bounds
pub fn center(self: Bounds) Vec2 {
    return Vec2{
        .x = self.x + self.width * 0.5,
        .y = self.y + self.height * 0.5,
    };
}

/// Returns true if the point is within the bounds
pub fn contains(self: Bounds, point: Vec2) bool {
    return point.x >= self.x and point.x <= (self.x + self.width) and
        point.y >= self.y and point.y <= (self.y + self.height);
}

/// Returns true if the two bounds intersect
pub fn intersects(self: Bounds, other: Bounds) bool {
    return !(other.x > (self.x + self.width) or
        (other.x + other.width) < self.x or
        other.y > (self.y + self.height) or
        (other.y + other.height) < self.y);
}

/// Merges two bounds into one that encompasses both
pub fn merge(self: Bounds, other: Bounds) Bounds {
    const min_x = @min(self.x, other.x);
    const min_y = @min(self.y, other.y);
    const max_x = @max(self.x + self.width, other.x + other.width);
    const max_y = @max(self.y + self.height, other.y + other.height);

    return Bounds{
        .x = min_x,
        .y = min_y,
        .width = max_x - min_x,
        .height = max_y - min_y,
    };
}

/// Expands the bounds by the given amount in all directions
pub fn offset(self: Bounds, amount: f32) Bounds {
    return Bounds{
        .x = self.x - amount,
        .y = self.y - amount,
        .width = self.width + amount * 2,
        .height = self.height + amount * 2,
    };
}

// Generic Conversions

pub fn toRect(self: *const Bounds, comptime T: type) T {
    const S = resolveStructType(T);

    comptime {
        if (@typeInfo(S) != .@"struct") {
            @compileError("toRect: target type must be a struct");
        }
    }

    var out: T = undefined;

    // Copy all matching fields from Bounds into T
    inline for (@typeInfo(S).@"struct".fields) |df| {
        if (comptime structHasField(Bounds, df.name)) {
            const src_val = @field(self.*, df.name);
            @field(out, df.name) = convertValue(df.type, src_val);
        }
    }

    // Compile-time validation: ensure at least one matching field exists
    comptime {
        var has_match = false;
        for (@typeInfo(S).@"struct".fields) |df| {
            if (structHasField(Bounds, df.name)) {
                has_match = true;
            }
        }
        if (!has_match) {
            @compileError("toRect: no matching fields between Bounds and target type");
        }
    }

    return out;
}

test toRect {
    const SomeRect = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    };
    const b = Bounds{
        .x = 10.5,
        .y = 20.5,
        .width = 100.5,
        .height = 200.5,
    };
    const sr = b.toRect(SomeRect);
    try std.testing.expectEqual(10, sr.x);
    try std.testing.expectEqual(20, sr.y);
    try std.testing.expectEqual(100, sr.width);
    try std.testing.expectEqual(200, sr.height);
}

pub fn fromRect(rect: anytype) Bounds {
    const RectT = @TypeOf(rect);

    var out = Bounds{
        .x = 0.0,
        .y = 0.0,
        .width = 0.0,
        .height = 0.0,
    };

    // Copy all matching fields from rect into Bounds
    inline for (@typeInfo(Bounds).@"struct".fields) |bf| {
        if (comptime structHasField(RectT, bf.name)) {
            const val = if (@typeInfo(RectT) == .pointer) @field(rect.*, bf.name) else @field(rect, bf.name);
            @field(out, bf.name) = convertValue(bf.type, val);
        }
    }

    // Compile-time validation: ensure at least one matching field exists
    comptime {
        var has_match = false;
        for (@typeInfo(Bounds).@"struct".fields) |bf| {
            if (structHasField(RectT, bf.name)) {
                has_match = true;
            }
        }
        if (!has_match) {
            @compileError("fromRect: no matching fields between source and Bounds");
        }
    }

    return out;
}

test fromRect {
    const SomeRect = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    };
    const sr = SomeRect{
        .x = 10,
        .y = 20,
        .width = 100,
        .height = 200,
    };
    const br = fromRect(sr);
    try std.testing.expectEqual(10.0, br.x);
    try std.testing.expectEqual(20.0, br.y);
    try std.testing.expectEqual(100.0, br.width);
    try std.testing.expectEqual(200.0, br.height);
}

// Imports
const std = @import("std");

const root = @import("root.zig");
const Vec2 = root.Vec2;

const meta = @import("meta.zig");
const resolveStructType = meta.resolveStructType;
const structHasField = meta.structHasField;
const convertValue = meta.convertValue;
