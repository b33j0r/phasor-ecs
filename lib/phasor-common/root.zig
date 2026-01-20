pub const PrngPlugin = @import("PrngPlugin.zig");
pub const Prng = PrngPlugin.Prng;

// General-purpose components
pub const Bounds = @import("Bounds.zig");
pub const Padding = @import("Padding.zig");
pub const Color = @import("Color.zig");
pub const Mat4 = @import("mat4.zig").Mat4;
pub const Quat = @import("quat.zig").Quat;
pub const vec = @import("vec.zig");
pub const Vec2 = vec.Vec2;
pub const Vec3 = vec.Vec3;

pub const ClearColor = struct {
    color: Color = Color.BSOD,
};

pub const DeltaTime = struct {
    seconds: f32,
};

pub const ElapsedTime = struct {
    seconds: f32,
};

pub const transform = @import("transform.zig");
pub const Transform2d = transform.Transform2d;
pub const Transform3d = transform.Transform3d;

pub const RenderBounds = struct {
    width: f32,
    height: f32,

    pub fn widthInt(self: RenderBounds) i32 {
        return @intFromFloat(self.width);
    }

    pub fn heightInt(self: RenderBounds) i32 {
        return @intFromFloat(self.height);
    }
};

pub const WindowBounds = struct {
    width: i32,
    height: i32,
};

pub const TargetFps = struct {
    value: i32,
};

pub const WindowResized = struct {
    width: i32,
    height: i32,
};

pub const ContentScale = struct {
    x: f32 = 1.0,
    y: f32 = 1.0,
};

pub const ContentScaleChanged = struct {
    x: f32,
    y: f32,
};

test {
    _ = @import("Bounds.zig");
    _ = @import("Color.zig");
    _ = @import("mat4.zig");
    _ = @import("Padding.zig");
    _ = @import("PrngPlugin.zig");
    _ = @import("quat.zig");
    _ = @import("transform.zig");
    _ = @import("vec.zig");
}
