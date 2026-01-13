//! Compressed Sparse Row (CSR) sparse graph representation in Zig.
//! This was inspired by the implementation in petgraph.

const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// Compressed Sparse Row (CSR) sparse graph representation
///
/// A CSR graph uses O(|V| + |E|) space where V is nodes and E is edges.
/// Provides fast iteration of outgoing edges from any node.
/// Self loops are allowed, no parallel edges.
pub fn Csr(comptime NodeWeight: type, comptime EdgeWeight: type) type {
    return struct {
        const Self = @This();

        /// Column indices (target nodes for each edge)
        column: ArrayListUnmanaged(u32),

        /// Edge weights, parallel to column
        edges: OptionalArray(EdgeWeight),

        /// Row pointers - indices where each node's edges start
        /// Always node_count + 1 elements, last element equals column.len
        row: ArrayListUnmanaged(usize),

        /// Node weights
        node_weights: OptionalArray(NodeWeight),

        /// Total number of edges (for undirected graphs)
        edge_count: usize,

        /// Memory allocator
        allocator: Allocator,

        pub const NodeIndex = u32;
        pub const EdgeIndex = usize;

        /// Error type for CSR operations
        pub const CsrError = error{
            IndicesOutOfBounds,
            EdgesNotSorted,
            OutOfMemory,
        };

        /// Create a new empty CSR graph
        pub fn init(allocator: Allocator) Self {
            var self = Self{
                .column = .empty,
                .edges = initOptionalArray(EdgeWeight),
                .row = .empty,
                .node_weights = initOptionalArray(NodeWeight),
                .edge_count = 0,
                .allocator = allocator,
            };
            // Initialize with single zero for empty graph
            self.row.append(self.allocator, 0) catch unreachable;
            return self;
        }

        /// Create CSR with n nodes, using default node weights
        pub fn withNodes(allocator: Allocator, n: usize) !Self {
            var self = Self{
                .column = .empty,
                .edges = initOptionalArray(EdgeWeight),
                .row = .empty,
                .node_weights = initOptionalArray(NodeWeight),
                .edge_count = 0,
                .allocator = allocator,
            };

            // Initialize row pointers (all pointing to 0 initially)
            try self.row.resize(self.allocator, n + 1);
            @memset(self.row.items, 0);

            // Initialize node weights with default values
            try self.node_weights.ensureTotalCapacity(self.allocator, n);
            const default_weight = if (@sizeOf(NodeWeight) == 0) {} else std.mem.zeroes(NodeWeight);
            try self.node_weights.appendNTimes(self.allocator, default_weight, n);

            return self;
        }

        /// Create CSR from sorted edges
        /// Edges must be sorted by (source, target) and unique
        pub fn fromSortedEdges(allocator: Allocator, edges: []const struct { u32, u32, EdgeWeight }) !Self {
            if (edges.len == 0) return Self.withNodes(allocator, 0);

            // Find maximum node index
            var max_node: u32 = 0;
            for (edges) |edge| {
                max_node = @max(max_node, @max(edge[0], edge[1]));
            }

            var self = try Self.withNodes(allocator, max_node + 1);

            var edge_idx: usize = 0;
            var last_target: ?u32 = null;

            for (0..self.nodeCount()) |node| {
                self.row.items[node] = self.column.items.len;
                last_target = null;

                // Process all edges from this node
                while (edge_idx < edges.len and edges[edge_idx][0] == node) {
                    const edge = edges[edge_idx];
                    const source = edge[0];
                    const target = edge[1];
                    const weight = edge[2];

                    // Verify sorting
                    if (node > source) return CsrError.EdgesNotSorted;
                    if (last_target != null and target <= last_target.?) {
                        return CsrError.EdgesNotSorted;
                    }

                    try self.column.append(self.allocator, target);
                    try self.edges.append(self.allocator, weight);
                    last_target = target;
                    edge_idx += 1;
                }
            }

            // Set final row pointer
            self.row.items[self.nodeCount()] = self.column.items.len;
            self.edge_count = edges.len;

            return self;
        }

        /// Clean up allocated memory
        pub fn deinit(self: *Self) void {
            self.column.deinit(self.allocator);
            self.edges.deinit(self.allocator);
            self.row.deinit(self.allocator);
            self.node_weights.deinit(self.allocator);
        }

        /// Get number of nodes
        pub fn nodeCount(self: *const Self) usize {
            return self.row.items.len - 1;
        }

        /// Get number of edges
        pub fn edgeCount(self: *const Self) usize {
            return self.column.items.len;
        }

        /// Add a new node with given weight
        pub fn addNode(self: *Self, weight: NodeWeight) !NodeIndex {
            const node_idx = self.nodeCount();

            // Insert new row pointer before the last one
            try self.row.insert(self.allocator, node_idx, self.column.items.len);
            try self.node_weights.insert(self.allocator, node_idx, weight);

            return @intCast(node_idx);
        }

        /// Remove a node by index. Also removes any edges incident to the node and
        /// reindexes all nodes with index greater than the removed one by -1.
        pub fn removeNode(self: *Self, node: NodeIndex) !void {
            const n = self.nodeCount();
            if (node >= n) return CsrError.IndicesOutOfBounds;

            // Build new CSR arrays excluding the removed node and incident edges
            var new_column: ArrayListUnmanaged(u32) = .empty;
            var new_edges: OptionalArray(EdgeWeight) = initOptionalArray(EdgeWeight);
            var new_row: ArrayListUnmanaged(usize) = .empty;
            var new_node_weights: OptionalArray(NodeWeight) = initOptionalArray(NodeWeight);

            // Reserve reasonable capacities
            try new_row.ensureTotalCapacity(self.allocator, n);
            // new_row will end with +1 appended later
            if (@sizeOf(NodeWeight) != 0) {
                try new_node_weights.ensureTotalCapacity(self.allocator, n - 1);
            }
            if (@sizeOf(EdgeWeight) != 0) {
                // worst case all edges remain except those touching the node
                try new_column.ensureTotalCapacity(self.allocator, self.column.items.len);
                try new_edges.ensureTotalCapacity(self.allocator, self.edges.items.len);
            }

            var next_row_start: usize = 0;
            for (0..n) |old_node| {
                if (old_node == node) continue; // skip removed node

                // append start pointer for this node
                try new_row.append(self.allocator, next_row_start);

                const r = self.neighborsRange(@intCast(old_node));
                // copy edges, skipping those pointing to removed node
                for (r.start..r.end) |eidx| {
                    const tgt = self.column.items[eidx];
                    if (tgt == node) continue; // drop incoming to removed

                    const new_tgt: u32 = if (tgt > node) tgt - 1 else tgt;
                    try new_column.append(self.allocator, new_tgt);
                    try new_edges.append(self.allocator, if (@sizeOf(EdgeWeight) == 0) {} else self.edges.items[eidx]);
                    next_row_start += 1;
                }

                // append node weight for this node
                if (@sizeOf(NodeWeight) == 0) {
                    try new_node_weights.append(self.allocator, {});
                } else {
                    try new_node_weights.append(self.allocator, self.node_weights.items[old_node]);
                }
            }
            // final row pointer
            try new_row.append(self.allocator, next_row_start);

            // Swap in new arrays and deinit old ones
            var old_column = self.column;
            var old_edges = self.edges;
            var old_row = self.row;
            var old_node_weights = self.node_weights;

            self.column = new_column;
            self.edges = new_edges;
            self.row = new_row;
            self.node_weights = new_node_weights;
            self.edge_count = next_row_start;

            // Now free old buffers
            old_column.deinit(self.allocator);
            old_edges.deinit(self.allocator);
            old_row.deinit(self.allocator);
            old_node_weights.deinit(self.allocator);
        }

        /// Add an edge from source to target with given weight
        /// Returns true if edge was added, false if it already exists
        pub fn addEdge(self: *Self, source: NodeIndex, target: NodeIndex, weight: EdgeWeight) !bool {
            if (source >= self.nodeCount() or target >= self.nodeCount()) {
                return CsrError.IndicesOutOfBounds;
            }

            // Find insertion position
            const pos = self.findEdgePos(source, target) catch |err| switch (err) {
                error.EdgeExists => return false,
                // else => return err,
            };

            // Insert edge
            try self.column.insert(self.allocator, pos, target);
            try self.edges.insert(self.allocator, pos, weight);

            // Update row pointers for all nodes after source
            for (source + 1..self.row.items.len) |i| {
                self.row.items[i] += 1;
            }

            self.edge_count += 1;
            return true;
        }

        /// Check if edge exists between source and target
        pub fn containsEdge(self: *const Self, source: NodeIndex, target: NodeIndex) bool {
            _ = self.findEdgePos(source, target) catch |err| switch (err) {
                error.EdgeExists => return true,
            };
            return false;
        }

        /// Get out-degree of a node
        pub fn outDegree(self: *const Self, node: NodeIndex) usize {
            const range = self.neighborsRange(node);
            return range.end - range.start;
        }

        /// Get slice of neighbor node indices
        pub fn neighborsSlice(self: *const Self, node: NodeIndex) []const NodeIndex {
            const range = self.neighborsRange(node);
            return self.column.items[range.start..range.end];
        }

        /// Get slice of edge weights for a node
        pub fn edgesSlice(self: *const Self, node: NodeIndex) []const EdgeWeight {
            const range = self.neighborsRange(node);
            if (@sizeOf(EdgeWeight) == 0) {
                return self.edges.slice(range.start, range.end);
            } else {
                return self.edges.items[range.start..range.end];
            }
        }

        /// Get node weight by index
        pub fn getNodeWeight(self: *const Self, node: NodeIndex) NodeWeight {
            if (@sizeOf(NodeWeight) == 0) {
                return self.node_weights.get(node);
            } else {
                return self.node_weights.items[node];
            }
        }

        /// Set node weight by index
        pub fn setNodeWeight(self: *Self, node: NodeIndex, weight: NodeWeight) void {
            if (@sizeOf(NodeWeight) == 0) {
                self.node_weights.set(node, weight);
            } else {
                self.node_weights.items[node] = weight;
            }
        }

        /// Clear all edges while keeping nodes
        pub fn clearEdges(self: *Self) void {
            self.column.clearRetainingCapacity();
            self.edges.clearRetainingCapacity();
            for (self.row.items) |*r| {
                r.* = 0;
            }
            self.edge_count = 0;
        }

        // Private helper methods

        pub fn neighborsRange(self: *const Self, node: NodeIndex) struct { start: usize, end: usize } {
            const start = self.row.items[node];
            const end = self.row.items[node + 1];
            return .{ .start = start, .end = end };
        }

        fn findEdgePos(self: *const Self, source: NodeIndex, target: NodeIndex) !usize {
            const range = self.neighborsRange(source);
            const neighbors = self.column.items[range.start..range.end];

            // Linear search for small arrays, binary search for larger ones
            if (neighbors.len < 32) {
                for (neighbors, 0..) |neighbor, i| {
                    if (neighbor == target) return error.EdgeExists;
                    if (neighbor > target) return range.start + i;
                }
                return range.start + neighbors.len;
            } else {
                // Binary search
                var left: usize = 0;
                var right: usize = neighbors.len;

                while (left < right) {
                    const mid = left + (right - left) / 2;
                    if (neighbors[mid] == target) return error.EdgeExists;
                    if (neighbors[mid] < target) {
                        left = mid + 1;
                    } else {
                        right = mid;
                    }
                }
                return range.start + left;
            }
        }
    };
}

