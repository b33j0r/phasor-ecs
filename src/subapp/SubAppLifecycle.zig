//! A type-erased wrapper around a SubApp that allows us to store
//! different SubApp instances in the same collection.

const Self = @This();

pub fn stop(self: *Self) void {
    _ = self;
}

pub fn waitForStop(self: *Self, timeout_ns: usize) !void {
    _ = self;
    _ = timeout_ns;
    return error.NotImplemented;
}
