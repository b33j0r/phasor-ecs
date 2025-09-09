const std = @import("std");
const phasor = @import("phasor-ecs");
const App = phasor.App;
const DefaultRunner = phasor.DefaultRunner;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var app = App.init(allocator);
    defer app.deinit();

    app.setRunner(DefaultRunner.run);

    try app.run();
}
