test "World registerEvent adds Events(T) resource" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);

    const events = world.getResource(Events(i32));
    try std.testing.expect(events != null);

    const events_mut = world.getResourceMut(Events(i32));
    try std.testing.expect(events_mut != null);

    // check capacity
    try std.testing.expectEqual(@as(usize, 4), events_mut.?.cap);
}

test "EventWriter enqueues into Events(T)" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);

    const sys = struct {
        pub fn f(w: EventWriter(i32)) !void {
            try w.send(7);
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);
    defer sched.deinit();

    try sched.add(sys);
    try sched.run(world);

    // Subscribe to read the event
    const events = world.getResource(Events(i32)).?;
    var receiver = try events.subscribe();
    defer receiver.deinit();
    const ev = receiver.tryRecv();
    try std.testing.expectEqual(@as(i32, 7), ev);
}

test "EventReader drains all queued events" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);

    // Preload some events
    const events = world.getResource(Events(i32)).?;
    try events.send(1);
    try events.send(2);
    try events.send(3);

    const sys = struct {
        pub fn f(r: EventReader(i32)) !void {
            var seen: [3]i32 = undefined;
            var i: usize = 0;
            while (r.tryRecv()) |ev| : (i += 1) {
                seen[i] = ev;
            }
            try std.testing.expectEqualSlices(i32, &.{ 1, 2, 3 }, seen[0..i]);
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);
    defer sched.deinit();

    try sched.add(sys);
    try sched.run(world);
}

test "EventWriter in one system, EventReader in another" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);

    const write_sys = struct {
        pub fn f(w: EventWriter(i32)) !void {
            try w.send(42);
        }
    }.f;

    const read_sys = struct {
        pub fn f(r: EventReader(i32)) !void {
            const val = r.tryRecv();
            try std.testing.expectEqual(@as(i32, 42), val);
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);
    defer sched.deinit();

    try sched.add(write_sys);
    try sched.add(read_sys);

    try sched.run(world);
}

test "EventWriter in one system, EventReaders in two systems" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);

    const write_sys = struct {
        pub fn f(w: EventWriter(i32)) !void {
            try w.send(100);
        }
    }.f;

    const read_sys1 = struct {
        pub fn f(r: EventReader(i32)) !void {
            const val = r.tryRecv();
            try std.testing.expectEqual(@as(i32, 100), val);
        }
    }.f;

    const read_sys2 = struct {
        pub fn f(r: EventReader(i32)) !void {
            const val = r.tryRecv();
            try std.testing.expectEqual(@as(i32, 100), val);
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);
    defer sched.deinit();

    try sched.add(write_sys);
    try sched.add(read_sys1);
    try sched.add(read_sys2);

    try sched.run(world);
}

test "EventReader subscription is cleaned up when the schedule is deinit'd" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);
    const events = world.getResource(Events(i32)).?;

    try std.testing.expectEqual(0, events.getSubscriptionCount());

    const read_sys = struct {
        pub fn f(r: EventReader(i32)) !void {
            _ = r.tryRecv();
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);

    try sched.add(read_sys);
    try sched.run(world);

    try std.testing.expectEqual(1, events.getSubscriptionCount());

    sched.deinit();

    try std.testing.expectEqual(0, events.getSubscriptionCount());
}

test "EventReader subscription is cleaned up when the system is removed from schedule" {
    const alloc = std.testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    try world.registerEvent(i32, 4);
    const events = world.getResource(Events(i32)).?;

    try std.testing.expectEqual(0, events.getSubscriptionCount());

    const read_sys = struct {
        pub fn f(r: EventReader(i32)) !void {
            _ = r.tryRecv();
        }
    }.f;

    var sched = try Schedule.init(alloc, "Test", world);

    try sched.add(read_sys);
    try sched.run(world);

    try std.testing.expectEqual(1, events.getSubscriptionCount());

    try sched.remove(read_sys);

    try std.testing.expectEqual(0, events.getSubscriptionCount());

    sched.deinit();
}

// Imports
const std = @import("std");

const ecs = @import("phasor-ecs");
const World = ecs.World;
const Schedule = ecs.Schedule;
const Events = ecs.Events;
const EventWriter = ecs.EventWriter;
const EventReader = ecs.EventReader;
const Commands = ecs.Commands;
