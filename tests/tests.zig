pub const test_schedules = @import("test_schedules.zig");
pub const test_app = @import("test_app.zig");

const std = @import("std");
const Self = @This();

test "Import tests" {
    std.testing.refAllDecls(Self);
}