/// Helper function to initialize OptionalArray based on type size
inline fn initOptionalArray(comptime T: type) OptionalArray(T) {
    return if (@sizeOf(T) == 0) OptionalArray(T).init() else .empty;
}

/// Helper container that handles zero-sized types like `void` and `struct {}`.
fn OptionalArray(comptime T: type) type {
    if (@sizeOf(T) == 0) {
        return struct {
            len: usize = 0,

            const Empty = @This();
            const empty_slice = [_]T{};

            pub const items = &empty_slice;

            pub fn init() Empty {
                return .{};
            }

            pub fn deinit(self: *Empty, allocator: Allocator) void {
                _ = self;
                _ = allocator;
            }

            pub fn append(self: *Empty, allocator: Allocator, item: T) !void {
                _ = allocator;
                _ = item;
                self.len += 1;
            }

            pub fn insert(self: *Empty, allocator: Allocator, index: usize, item: T) !void {
                _ = allocator;
                _ = index;
                _ = item;
                self.len += 1;
            }

            pub fn clearRetainingCapacity(self: *Empty) void {
                self.len = 0;
            }

            pub fn ensureTotalCapacity(self: *Empty, allocator: Allocator, capacity: usize) !void {
                _ = self;
                _ = allocator;
                _ = capacity;
            }

            pub fn get(self: *const Empty, index: usize) T {
                _ = self;
                _ = index;
                return {};
            }

            pub fn set(self: *Empty, index: usize, item: T) void {
                _ = self;
                _ = index;
                _ = item;
            }

            pub fn slice(self: *const Empty, start: usize, end: usize) []const T {
                _ = self;
                _ = start;
                _ = end;
                return &empty_slice;
            }
        };
    } else {
        return ArrayListUnmanaged(T);
    }
}

