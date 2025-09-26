const std = @import("std");
const Graph = @import("phasor-graph").Graph;
const CsrStorage = @import("phasor-graph").CsrStorage;
const MatrixStorage = @import("phasor-graph").MatrixStorage;

/// Test helper to run the same test with both backends
fn testWithBothBackends(comptime testFn: anytype, comptime NodeType: type, comptime EdgeType: type) !void {
    // Test with CSR backend (default)
    try testFn(NodeType, EdgeType, null);

    // Test with Matrix backend
    try testFn(NodeType, EdgeType, MatrixStorage(NodeType, EdgeType));
}

/// Test basic graph operations (addNode, addEdge, containsEdge, etc.)
fn testBasicOperations(comptime NodeType: type, comptime EdgeType: type, comptime StorageType: ?type) !void {
    const allocator = std.testing.allocator;
    var graph = Graph(NodeType, EdgeType, StorageType).init(allocator);
    defer graph.deinit();

    try std.testing.expect(graph.nodeCount() == 0);
    try std.testing.expect(graph.edgeCount() == 0);

    // Add nodes with weights
    const a = try graph.addNode(@as(NodeType, 10));
    const b = try graph.addNode(@as(NodeType, 20));
    const c = try graph.addNode(@as(NodeType, 30));

    try std.testing.expect(graph.nodeCount() == 3);
    try std.testing.expect(graph.edgeCount() == 0);

    // Check node weights
    try std.testing.expect(graph.getNodeWeight(a) == 10);
    try std.testing.expect(graph.getNodeWeight(b) == 20);
    try std.testing.expect(graph.getNodeWeight(c) == 30);

    // Modify node weight
    graph.setNodeWeight(b, @as(NodeType, 25));
    try std.testing.expect(graph.getNodeWeight(b) == 25);

    // Add edges
    try std.testing.expect(try graph.addEdge(a, b, @as(EdgeType, if (EdgeType == void) {} else 1.5)));
    try std.testing.expect(try graph.addEdge(a, c, @as(EdgeType, if (EdgeType == void) {} else 2.5)));
    try std.testing.expect(try graph.addEdge(b, c, @as(EdgeType, if (EdgeType == void) {} else 3.5)));

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
    try std.testing.expect(!try graph.addEdge(a, b, @as(EdgeType, if (EdgeType == void) {} else 1.0))); // Should return false
    try std.testing.expect(graph.edgeCount() == 3); // Edge count shouldn't change
}

/// Test neighbor iteration correctness
fn testNeighborIteration(comptime NodeType: type, comptime EdgeType: type, comptime StorageType: ?type) !void {
    const allocator = std.testing.allocator;
    var graph = Graph(NodeType, EdgeType, StorageType).init(allocator);
    defer graph.deinit();

    // Add nodes
    const a = try graph.addNode(@as(NodeType, 1));
    const b = try graph.addNode(@as(NodeType, 2));
    const c = try graph.addNode(@as(NodeType, 3));

    // Add edges
    _ = try graph.addEdge(a, b, @as(EdgeType, if (EdgeType == void) {} else 1.5));
    _ = try graph.addEdge(a, c, @as(EdgeType, if (EdgeType == void) {} else 2.0));

    // Test neighbor iteration
    var iter = graph.neighborIterator(a);
    var count: usize = 0;
    var found_b = false;
    var found_c = false;

    while (iter.next()) |item| {
        count += 1;
        if (item.neighbor == b) {
            found_b = true;
            if (EdgeType != void) {
                try std.testing.expect(item.edge == 1.5);
            }
        } else if (item.neighbor == c) {
            found_c = true;
            if (EdgeType != void) {
                try std.testing.expect(item.edge == 2.0);
            }
        }
    }

    try std.testing.expect(count == 2);
    try std.testing.expect(found_b);
    try std.testing.expect(found_c);

    // Test iteration for node with no neighbors
    var iter_empty = graph.neighborIterator(c);
    try std.testing.expect(iter_empty.next() == null);
}

