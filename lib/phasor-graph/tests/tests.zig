const test_backends = @import("test_backends.zig");
const test_dijkstra = @import("test_dijkstra.zig");
const test_graph = @import("test_graph.zig");
const test_real_world = @import("test_real_world.zig");
const test_topology = @import("test_topology.zig");
const test_traversal = @import("test_traversal.zig");

// Ensure semantic analyzer sees them
comptime {
    _ = test_backends;
    _ = test_dijkstra;
    _ = test_graph;
    _ = test_real_world;
    _ = test_topology;
    _ = test_traversal;
}
