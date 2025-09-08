graph: ScheduleGraph,

const std = @import("std");

const root = @import("root.zig");
const Schedule = root.Schedule;

const phasor_graph = @import("phasor-graph");
const Graph = phasor_graph.Graph;

/// `Relationship` is the edge weight in the schedule graph.
pub const Relationship = enum {
    Concurrent,
    Before,
    After,
};

/// `ScheduleGraph` represents a directed graph where nodes are systems and edges define execution relationships.
pub const ScheduleGraph = Graph(Schedule, Relationship, null);
