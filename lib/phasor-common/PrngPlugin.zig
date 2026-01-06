seed: u64 = 1337,

const PrngPlugin = @This();

pub fn default() PrngPlugin {
    const time = try std.posix.clock_gettime(std.posix.system.clockid_t.REALTIME);
    const seed: u64 = @intCast(time.nsec);
    return .{
        .seed = seed,
    };
}

pub fn build(self: *PrngPlugin, app: *App) !void {
    const resource = Prng.init(self.seed);
    try app.insertResource(resource);
}

pub const Prng = struct {
    prng: std.Random.DefaultPrng,

    /// Initialize with a 64-bit seed.
    pub fn init(seed: u64) Prng {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    /// Public access to a Random interface view.
    pub fn random(self: *Prng) std.Random {
        return self.prng.random();
    }

    /// Uniform float in [0,1)
    pub fn float32(self: *Prng) f32 {
        return self.random().float(f32);
    }

    /// Uniform float in [0,1)
    pub fn float64(self: *Prng) f64 {
        return self.random().float(f64);
    }

    /// Uniform boolean
    pub fn boolean(self: *Prng) bool {
        return self.random().boolean();
    }

    /// Integer in [0, max) (exclusive upper bound)
    pub fn intLessThan(self: *Prng, comptime T: type, max: T) T {
        return self.random().intRangeLessThan(T, 0, max);
    }

    /// Integer in [min, max] (inclusive upper bound)
    pub fn intRangeAtMost(self: *Prng, comptime T: type, min: T, max: T) T {
        return self.random().intRangeAtMost(T, min, max);
    }

    /// Integer in [min, max) (exclusive upper bound)
    pub fn intRangeLessThan(self: *Prng, comptime T: type, min: T, max: T) T {
        return self.random().intRangeLessThan(T, min, max);
    }

    /// Float in [min, max) (exclusive upper bound)
    pub fn floatRange32(self: *Prng, min: f32, max: f32) f32 {
        return self.float32() * (max - min) + min;
    }

    /// Float in [min, max) (exclusive upper bound), double precision
    pub fn floatRange64(self: *Prng, min: f64, max: f64) f64 {
        return self.float64() * (max - min) + min;
    }

    /// Pick a random value from a slice, or null if empty.
    pub fn pickSlice(self: *Prng, comptime T: type, items: []const T) ?T {
        if (items.len == 0) return null;
        const idx = self.intLessThan(usize, items.len);
        return items[idx];
    }

    /// Pick a random value from a slice and return a pointer, or null if empty.
    pub fn pickSlicePtr(self: *Prng, comptime T: type, items: []T) ?*T {
        if (items.len == 0) return null;
        const idx = self.intLessThan(usize, items.len);
        return &items[idx];
    }

    /// Return random bytes in a buffer
    pub fn fillBytes(self: *Prng, buffer: []u8) void {
        self.random().fill(buffer);
    }
};

// Imports
const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
