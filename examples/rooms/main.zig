const std = @import("std");
const phasor = @import("phasor-ecs");
const App = phasor.App;
const DefaultRunner = phasor.DefaultRunner;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    _ = try app.addSchedule("BeforeUpdate");
    try app.scheduleBefore("BeforeUpdate", "Update");

    _ = try app.addSchedule("AfterUpdate");
    try app.scheduleAfter("AfterUpdate", "Update");

    try app.addSystem("Update", print_update);
    try app.addSystem("BeforeUpdate", print_before_update);
    try app.addSystem("AfterUpdate", print_after_update);

    try app.run();
}

pub fn print_before_update(tx: *phasor.db.Transaction) !void {
    _ = tx;
    std.debug.print("Not yet, Phasor!\n", .{});
}

pub fn print_update(tx: *phasor.db.Transaction) !void {
    _ = tx;
    std.debug.print("Hello, Phasor!\n", .{});
}

pub fn print_after_update(tx: *phasor.db.Transaction) !void {
    _ = tx;
    std.debug.print("Goodbye, Phasor!\n", .{});
}
