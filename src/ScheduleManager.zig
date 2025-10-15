allocator: std.mem.Allocator,
graph: ScheduleGraph,
schedules: std.ArrayListUnmanaged(Schedule) = .empty,
name_to_node: std.StringHashMapUnmanaged(ScheduleGraph.NodeIndex) = .empty,
// Map stable schedule IDs -> dense schedules array indices
id_to_index: std.AutoHashMapUnmanaged(u32, u32) = .empty,
// Next stable schedule ID to assign
next_id: u32 = 0,

const std = @import("std");

const root = @import("root.zig");
const Schedule = root.Schedule;
const World = root.World;

const phasor_graph = @import("phasor-graph");
const Graph = phasor_graph.Graph;

const ScheduleManager = @This();

/// Edge type carries no data for schedule ordering
pub const Relationship = void;

/// Use schedule indices (u32) as node weights
pub const ScheduleGraph = Graph(u32, Relationship, null);

pub const Error = error{
    ScheduleAlreadyExists,
    ScheduleNotFound,
    CyclicDependency,
};

pub fn init(allocator: std.mem.Allocator) ScheduleManager {
    return ScheduleManager{
        .allocator = allocator,
        .graph = ScheduleGraph.init(allocator),
        .schedules = .empty,
        .name_to_node = .empty,
        .id_to_index = .empty,
        .next_id = 0,
    };
}

pub fn deinit(self: *ScheduleManager) void {
    // deinit schedules
    for (self.schedules.items) |*s| s.deinit();
    self.schedules.deinit(self.allocator);
    // deinit name map
    self.name_to_node.deinit(self.allocator);
    // deinit id map
    self.id_to_index.deinit(self.allocator);
    // deinit graph
    self.graph.deinit();
}

pub fn addSchedule(self: *ScheduleManager, name: []const u8) !*Schedule {
    if (self.name_to_node.get(name)) |_| {
        // return existing schedule pointer
        const node = self.name_to_node.get(name).?;
        const id = self.graph.getNodeWeight(node);
        const idx_u32 = self.id_to_index.get(id).?;
        const idx: usize = @intCast(idx_u32);
        return &self.schedules.items[idx];
    }
    // create schedule and add to list
    const schedule = try Schedule.initWithLabel(self.allocator, name);
    try self.schedules.append(self.allocator, schedule);
    const idx_u32_now: u32 = @intCast(self.schedules.items.len - 1);
    const id = self.next_id;
    self.next_id += 1;
    const node = try self.graph.addNode(id);
    // Map stable ID to dense index
    try self.id_to_index.put(self.allocator, id, idx_u32_now);
    // Use the owned label slice from the schedule as key in the map
    try self.name_to_node.put(self.allocator, self.schedules.items[idx_u32_now].label, node);
    return &self.schedules.items[idx_u32_now];
}

pub fn removeSchedule(self: *ScheduleManager, name: []const u8) !void {
    const node = self.name_to_node.get(name) orelse return Error.ScheduleNotFound;
    const id = self.graph.getNodeWeight(node);
    const idx_u32 = self.id_to_index.get(id) orelse return Error.ScheduleNotFound;
    const idx: usize = @intCast(idx_u32);

    // 1) Remove from name map BEFORE deinit, because the map stores a slice into schedule.label.
    _ = self.name_to_node.remove(name);

    // 2) Remove node from graph and id->index map
    _ = try self.graph.removeNode(node);
    _ = self.id_to_index.remove(id);

    // 3) Densify schedules by swap-removing the element at idx
    const last_index = self.schedules.items.len - 1;

    // Deinit the schedule being removed
    self.schedules.items[idx].deinit();

    if (idx != last_index) {
        // Move the last schedule into the vacated slot
        self.schedules.items[idx] = self.schedules.items[last_index];

        // Update the moved schedule's ID->index mapping
        const moved_label = self.schedules.items[idx].label;
        const moved_node = self.name_to_node.get(moved_label).?;
        const moved_id = self.graph.getNodeWeight(moved_node);
        try self.id_to_index.put(self.allocator, moved_id, @as(u32, @intCast(idx)));
    }

    // Shrink the array (do not deinit the moved schedule)
    _ = self.schedules.pop();
}

pub fn scheduleBefore(self: *ScheduleManager, name: []const u8, other: []const u8) !void {
    const a = self.name_to_node.get(name) orelse return Error.ScheduleNotFound;
    const b = self.name_to_node.get(other) orelse return Error.ScheduleNotFound;
    _ = try self.graph.addEdge(a, b, {});
}

pub fn scheduleAfter(self: *ScheduleManager, name: []const u8, other: []const u8) !void {
    const a = self.name_to_node.get(name) orelse return Error.ScheduleNotFound;
    const b = self.name_to_node.get(other) orelse return Error.ScheduleNotFound;
    _ = try self.graph.addEdge(b, a, {});
}

pub fn scheduleBetween(self: *ScheduleManager, name: []const u8, first: []const u8, last: []const u8) !void {
    try self.scheduleAfter(name, first);
    try self.scheduleBefore(name, last);
}

pub fn addScheduleBetween(self: *ScheduleManager, name: []const u8, first: []const u8, last: []const u8) !*Schedule {
    const sched = try self.addSchedule(name);
    try self.scheduleBetween(name, first, last);
    return sched;
}

pub fn addSystem(self: *ScheduleManager, schedule_name: []const u8, comptime system_fn: anytype, world: *World) !void {
    const node = self.name_to_node.get(schedule_name) orelse return Error.ScheduleNotFound;
    const id = self.graph.getNodeWeight(node);
    const idx_u32 = self.id_to_index.get(id) orelse return Error.ScheduleNotFound;
    const idx: usize = @intCast(idx_u32);
    try self.schedules.items[idx].addWithWorld(system_fn, world);
}

pub const ScheduleIterator = struct {
    manager: *const ScheduleManager,
    topo: ScheduleGraph.TopologicalSortResult,
    index: usize,

    pub fn init(manager: *const ScheduleManager, topo: ScheduleGraph.TopologicalSortResult) ScheduleIterator {
        return ScheduleIterator{ .manager = manager, .topo = topo, .index = 0 };
    }

    pub fn next(self: *ScheduleIterator) ?*Schedule {
        if (self.index >= self.topo.order.len) return null;
        const node = self.topo.order[self.index];
        self.index += 1;
        const id = self.manager.graph.getNodeWeight(node);
        const sched_idx_u32 = self.manager.id_to_index.get(id).?;
        const sched_idx: usize = @intCast(sched_idx_u32);
        return &self.manager.schedules.items[sched_idx];
    }

    pub fn deinit(self: *ScheduleIterator) void {
        self.topo.deinit();
    }
};

pub fn iterator(self: *ScheduleManager, startNode: []const u8) !ScheduleIterator {
    const start = self.name_to_node.get(startNode) orelse return Error.ScheduleNotFound;
    var result = try self.graph.topologicalSortFrom(self.allocator, start);
    if (result.has_cycles) {
        result.deinit();
        return Error.CyclicDependency;
    }
    return ScheduleIterator.init(self, result);
}
