pub const PrngPlugin = @import("PrngPlugin.zig");
pub const Prng = PrngPlugin.Prng;

// General-purpose components
pub const Bounds = @import("Bounds.zig");
pub const Padding = @import("Padding.zig");
pub const Color = @import("Color.zig");
pub const Mat4 = @import("Mat4.zig");
pub const Quat = @import("Quat.zig");
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

pub const Transform2d = struct {
    translation: Vec2 = .{ .x = 0.0, .y = 0.0 },
    scale: Vec2 = .{ .x = 1.0, .y = 1.0 },
    rotation: f32 = 0.0, // radians
};

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



