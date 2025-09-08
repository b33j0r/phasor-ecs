pub const test_schedules = @import("test_schedules.zig");

const std = @import("std");
const Self = @This();

test "Import tests" {
    std.testing.refAllDecls(Self);
}
