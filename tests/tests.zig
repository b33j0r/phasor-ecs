pub const test_schedules = @import("test_schedules.zig");
pub const test_app = @import("test_app.zig");
pub const test_resources = @import("test_resources.zig");
pub const test_commands = @import("test_commands.zig");

const std = @import("std");
const Self = @This();

test "Import tests" {
    std.testing.refAllDecls(Self);
}
