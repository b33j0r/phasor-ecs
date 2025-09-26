const std = @import("std");

/// Breadth-first search from a start node
/// Calls visitor function for each node in BFS order
pub fn bfs(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    start: NodeIndex,
    neighbors_fn: anytype,
    visitor: anytype,
) !void {
    if (start >= node_count) return;

    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var queue = std.ArrayListUnmanaged(NodeIndex).empty;
    defer queue.deinit(allocator);

    try queue.append(allocator, start);
    visited[start] = true;

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        visitor(current);

        const neighbors_slice = neighbors_fn(current);
        for (neighbors_slice) |neighbor| {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                try queue.append(allocator, neighbor);
            }
        }
    }
}

/// Depth-first search from a start node
/// Calls visitor function for each node in DFS order
pub fn dfs(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    start: NodeIndex,
    neighbors_fn: anytype,
    visitor: anytype,
) !void {
    if (start >= node_count) return;

    const visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    try dfsRecursive(NodeIndex, start, visited, neighbors_fn, visitor);
}

/// Internal recursive DFS implementation
fn dfsRecursive(
    comptime NodeIndex: type,
    node: NodeIndex,
    visited: []bool,
    neighbors_fn: anytype,
    visitor: anytype,
) !void {
    visited[node] = true;
    visitor(node);

    const neighbors_slice = neighbors_fn(node);
    for (neighbors_slice) |neighbor| {
        if (!visited[neighbor]) {
            try dfsRecursive(NodeIndex, neighbor, visited, neighbors_fn, visitor);
        }
    }
}

/// Iterative DFS implementation using explicit stack
/// More suitable for SIMD optimization than recursive version
pub fn dfsIterative(
    comptime NodeIndex: type,
    allocator: std.mem.Allocator,
    node_count: usize,
    start: NodeIndex,
    neighbors_fn: anytype,
    visitor: anytype,
) !void {
    if (start >= node_count) return;

    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var stack = std.ArrayList(NodeIndex).init(allocator);
    defer stack.deinit();

    try stack.append(start);
    visited[start] = true;

    while (stack.items.len > 0) {
        const current = stack.pop();
        visitor(current);

        const neighbors_slice = neighbors_fn(current);
        // Process neighbors in reverse order to maintain same visitation order as recursive DFS
        var i = neighbors_slice.len;
        while (i > 0) {
            i -= 1;
            const neighbor = neighbors_slice[i];
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                try stack.append(neighbor);
            }
        }
    }
}