// Tests
test "CSR basic operations" {
    const allocator = testing.allocator;

    var graph = Csr(void, void).init(allocator);
    defer graph.deinit();

    // Add nodes
    const a = try graph.addNode({});
    const b = try graph.addNode({});
    const c = try graph.addNode({});

    try testing.expect(graph.nodeCount() == 3);
    try testing.expect(graph.edgeCount() == 0);

    // Add edges
    try testing.expect(try graph.addEdge(a, b, {}));
    try testing.expect(try graph.addEdge(b, c, {}));
    try testing.expect(try graph.addEdge(c, a, {}));

    try testing.expect(graph.edgeCount() == 3);

    // Test neighbors
    try testing.expectEqualSlices(u32, &[_]u32{b}, graph.neighborsSlice(a));
    try testing.expectEqualSlices(u32, &[_]u32{c}, graph.neighborsSlice(b));
    try testing.expectEqualSlices(u32, &[_]u32{a}, graph.neighborsSlice(c));

    // Test duplicate edge
    try testing.expect(!try graph.addEdge(a, b, {}));
}

test "CSR with nodes" {
    const allocator = testing.allocator;

    var graph = try Csr(u32, void).withNodes(allocator, 3);
    defer graph.deinit();

    try testing.expect(graph.nodeCount() == 3);
    try testing.expect(graph.edgeCount() == 0);

    // Test node weights (should be zero-initialized)
    try testing.expect(graph.getNodeWeight(0) == 0);
    try testing.expect(graph.getNodeWeight(2) == 0);

    // Set node weights
    graph.setNodeWeight(1, 42);
    try testing.expect(graph.getNodeWeight(1) == 42);
}

