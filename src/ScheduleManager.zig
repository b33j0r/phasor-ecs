allocator: std.mem.Allocator,
graph: ScheduleGraph,
schedules: std.ArrayListUnmanaged(Schedule) = .empty,
name_to_node: std.StringHashMapUnmanaged(ScheduleGraph.NodeIndex) = .empty,

const std = @import("std");

const root = @import("root.zig");
const Schedule = root.Schedule;

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
    };
}

pub fn deinit(self: *ScheduleManager) void {
    // deinit schedules
    for (self.schedules.items) |*s| s.deinit();
    self.schedules.deinit(self.allocator);
    // deinit name map
    self.name_to_node.deinit(self.allocator);
    // deinit graph
    self.graph.deinit();
}

pub fn addSchedule(self: *ScheduleManager, name: []const u8) !*Schedule {
    if (self.name_to_node.get(name)) |_| {
        // return existing schedule pointer
        const node = self.name_to_node.get(name).?;
        const idx = self.graph.getNodeWeight(node);
        return &self.schedules.items[idx];
    }
    // create schedule and add to list
    const schedule = try Schedule.initWithLabel(self.allocator, name);
    try self.schedules.append(self.allocator, schedule);
    const idx_u32: u32 = @intCast(self.schedules.items.len - 1);
    const node = try self.graph.addNode(idx_u32);
    // Use the owned label slice from the schedule as key in the map
    try self.name_to_node.put(self.allocator, self.schedules.items[idx_u32].label, node);
    return &self.schedules.items[idx_u32];
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

pub fn addSystem(self: *ScheduleManager, schedule_name: []const u8, comptime system_fn: anytype) !void {
    const node = self.name_to_node.get(schedule_name) orelse return Error.ScheduleNotFound;
    const idx = self.graph.getNodeWeight(node);
    try self.schedules.items[idx].add(system_fn);
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
        const sched_idx = self.manager.graph.getNodeWeight(node);
        return &self.manager.schedules.items[sched_idx];
    }

    pub fn deinit(self: *ScheduleIterator) void {
        self.topo.deinit();
    }
};

pub fn iterator(self: *ScheduleManager) !ScheduleIterator {
    var result = try self.graph.topologicalSort(self.allocator);
    if (result.has_cycles) {
        result.deinit();
        return Error.CyclicDependency;
    }
    return ScheduleIterator.init(self, result);
}
