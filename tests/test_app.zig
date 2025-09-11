const std = @import("std");
const ecs = @import("phasor-ecs");
const App = ecs.App;
const Res = ecs.Res;

const Recorder = struct {
    log: std.ArrayListUnmanaged([]const u8) = .empty,
};

test "App.addSystem adds to existing schedule and runs in order" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    const s1 = struct {
        pub fn run(rec: Res(Recorder)) !void {
            try rec.ptr.log.append(std.testing.allocator, "A");
        }
    }.run;
    const s2 = struct {
        pub fn run(rec: Res(Recorder)) !void {
            try rec.ptr.log.append(std.testing.allocator, "B");
        }
    }.run;

    try app.addSystem("Update", s1);
    try app.addSystem("Update", s2);

    try app.step();

    const rec = app.world.getResource(Recorder).?;
    try std.testing.expectEqual(@as(usize, 2), rec.log.items.len);
    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "A"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "B"));

    // cleanup Recorder resource allocations
    var rec_mut = app.world.getResourceMut(Recorder).?;
    rec_mut.log.deinit(allocator);
}

fn appendMark(comptime name: []const u8) fn (Res(Recorder)) anyerror!void {
    return struct {
        pub fn run(rec: Res(Recorder)) !void {
            try rec.ptr.log.append(std.testing.allocator, name);
        }
    }.run;
}

test "Schedules can be added and ordered with before/after" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    // Add another schedule
    _ = try app.addSchedule("Render");

    // Constrain order: Update -> Render
    try app.scheduleBefore("Update", "Render");

    try app.addSystem("Update", appendMark("U"));
    try app.addSystem("Render", appendMark("R"));

    try app.step();

    const rec = app.world.getResource(Recorder).?;
    try std.testing.expectEqual(@as(usize, 2), rec.log.items.len);

    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "U"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "R"));

    var rec_mut = app.world.getResourceMut(Recorder).?;
    rec_mut.log.deinit(allocator);
}

test "Schedule after and before constraints around Update" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    try app.insertResource(Recorder{});

    _ = try app.addSchedule("Render");
    _ = try app.addSchedule("AfterUpdate");

    // Update -> AfterUpdate -> Render
    try app.scheduleAfter("AfterUpdate", "Update");
    try app.scheduleBefore("AfterUpdate", "Render");

    try app.addSystem("Update", appendMark("U"));
    try app.addSystem("AfterUpdate", appendMark("A"));
    try app.addSystem("Render", appendMark("R"));

    try app.step();

    const rec = app.world.getResource(Recorder).?;
    try std.testing.expectEqual(@as(usize, 3), rec.log.items.len);
    try std.testing.expect(std.mem.eql(u8, rec.log.items[0], "U"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[1], "A"));
    try std.testing.expect(std.mem.eql(u8, rec.log.items[2], "R"));

    var rec_mut = app.world.getResourceMut(Recorder).?;
    rec_mut.log.deinit(allocator);
}