/// Test BFS algorithm
fn testBFS(comptime NodeType: type, comptime EdgeType: type, comptime StorageType: ?type) !void {
    const allocator = std.testing.allocator;
    var graph = Graph(NodeType, EdgeType, StorageType).init(allocator);
    defer graph.deinit();

    // Create a simple graph: 0 -> 1, 0 -> 2, 1 -> 3
    const n0 = try graph.addNode(@as(NodeType, 0));
    const n1 = try graph.addNode(@as(NodeType, 1));
    const n2 = try graph.addNode(@as(NodeType, 2));
    const n3 = try graph.addNode(@as(NodeType, 3));

    _ = try graph.addEdge(n0, n1, @as(EdgeType, if (EdgeType == void) {} else 1));
    _ = try graph.addEdge(n0, n2, @as(EdgeType, if (EdgeType == void) {} else 2));
    _ = try graph.addEdge(n1, n3, @as(EdgeType, if (EdgeType == void) {} else 3));

    // Test BFS order
    var visited_order: std.ArrayListUnmanaged(u32) = .empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;
        var alloc: std.mem.Allocator = undefined;

        fn visit(node: u32) void {
            list.append(alloc, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    TestContext.alloc = allocator;
    try graph.bfs(allocator, n0, TestContext.visit);

    try std.testing.expect(visited_order.items.len == 4);
    try std.testing.expect(visited_order.items[0] == n0);
    // BFS should visit n1 and n2 before n3
    const n3_pos = std.mem.indexOfScalar(u32, visited_order.items, n3).?;
    const n1_pos = std.mem.indexOfScalar(u32, visited_order.items, n1).?;
    const n2_pos = std.mem.indexOfScalar(u32, visited_order.items, n2).?;
    try std.testing.expect(n1_pos < n3_pos);
    try std.testing.expect(n2_pos < n3_pos);
}

/// Test topological sort and cycle detection
fn testTopologyAndCycles(comptime NodeType: type, comptime EdgeType: type, comptime StorageType: ?type) !void {
    const allocator = std.testing.allocator;

    // Test acyclic graph
    {
        var graph = Graph(NodeType, EdgeType, StorageType).init(allocator);
        defer graph.deinit();

        // Create DAG: 0 -> 1, 0 -> 2, 1 -> 2
        const n0 = try graph.addNode(@as(NodeType, 0));
        const n1 = try graph.addNode(@as(NodeType, 1));
        const n2 = try graph.addNode(@as(NodeType, 2));

        _ = try graph.addEdge(n0, n1, @as(EdgeType, if (EdgeType == void) {} else 1));
        _ = try graph.addEdge(n0, n2, @as(EdgeType, if (EdgeType == void) {} else 2));
        _ = try graph.addEdge(n1, n2, @as(EdgeType, if (EdgeType == void) {} else 3));

        // Should have no cycles
        try std.testing.expect(!try graph.hasCycles(allocator));

        // Test topological sort
        var topo_result = try graph.topologicalSort(allocator);
        defer topo_result.deinit();

        try std.testing.expect(!topo_result.has_cycles);
        try std.testing.expect(topo_result.order.len == 3);

        // n0 should come before n1 and n2
        const n0_pos = std.mem.indexOfScalar(u32, topo_result.order, n0).?;
        const n1_pos = std.mem.indexOfScalar(u32, topo_result.order, n1).?;
        const n2_pos = std.mem.indexOfScalar(u32, topo_result.order, n2).?;
        try std.testing.expect(n0_pos < n1_pos);
        try std.testing.expect(n0_pos < n2_pos);
        try std.testing.expect(n1_pos < n2_pos);
    }

    // Test cyclic graph
    {
        var graph = Graph(NodeType, EdgeType, StorageType).init(allocator);
        defer graph.deinit();

        // Create cycle: 0 -> 1 -> 2 -> 0
        const n0 = try graph.addNode(@as(NodeType, 0));
        const n1 = try graph.addNode(@as(NodeType, 1));
        const n2 = try graph.addNode(@as(NodeType, 2));

        _ = try graph.addEdge(n0, n1, @as(EdgeType, if (EdgeType == void) {} else 1));
        _ = try graph.addEdge(n1, n2, @as(EdgeType, if (EdgeType == void) {} else 2));
        _ = try graph.addEdge(n2, n0, @as(EdgeType, if (EdgeType == void) {} else 3));

        // Should detect cycle
        try std.testing.expect(try graph.hasCycles(allocator));

        // Topological sort should detect cycles
        var topo_result = try graph.topologicalSort(allocator);
        defer topo_result.deinit();
        try std.testing.expect(topo_result.has_cycles);
    }
}

// Test cases for different type combinations
test "Backend agnostic: basic operations with f32 edges" {
    try testWithBothBackends(testBasicOperations, u32, f32);
}

test "Backend agnostic: basic operations with void edges" {
    try testWithBothBackends(testBasicOperations, u32, void);
}

test "Backend agnostic: neighbor iteration with f32 edges" {
    try testWithBothBackends(testNeighborIteration, u32, f32);
}

test "Backend agnostic: neighbor iteration with void edges" {
    try testWithBothBackends(testNeighborIteration, u32, void);
}

test "Backend agnostic: BFS with f32 edges" {
    try testWithBothBackends(testBFS, u32, f32);
}

test "Backend agnostic: BFS with void edges" {
    try testWithBothBackends(testBFS, u32, void);
}

test "Backend agnostic: topology and cycles with f32 edges" {
    try testWithBothBackends(testTopologyAndCycles, u32, f32);
}

test "Backend agnostic: topology and cycles with void edges" {
    try testWithBothBackends(testTopologyAndCycles, u32, void);
}
