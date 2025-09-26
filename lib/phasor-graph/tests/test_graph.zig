const std = @import("std");
const Graph = @import("phasor-graph").Graph;

test "Graph neighbor access and iteration" {
    const allocator = std.testing.allocator;

    var graph = Graph(u32, f32, null).init(allocator);
    defer graph.deinit();

    // Add nodes
    const a = try graph.addNode(1);
    const b = try graph.addNode(2);
    const c = try graph.addNode(3);

    // Add edges
    _ = try graph.addEdge(a, b, 1.5);
    _ = try graph.addEdge(a, c, 2.0);

    // Test neighbors access
    const neighbors = graph.neighbors(a);
    try std.testing.expect(neighbors.len == 2);
    try std.testing.expect(neighbors[0] == b);
    try std.testing.expect(neighbors[1] == c);

    // Test neighbor iteration
    var iter = graph.neighborIterator(a);
    var count: usize = 0;
    while (iter.next()) |item| {
        count += 1;
        if (item.neighbor == b) {
            try std.testing.expect(item.edge == 1.5);
        } else if (item.neighbor == c) {
            try std.testing.expect(item.edge == 2.0);
        }
    }
    try std.testing.expect(count == 2);

    // Test out-degree
    try std.testing.expect(graph.outDegree(a) == 2);
    try std.testing.expect(graph.outDegree(b) == 0);
}

test "Graph basic operations - node and edge management" {
    const allocator = std.testing.allocator;

    var graph = Graph(u32, f32, null).init(allocator);
    defer graph.deinit();

    try std.testing.expect(graph.nodeCount() == 0);
    try std.testing.expect(graph.edgeCount() == 0);

    // Add nodes with weights
    const a = try graph.addNode(10);
    const b = try graph.addNode(20);
    const c = try graph.addNode(30);

    try std.testing.expect(graph.nodeCount() == 3);
    try std.testing.expect(graph.edgeCount() == 0);

    // Check node weights
    try std.testing.expect(graph.getNodeWeight(a) == 10);
    try std.testing.expect(graph.getNodeWeight(b) == 20);
    try std.testing.expect(graph.getNodeWeight(c) == 30);

    // Modify node weight
    graph.setNodeWeight(b, 25);
    try std.testing.expect(graph.getNodeWeight(b) == 25);

    // Add edges
    try std.testing.expect(try graph.addEdge(a, b, 1.5));
    try std.testing.expect(try graph.addEdge(a, c, 2.5));
    try std.testing.expect(try graph.addEdge(b, c, 3.5));

    try std.testing.expect(graph.edgeCount() == 3);

    // Check edge existence
    try std.testing.expect(graph.containsEdge(a, b));
    try std.testing.expect(graph.containsEdge(a, c));
    try std.testing.expect(graph.containsEdge(b, c));
    try std.testing.expect(!graph.containsEdge(b, a)); // Should be false (directed)
    try std.testing.expect(!graph.containsEdge(c, a)); // Should be false (directed)

    // Check out-degrees
    try std.testing.expect(graph.outDegree(a) == 2);
    try std.testing.expect(graph.outDegree(b) == 1);
    try std.testing.expect(graph.outDegree(c) == 0);

    // Try to add duplicate edge
    try std.testing.expect(!try graph.addEdge(a, b, 1.0)); // Should return false
    try std.testing.expect(graph.edgeCount() == 3); // Edge count shouldn't change
}

