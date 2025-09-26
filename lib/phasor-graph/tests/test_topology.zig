const std = @import("std");
const Graph = @import("phasor-graph").Graph;

test "Topological sort - empty graph" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.order.len == 0);
    try std.testing.expect(!result.has_cycles);
}

test "Topological sort - single node" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    const a = try graph.addNode({});

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.order.len == 1);
    try std.testing.expect(result.order[0] == a);
    try std.testing.expect(!result.has_cycles);
}

test "Topological sort - simple DAG" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a simple DAG: A -> B -> C
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, c, {});

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.order.len == 3);
    try std.testing.expect(!result.has_cycles);

    // Check that A comes before B, and B comes before C
    var a_pos: usize = undefined;
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;

    for (result.order, 0..) |node, i| {
        if (node == a) a_pos = i;
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
    }

    try std.testing.expect(a_pos < b_pos);
    try std.testing.expect(b_pos < c_pos);
}

test "Topological sort - complex DAG" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a diamond DAG: A -> B, A -> C, B -> D, C -> D
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(a, c, {});
    _ = try graph.addEdge(b, d, {});
    _ = try graph.addEdge(c, d, {});

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.order.len == 4);
    try std.testing.expect(!result.has_cycles);

    // Check that A comes first, D comes last, and B,C come before D
    var a_pos: usize = undefined;
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;
    var d_pos: usize = undefined;

    for (result.order, 0..) |node, i| {
        if (node == a) a_pos = i;
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
        if (node == d) d_pos = i;
    }

    try std.testing.expect(a_pos == 0); // A should be first
    try std.testing.expect(d_pos == 3); // D should be last
    try std.testing.expect(a_pos < b_pos);
    try std.testing.expect(a_pos < c_pos);
    try std.testing.expect(b_pos < d_pos);
    try std.testing.expect(c_pos < d_pos);
}

test "Topological sort - cyclic graph" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a cycle: A -> B -> C -> A
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, c, {});
    _ = try graph.addEdge(c, a, {}); // This creates a cycle

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.has_cycles);
    try std.testing.expect(result.order.len < 3); // Should not include all nodes
}

test "Topological sort - disconnected components" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create two disconnected components: A -> B and C -> D
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(c, d, {});

    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(result.order.len == 4);
    try std.testing.expect(!result.has_cycles);

    // Check that dependencies are respected within each component
    var a_pos: usize = undefined;
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;
    var d_pos: usize = undefined;

    for (result.order, 0..) |node, i| {
        if (node == a) a_pos = i;
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
        if (node == d) d_pos = i;
    }

    try std.testing.expect(a_pos < b_pos);
    try std.testing.expect(c_pos < d_pos);
}

test "Cycle detection - DAG" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a DAG: A -> B -> C, A -> C
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, c, {});
    _ = try graph.addEdge(a, c, {});

    try std.testing.expect(!try graph.hasCycles(allocator));
}

test "Cycle detection - simple cycle" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a cycle: A -> B -> A
    const a = try graph.addNode({});
    const b = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, a, {});

    try std.testing.expect(try graph.hasCycles(allocator));
}

test "Cycle detection - self loop" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a self-loop: A -> A
    const a = try graph.addNode({});
    _ = try graph.addEdge(a, a, {});

    try std.testing.expect(try graph.hasCycles(allocator));
}

test "Cycle detection - empty graph" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    try std.testing.expect(!try graph.hasCycles(allocator));
}
