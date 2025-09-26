const std = @import("std");
const Graph = @import("phasor-graph").Graph;

test "Dijkstra shortest path with numeric weights" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, u32, null).init(allocator);
    defer graph.deinit();

    // Create a diamond graph with different path costs
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});

    _ = try graph.addEdge(a, b, 1); // Short path: a->b->d (cost 4)
    _ = try graph.addEdge(a, c, 10); // Long path: a->c->d (cost 11)
    _ = try graph.addEdge(b, d, 3);
    _ = try graph.addEdge(c, d, 1);

    // Run Dijkstra from node a
    var result = (try graph.dijkstra(allocator, a)) orelse {
        try std.testing.expect(false); // Should not be null
        return;
    };
    defer result.deinit();

    // Check distances
    try std.testing.expect(result.distanceTo(a).? == 0);
    try std.testing.expect(result.distanceTo(b).? == 1);
    try std.testing.expect(result.distanceTo(c).? == 10);
    try std.testing.expect(result.distanceTo(d).? == 4); // Should take shorter path through b

    // Check reachability
    try std.testing.expect(result.isReachable(a));
    try std.testing.expect(result.isReachable(b));
    try std.testing.expect(result.isReachable(c));
    try std.testing.expect(result.isReachable(d));

    // Check shortest path to d
    const path = (try result.pathTo(allocator, d)) orelse {
        try std.testing.expect(false); // Should not be null
        return;
    };
    defer allocator.free(path);

    try std.testing.expect(path.len == 3);
    try std.testing.expect(path[0] == a);
    try std.testing.expect(path[1] == b);
    try std.testing.expect(path[2] == d);
}