test "topological sort from seed subgraph without cycles" {
    const allocator = std.testing.allocator;

    var g = Graph(void, u32, null).init(allocator);
    defer g.deinit();

    // Component A (reachable from a): a -> b, a -> c, b -> d, c -> d
    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});
    const d = try g.addNode({});

    // Disconnected Component B: e -> f
    const e = try g.addNode({});
    const f = try g.addNode({});

    _ = try g.addEdge(a, b, 1);
    _ = try g.addEdge(a, c, 1);
    _ = try g.addEdge(b, d, 1);
    _ = try g.addEdge(c, d, 1);

    _ = try g.addEdge(e, f, 1);

    var result = try g.topologicalSortFrom(allocator, a);
    defer result.deinit();

    // Expect exactly 4 nodes in order (a, b, c, d in some valid topo order)
    try std.testing.expect(result.order.len == 4);

    // Verify membership using a DynamicBitSet
    var seen = try std.DynamicBitSet.initEmpty(allocator, g.nodeCount());
    defer seen.deinit();
    for (result.order) |n| seen.set(n);

    try std.testing.expect(seen.isSet(a));
    try std.testing.expect(seen.isSet(b));
    try std.testing.expect(seen.isSet(c));
    try std.testing.expect(seen.isSet(d));
    try std.testing.expect(!seen.isSet(e));
    try std.testing.expect(!seen.isSet(f));

    // Verify partial order constraints: a before b and c; b and c before d
    const idx = struct {
        fn find(slice: []const Graph(void, u32, null).NodeIndex, v: Graph(void, u32, null).NodeIndex) usize {
            var i: usize = 0;
            while (i < slice.len) : (i += 1) {
                if (slice[i] == v) return i;
            }
            return std.math.maxInt(usize);
        }
    };

    const ia = idx.find(result.order, a);
    const ib = idx.find(result.order, b);
    const ic = idx.find(result.order, c);
    const id = idx.find(result.order, d);

    try std.testing.expect(ia < ib);
    try std.testing.expect(ia < ic);
    try std.testing.expect(ib < id or ic < id); // both b and c should be before d
    try std.testing.expect(!result.has_cycles);
}

test "topological sort from seed subgraph detects cycles" {
    const allocator = std.testing.allocator;

    var g = Graph(void, u32, null).init(allocator);
    defer g.deinit();

    // Component with a cycle: x -> y -> z -> x
    const x = try g.addNode({});
    const y = try g.addNode({});
    const z = try g.addNode({});

    _ = try g.addEdge(x, y, 1);
    _ = try g.addEdge(y, z, 1);
    _ = try g.addEdge(z, x, 1);

    var result = try g.topologicalSortFrom(allocator, x);
    defer result.deinit();

    // Cycle within reachable subgraph should be reported
    try std.testing.expect(result.has_cycles);

    // Partial order should be shorter than the reachable set (3)
    try std.testing.expect(result.order.len < 3);
}

test "Graph removeNode removes incident edges and renumbers" {
    const allocator = std.testing.allocator;

    var g = Graph(u32, u32, null).init(allocator);
    defer g.deinit();

    const a = try g.addNode(1); // 0
    const b = try g.addNode(2); // 1
    const c = try g.addNode(3); // 2
    const d = try g.addNode(4); // 3

    _ = try g.addEdge(a, b, 1);
    _ = try g.addEdge(b, c, 1);
    _ = try g.addEdge(c, a, 1);
    _ = try g.addEdge(d, b, 1);
    _ = try g.addEdge(b, b, 1); // self-loop

    try std.testing.expect(g.nodeCount() == 4);
    try std.testing.expect(g.edgeCount() == 5);

    // Remove node b (index 1)
    try g.removeNode(b);

    // Now there should be 3 nodes; indices: a=0, c->1, d->2
    try std.testing.expect(g.nodeCount() == 3);

    // Edges incident to b removed; only c->a remains, which becomes 1->0
    try std.testing.expect(g.edgeCount() == 1);
    try std.testing.expect(g.containsEdge(1, 0));
    try std.testing.expect(!g.containsEdge(0, 1));

    // Check neighbors
    try std.testing.expect(g.outDegree(0) == 0);
    try std.testing.expect(g.outDegree(1) == 1);
    const neigh1 = g.neighbors(1);
    try std.testing.expect(neigh1.len == 1 and neigh1[0] == 0);
}

test "Graph removeNode first and last and out-of-bounds" {
    const allocator = std.testing.allocator;

    var g = Graph(u32, void, null).init(allocator);
    defer g.deinit();

    const n0 = try g.addNode(10); // 0
    const n1 = try g.addNode(20); // 1
    const n2 = try g.addNode(30); // 2

    _ = try g.addEdge(n0, n1, {});
    _ = try g.addEdge(n1, n2, {});

    // Remove first node
    try g.removeNode(n0);
    try std.testing.expect(g.nodeCount() == 2);
    try std.testing.expect(!g.containsEdge(0, 0)); // was 0->1

    // Remove last node (current index 1)
    try g.removeNode(1);
    try std.testing.expect(g.nodeCount() == 1);

    // Out-of-bounds remove should error
    try std.testing.expectError(error.IndicesOutOfBounds, g.removeNode(5));
}
