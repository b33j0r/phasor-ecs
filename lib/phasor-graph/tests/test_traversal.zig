const std = @import("std");
const Graph = @import("phasor-graph").Graph;

test "Graph BFS traversal" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a more complex graph structure:
    //     0
    //   /   \
    //  1     2
    //  |     |\
    //  3     4 5
    //        |
    //        6
    const a = try graph.addNode({}); // 0
    const b = try graph.addNode({}); // 1
    const c = try graph.addNode({}); // 2
    const d = try graph.addNode({}); // 3
    const e = try graph.addNode({}); // 4
    const f = try graph.addNode({}); // 5
    const g = try graph.addNode({}); // 6

    _ = try graph.addEdge(a, b, {}); // 0->1
    _ = try graph.addEdge(a, c, {}); // 0->2
    _ = try graph.addEdge(b, d, {}); // 1->3
    _ = try graph.addEdge(c, e, {}); // 2->4
    _ = try graph.addEdge(c, f, {}); // 2->5
    _ = try graph.addEdge(e, g, {}); // 4->6

    // Test BFS order - collect visited nodes in order
    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.bfs(allocator, a, TestContext.visit);

    // Verify BFS properties:
    // 1. All reachable nodes are visited
    try std.testing.expect(visited_order.items.len == 7);

    // 2. Root node is first
    try std.testing.expect(visited_order.items[0] == a);

    // 3. Level 1 nodes (b, c) come before level 2 nodes (d, e, f)
    const a_pos: usize = 0;
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;
    var d_pos: usize = undefined;
    var e_pos: usize = undefined;
    var f_pos: usize = undefined;
    var g_pos: usize = undefined;

    for (visited_order.items, 0..) |node, i| {
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
        if (node == d) d_pos = i;
        if (node == e) e_pos = i;
        if (node == f) f_pos = i;
        if (node == g) g_pos = i;
    }

    // Level 0 (a) < Level 1 (b, c) < Level 2 (d, e, f) < Level 3 (g)
    try std.testing.expect(a_pos < b_pos);
    try std.testing.expect(a_pos < c_pos);
    try std.testing.expect(b_pos < d_pos);
    try std.testing.expect(c_pos < e_pos);
    try std.testing.expect(c_pos < f_pos);
    try std.testing.expect(e_pos < g_pos);
}

test "Graph BFS traversal - disconnected graph" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create disconnected components: 0->1 and 2->3
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(c, d, {});

    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.bfs(allocator, a, TestContext.visit);

    // Should only visit connected component starting from 'a'
    try std.testing.expect(visited_order.items.len == 2);
    try std.testing.expect(visited_order.items[0] == a);
    try std.testing.expect(visited_order.items[1] == b);

    // Verify c and d are not visited
    for (visited_order.items) |node| {
        try std.testing.expect(node != c);
        try std.testing.expect(node != d);
    }
}

test "Graph BFS traversal - single node" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    const a = try graph.addNode({});

    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.bfs(allocator, a, TestContext.visit);

    try std.testing.expect(visited_order.items.len == 1);
    try std.testing.expect(visited_order.items[0] == a);
}