test "CSR from sorted edges" {
    const allocator = testing.allocator;

    const edges = [_]struct { u32, u32, f32 }{
        .{ 0, 1, 0.5 },
        .{ 0, 2, 2.0 },
        .{ 1, 0, 1.0 },
        .{ 1, 1, 1.0 },
        .{ 1, 2, 1.0 },
        .{ 1, 3, 1.0 },
        .{ 2, 3, 3.0 },
    };

    var graph = try Csr(void, f32).fromSortedEdges(allocator, &edges);
    defer graph.deinit();

    try testing.expect(graph.nodeCount() == 4);
    try testing.expect(graph.edgeCount() == 7);

    // Test specific neighbors
    try testing.expectEqualSlices(u32, &[_]u32{ 1, 2 }, graph.neighborsSlice(0));
    try testing.expectEqualSlices(u32, &[_]u32{ 0, 1, 2, 3 }, graph.neighborsSlice(1));
    try testing.expectEqualSlices(u32, &[_]u32{3}, graph.neighborsSlice(2));

    // Test edge weights
    const edges_from_1 = graph.edgesSlice(1);
    try testing.expect(edges_from_1.len == 4);
    try testing.expect(edges_from_1[0] == 1.0); // to node 0
    try testing.expect(edges_from_1[1] == 1.0); // to node 1 (self-loop)
}

test "CSR clear edges" {
    const allocator = testing.allocator;

    var graph = try Csr(void, void).withNodes(allocator, 3);
    defer graph.deinit();

    _ = try graph.addEdge(0, 1, {});
    _ = try graph.addEdge(1, 2, {});

    try testing.expect(graph.edgeCount() == 2);

    graph.clearEdges();

    try testing.expect(graph.edgeCount() == 0);
    try testing.expect(graph.nodeCount() == 3); // Nodes should remain
}
