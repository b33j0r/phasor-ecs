//! A type-erased wrapper around a SubApp that allows us to store
//! different SubApp instances in the same collection.
ptr: *anyopaque,
vtable: *const VTable,

const Self = @This();

const VTable = struct {
    waitForStop: *const fn (self: *anyopaque, timeout_ns: usize) anyerror!void,
    deinit: *const fn (self: *anyopaque) void,
};

pub fn from(SubAppType: type) Self {
    return .{
        .ptr = @ptrCast(*SubAppType),
        .vtable = &.{
            .waitForStop = @ptrCast(SubAppType.waitForStop),
            .deinit = @ptrCast(SubAppType.deinit),
        },
    };
}

pub fn waitForStop(self: *Self, timeout_ns: usize) !void {
    _ = self;
    _ = timeout_ns;
    return error.NotImplemented;
}

pub fn deinit(self: *Self) void {
    _ = self;
}
