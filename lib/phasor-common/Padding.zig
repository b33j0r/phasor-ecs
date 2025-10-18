top: f32,
right: f32,
bottom: f32,
left: f32,

const Padding = @This();

/// Creates padding with the same value on all sides
pub fn splat(value: f32) Padding {
    return Padding{
        .top = value,
        .right = value,
        .bottom = value,
        .left = value,
    };
}

/// Creates padding with zero on all sides
pub fn zero() Padding {
    return Padding{
        .top = 0,
        .right = 0,
        .bottom = 0,
        .left = 0,
    };
}

/// Creates padding with horizontal and vertical values
pub fn symmetric(horiz: f32, vert: f32) Padding {
    return Padding{
        .top = vert,
        .right = horiz,
        .bottom = vert,
        .left = horiz,
    };
}

/// Creates padding with individual values for each side
pub fn sides(top: f32, right: f32, bottom: f32, left: f32) Padding {
    return Padding{
        .top = top,
        .right = right,
        .bottom = bottom,
        .left = left,
    };
}

/// Calculates the content bounds by applying padding to the given bounds
pub fn applyTo(self: Padding, bounds: Bounds) Bounds {
    return Bounds{
        .x = bounds.x + self.left,
        .y = bounds.y + self.top,
        .width = @max(0, bounds.width - self.left - self.right),
        .height = @max(0, bounds.height - self.top - self.bottom),
    };
}

/// Returns the total horizontal padding (left + right)
pub fn horizontal(self: Padding) f32 {
    return self.left + self.right;
}

/// Returns the total vertical padding (top + bottom)
pub fn vertical(self: Padding) f32 {
    return self.top + self.bottom;
}

// Imports
const std = @import("std");
const Bounds = @import("Bounds.zig");