test "Graph DFS traversal" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a tree structure to test DFS order:
    //     0
    //   /   \
    //  1     2
    //  |   / | \
    //  3  4  5  6
    //     |
    //     7
    const a = try graph.addNode({}); // 0
    const b = try graph.addNode({}); // 1
    const c = try graph.addNode({}); // 2
    const d = try graph.addNode({}); // 3
    const e = try graph.addNode({}); // 4
    const f = try graph.addNode({}); // 5
    const g = try graph.addNode({}); // 6
    const h = try graph.addNode({}); // 7

    _ = try graph.addEdge(a, b, {}); // 0->1
    _ = try graph.addEdge(a, c, {}); // 0->2
    _ = try graph.addEdge(b, d, {}); // 1->3
    _ = try graph.addEdge(c, e, {}); // 2->4
    _ = try graph.addEdge(c, f, {}); // 2->5
    _ = try graph.addEdge(c, g, {}); // 2->6
    _ = try graph.addEdge(e, h, {}); // 4->7

    // Test DFS order - collect visited nodes in order
    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.dfs(allocator, a, TestContext.visit);

    // Verify DFS properties:
    // 1. All nodes are visited
    try std.testing.expect(visited_order.items.len == 8);

    // 2. Root node is first
    try std.testing.expect(visited_order.items[0] == a);

    // 3. For DFS, once we visit a node, all its descendants should be visited before backtracking
    // Find positions of nodes
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;
    var d_pos: usize = undefined;
    var e_pos: usize = undefined;
    var f_pos: usize = undefined;
    var g_pos: usize = undefined;
    var h_pos: usize = undefined;

    for (visited_order.items, 0..) |node, i| {
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
        if (node == d) d_pos = i;
        if (node == e) e_pos = i;
        if (node == f) f_pos = i;
        if (node == g) g_pos = i;
        if (node == h) h_pos = i;
    }

    // DFS should visit descendants before siblings
    // If b is visited before c, then d should be visited before c
    if (b_pos < c_pos) {
        try std.testing.expect(d_pos < c_pos);
    } else {
        // If c is visited before b, then e,f,g,h should be visited before b
        try std.testing.expect(e_pos < b_pos);
        try std.testing.expect(f_pos < b_pos);
        try std.testing.expect(g_pos < b_pos);
        try std.testing.expect(h_pos < b_pos);
    }

    // h should be visited immediately after e (its parent)
    try std.testing.expect(h_pos == e_pos + 1);
}

test "Graph DFS traversal - disconnected graph" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create disconnected components: 0->1->2 and 3->4
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});
    const e = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, c, {});
    _ = try graph.addEdge(d, e, {});

    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.dfs(allocator, a, TestContext.visit);

    // Should only visit connected component starting from 'a'
    try std.testing.expect(visited_order.items.len == 3);
    try std.testing.expect(visited_order.items[0] == a);

    // Verify d and e are not visited
    for (visited_order.items) |node| {
        try std.testing.expect(node != d);
        try std.testing.expect(node != e);
    }

    // Verify DFS order: a->b->c
    var b_pos: usize = undefined;
    var c_pos: usize = undefined;

    for (visited_order.items, 0..) |node, i| {
        if (node == b) b_pos = i;
        if (node == c) c_pos = i;
    }

    try std.testing.expect(b_pos == 1);
    try std.testing.expect(c_pos == 2);
}

test "Graph DFS traversal - single node" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    const a = try graph.addNode({});

    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.dfs(allocator, a, TestContext.visit);

    try std.testing.expect(visited_order.items.len == 1);
    try std.testing.expect(visited_order.items[0] == a);
}

test "Graph DFS traversal - cycle handling" {
    const allocator = std.testing.allocator;

    var graph = Graph(void, void, null).init(allocator);
    defer graph.deinit();

    // Create a graph with cycle: 0->1->2->0 and 0->3
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});
    const d = try graph.addNode({});

    _ = try graph.addEdge(a, b, {});
    _ = try graph.addEdge(b, c, {});
    _ = try graph.addEdge(c, a, {}); // Creates cycle
    _ = try graph.addEdge(a, d, {});

    var visited_order = std.ArrayListUnmanaged(u32).empty;
    defer visited_order.deinit(allocator);

    const TestContext = struct {
        var list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    TestContext.list = &visited_order;
    try graph.dfs(allocator, a, TestContext.visit);

    // Should visit all nodes exactly once despite the cycle
    try std.testing.expect(visited_order.items.len == 4);
    try std.testing.expect(visited_order.items[0] == a);

    // Verify all nodes are visited exactly once
    var node_count = [_]u8{0} ** 4;
    for (visited_order.items) |node| {
        node_count[node] += 1;
    }

    for (node_count) |count| {
        try std.testing.expect(count == 1);
    }
}
