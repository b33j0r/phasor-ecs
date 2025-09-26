const std = @import("std");

/// Priority queue item for Dijkstra's algorithm
pub fn QueueItem(comptime EdgeType: type) type {
    return struct {
        node: u32,
        distance: EdgeType,
    };
}

/// Compare function for priority queue (min-heap)
pub fn compareQueueItems(comptime EdgeType: type) fn (void, QueueItem(EdgeType), QueueItem(EdgeType)) std.math.Order {
    return struct {
        fn compare(context: void, a: QueueItem(EdgeType), b: QueueItem(EdgeType)) std.math.Order {
            _ = context;
            return compareWeights(EdgeType, a.distance, b.distance);
        }
    }.compare;
}

/// Result type for Dijkstra's algorithm
pub fn DijkstraResult(comptime EdgeType: type) type {
    return struct {
        const Self = @This();

        distances: []?EdgeType,
        predecessors: []?u32,
        start: u32,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.distances);
            self.allocator.free(self.predecessors);
        }

        /// Get shortest distance to a node
        pub fn distanceTo(self: *const Self, node: u32) ?EdgeType {
            if (node >= self.distances.len) return null;
            return self.distances[node];
        }

        /// Get shortest path to a node
        pub fn pathTo(self: *const Self, allocator: std.mem.Allocator, target: u32) !?[]u32 {
            if (target >= self.distances.len or self.distances[target] == null) return null;

            var path = std.ArrayListUnmanaged(u32).empty;
            defer path.deinit(self.allocator);

            var current = target;
            try path.append(allocator, current);

            while (self.predecessors[current]) |pred| {
                try path.append(allocator, pred);
                current = pred;
                if (current == self.start) break;
            }

            // Reverse to get path from start to target
            std.mem.reverse(u32, path.items);
            return try path.toOwnedSlice(self.allocator);
        }

        /// Check if a node is reachable from start
        pub fn isReachable(self: *const Self, node: u32) bool {
            if (node >= self.distances.len) return false;
            return self.distances[node] != null;
        }
    };
}

/// Get zero value for numeric types
pub fn getZeroValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int, .float => 0,
        .@"struct" => |struct_info| {
            if (@hasDecl(T, "zero")) {
                return T.zero;
            } else if (@hasField(T, "cost") and struct_info.fields.len == 1) {
                return T{ .cost = 0 };
            } else {
                @compileError("Cannot determine zero value for type " ++ @typeName(T) ++ ". Please implement a 'zero' declaration.");
            }
        },
        else => @compileError("Cannot determine zero value for type " ++ @typeName(T)),
    };
}

/// Add two weight values
pub fn addWeights(comptime T: type, a: T, b: T) T {
    return switch (@typeInfo(T)) {
        .int, .float => a + b,
        .@"struct" => {
            if (@hasDecl(T, "add")) {
                return T.add(a, b);
            } else if (@hasField(T, "cost")) {
                return T{ .cost = a.cost + b.cost };
            } else {
                @compileError("Cannot add weights of type " ++ @typeName(T) ++ ". Please implement an 'add' method.");
            }
        },
        else => @compileError("Cannot add weights of type " ++ @typeName(T)),
    };
}

/// Compare two weight values
pub fn compareWeights(comptime T: type, a: T, b: T) std.math.Order {
    return switch (@typeInfo(T)) {
        .int, .float => std.math.order(a, b),
        .@"struct" => {
            if (@hasDecl(T, "compare")) {
                return T.compare(a, b);
            } else if (@hasField(T, "cost")) {
                return std.math.order(a.cost, b.cost);
            } else {
                @compileError("Cannot compare weights of type " ++ @typeName(T) ++ ". Please implement a 'compare' method.");
            }
        },
        else => @compileError("Cannot compare weights of type " ++ @typeName(T)),
    };
}

/// Dijkstra's shortest path algorithm implementation
/// Returns distances from start node to all reachable nodes
/// Edge weights must be numeric and support addition and comparison
/// TODO: SIMD optimization for distance updates in dense graphs
pub fn dijkstra(comptime NodeIndex: type, comptime EdgeType: type, allocator: std.mem.Allocator, node_count: usize, start: NodeIndex, neighbor_iterator_fn: anytype) !?DijkstraResult(EdgeType) {
    const QueueItemType = QueueItem(EdgeType);
    const PriorityQueue = std.PriorityQueue(QueueItemType, void, compareQueueItems(EdgeType));

    if (start >= node_count) return null;

    var distances = try allocator.alloc(?EdgeType, node_count);
    defer allocator.free(distances);
    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    var predecessors = try allocator.alloc(?NodeIndex, node_count);
    defer allocator.free(predecessors);

    // Initialize
    @memset(distances, null);
    @memset(visited, false);
    @memset(predecessors, null);
    distances[start] = getZeroValue(EdgeType);

    var queue = PriorityQueue.init(allocator, {});
    defer queue.deinit();

    try queue.add(QueueItemType{ .node = start, .distance = getZeroValue(EdgeType) });

    while (queue.count() > 0) {
        const current = queue.remove();
        if (visited[current.node]) continue;
        visited[current.node] = true;

        var iter = neighbor_iterator_fn(current.node);
        while (iter.next()) |neighbor_info| {
            const neighbor = neighbor_info.neighbor;
            const edge_weight = neighbor_info.edge;

            if (visited[neighbor]) continue;

            const new_distance = addWeights(EdgeType, distances[current.node].?, edge_weight);

            if (distances[neighbor] == null or compareWeights(EdgeType, new_distance, distances[neighbor].?) == .lt) {
                distances[neighbor] = new_distance;
                predecessors[neighbor] = current.node;
                try queue.add(QueueItemType{ .node = neighbor, .distance = new_distance });
            }
        }
    }

    // Copy results to owned arrays
    const result_distances = try allocator.alloc(?EdgeType, node_count);
    const result_predecessors = try allocator.alloc(?NodeIndex, node_count);
    @memcpy(result_distances, distances);
    @memcpy(result_predecessors, predecessors);

    return DijkstraResult(EdgeType){
        .distances = result_distances,
        .predecessors = result_predecessors,
        .start = start,
        .allocator = allocator,
    };
}
