const std = @import("std");

/// Topological sort result
pub fn TopologicalSortResult(comptime NodeIndex: type) type {
    return struct {
        const Self = @This();

        /// Topologically sorted node indices
        order: []NodeIndex,
        /// True if the graph has cycles (partial order returned)
        has_cycles: bool,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.order);
        }
    };
}

/// Kahn's algorithm for topological sorting
/// Returns nodes in dependency order (dependencies come before dependents)
/// If the graph has cycles, returns partial order and sets has_cycles to true
pub fn topologicalSort(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    neighbors_fn: anytype,
) !TopologicalSortResult(NodeIndex) {
    if (node_count == 0) {
        return TopologicalSortResult(NodeIndex){
            .order = try allocator.alloc(NodeIndex, 0),
            .has_cycles = false,
            .allocator = allocator,
        };
    }

    // Calculate in-degrees for all nodes
    var in_degrees = try allocator.alloc(u32, node_count);
    defer allocator.free(in_degrees);
    @memset(in_degrees, 0);

    // Count incoming edges for each node
    for (0..node_count) |node| {
        const neighbors_slice = neighbors_fn(@as(NodeIndex, @intCast(node)));
        for (neighbors_slice) |neighbor| {
            in_degrees[neighbor] += 1;
        }
    }

    // Initialize queue with nodes that have no incoming edges
    var queue = std.ArrayListUnmanaged(NodeIndex).empty;
    defer queue.deinit(allocator);

    for (0..node_count) |i| {
        if (in_degrees[i] == 0) {
            try queue.append(allocator, @intCast(i));
        }
    }

    // Process nodes in topological order
    var result = std.ArrayList(NodeIndex).init(allocator);
    defer result.deinit();

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        try result.append(current);

        // Reduce in-degree for all neighbors
        const neighbors_slice = neighbors_fn(current);
        for (neighbors_slice) |neighbor| {
            in_degrees[neighbor] -= 1;
            if (in_degrees[neighbor] == 0) {
                try queue.append(allocator, neighbor);
            }
        }
    }

    const has_cycles = result.items.len != node_count;

    return TopologicalSortResult(NodeIndex){
        .order = try result.toOwnedSlice(),
        .has_cycles = has_cycles,
        .allocator = allocator,
    };
}

/// Color enum for cycle detection DFS
const Color = enum { white, gray, black };

/// Check if the graph has any cycles using DFS
/// This is more efficient than topological sort if you only need to detect cycles
pub fn hasCycles(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    neighbors_fn: anytype,
) !bool {
    if (node_count == 0) return false;

    const colors = try allocator.alloc(Color, node_count);
    defer allocator.free(colors);
    @memset(colors, .white);

    // Check each component
    for (0..node_count) |i| {
        if (colors[i] == .white) {
            if (try dfsHasCycles(NodeIndex, @intCast(i), colors, neighbors_fn)) {
                return true;
            }
        }
    }

    return false;
}

/// Internal DFS function for cycle detection
/// Uses three-color approach: white (unvisited), gray (being processed), black (finished)
/// Back edges (to gray nodes) indicate cycles
fn dfsHasCycles(
    comptime NodeIndex: type,
    node: NodeIndex,
    colors: []Color,
    neighbors_fn: anytype,
) !bool {
    colors[node] = .gray;

    const neighbors_slice = neighbors_fn(node);
    for (neighbors_slice) |neighbor| {
        switch (colors[neighbor]) {
            .gray => return true, // Back edge found - cycle detected
            .white => {
                if (try dfsHasCycles(NodeIndex, neighbor, colors, neighbors_fn)) {
                    return true;
                }
            },
            .black => {}, // Already processed, skip
        }
    }

    colors[node] = .black;
    return false;
}

/// Iterative version of cycle detection using explicit stack
/// More suitable for SIMD optimization than recursive version
pub fn hasCyclesIterative(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    neighbors_fn: anytype,
) !bool {
    if (node_count == 0) return false;

    const colors = try allocator.alloc(Color, node_count);
    defer allocator.free(colors);
    @memset(colors, .white);

    // Stack entries track both the node and whether we're visiting or finishing it
    const StackEntry = struct {
        node: NodeIndex,
        visiting: bool, // true = visiting, false = finishing
    };

    var stack = std.ArrayList(StackEntry).init(allocator);
    defer stack.deinit();

    // Check each component
    for (0..node_count) |i| {
        const start_node = @as(NodeIndex, @intCast(i));
        if (colors[start_node] == .white) {
            try stack.append(.{ .node = start_node, .visiting = true });

            while (stack.items.len > 0) {
                const entry = stack.pop();

                if (entry.visiting) {
                    // Visiting phase
                    if (colors[entry.node] == .gray) {
                        return true; // Back edge - cycle detected
                    }
                    if (colors[entry.node] == .white) {
                        colors[entry.node] = .gray;
                        // Add finishing entry
                        try stack.append(.{ .node = entry.node, .visiting = false });

                        // Add neighbors for visiting
                        const neighbors_slice = neighbors_fn(entry.node);
                        for (neighbors_slice) |neighbor| {
                            if (colors[neighbor] != .black) {
                                try stack.append(.{ .node = neighbor, .visiting = true });
                            }
                        }
                    }
                } else {
                    // Finishing phase
                    colors[entry.node] = .black;
                }
            }
        }
    }

    return false;
}
