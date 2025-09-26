pub const test_app = @import("test_app.zig");
pub const test_commands = @import("test_commands.zig");
pub const test_events = @import("test_events.zig");
pub const test_resources = @import("test_resources.zig");
pub const test_schedules = @import("test_schedules.zig");
pub const test_sub_app = @import("test_sub_app.zig");

const Self = @This();

test "Import tests" {
    _ = Self.test_app;
    _ = Self.test_commands;
    _ = Self.test_events;
    _ = Self.test_resources;
    _ = Self.test_schedules;
    _ = Self.test_sub_app;
}
