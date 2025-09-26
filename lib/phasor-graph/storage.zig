const std = @import("std");
const csr = @import("csr.zig");

/// Storage interface that graph storage implementations must satisfy
pub fn StorageInterface(comptime NodeType: type, comptime EdgeType: type) type {
    _ = NodeType;
    _ = EdgeType;
    return struct {
        pub const NodeIndex = u32;
        pub const EdgeIndex = usize;

        // Required methods for any storage implementation:
        // - init(allocator) -> Self
        // - deinit(self: *Self) -> void
        // - addNode(self: *Self, weight: NodeType) -> !NodeIndex
        // - addEdge(self: *Self, source: NodeIndex, target: NodeIndex, weight: EdgeType) -> !bool
        // - containsEdge(self: *Self, source: NodeIndex, target: NodeIndex) -> bool
        // - nodeCount(self: *Self) -> usize
        // - edgeCount(self: *Self) -> usize
        // - getNodeWeight(self: *Self, node: NodeIndex) -> NodeType
        // - setNodeWeight(self: *Self, node: NodeIndex, weight: NodeType) -> void
        // - outDegree(self: *Self, node: NodeIndex) -> usize
        // - neighborIterator(self: *Self, node: NodeIndex) -> Iterator
        //     Iterator API:
        //       pub const Item = struct { neighbor: NodeIndex, edge: EdgeType }
        //       next(self: *Iterator) -> ?Item
    };
}

/// CSR-based storage implementation
/// Optimized for academic graph algorithms with high performance requirements
pub fn CsrStorage(comptime NodeType: type, comptime EdgeType: type) type {
    return struct {
        const Self = @This();
        const CsrImpl = csr.Csr(NodeType, EdgeType);

        pub const NodeIndex = u32;
        pub const EdgeIndex = usize;

        csr_graph: CsrImpl,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .csr_graph = CsrImpl.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.csr_graph.deinit();
        }

        pub fn addNode(self: *Self, weight: NodeType) !NodeIndex {
            return self.csr_graph.addNode(weight);
        }

        pub fn removeNode(self: *Self, node: NodeIndex) !void {
            return self.csr_graph.removeNode(node);
        }

        pub fn addEdge(self: *Self, source: NodeIndex, target: NodeIndex, weight: EdgeType) !bool {
            return self.csr_graph.addEdge(source, target, weight);
        }

        pub fn containsEdge(self: *Self, source: NodeIndex, target: NodeIndex) bool {
            return self.csr_graph.containsEdge(source, target);
        }

        pub fn nodeCount(self: *Self) usize {
            return self.csr_graph.nodeCount();
        }

        pub fn edgeCount(self: *Self) usize {
            return self.csr_graph.edgeCount();
        }

        pub fn getNodeWeight(self: *const Self, node: NodeIndex) NodeType {
            return self.csr_graph.getNodeWeight(node);
        }

        pub fn setNodeWeight(self: *Self, node: NodeIndex, weight: NodeType) void {
            self.csr_graph.setNodeWeight(node, weight);
        }

        // CSR-specific methods for high-performance graph operations
        /// Get neighbors of a node as a contiguous slice for optimal cache performance
        pub fn neighborsSlice(self: *Self, node: NodeIndex) []const NodeIndex {
            return self.csr_graph.neighborsSlice(node);
        }

        /// Get edge weights from a node as a contiguous slice for optimal cache performance
        pub fn edgesSlice(self: *Self, node: NodeIndex) []const EdgeType {
            return self.csr_graph.edgesSlice(node);
        }

        /// Get out-degree of a node - constant time operation in CSR
        pub fn outDegree(self: *Self, node: NodeIndex) usize {
            return self.csr_graph.outDegree(node);
        }

        /// Iterator for neighbors with edge weights
        pub const NeighborIterator = struct {
            const Iterator = @This();

            pub const Item = struct {
                neighbor: NodeIndex,
                edge: EdgeType,
            };

            csr_graph: *const CsrImpl,
            node: NodeIndex,
            current_index: usize,
            end_index: usize,

            pub fn next(iter: *Iterator) ?Item {
                if (iter.current_index >= iter.end_index) return null;

                const neighbor = iter.csr_graph.column.items[iter.current_index];
                const edge = if (@sizeOf(EdgeType) == 0)
                    iter.csr_graph.edges.get(iter.current_index)
                else
                    iter.csr_graph.edges.items[iter.current_index];

                iter.current_index += 1;

                return Item{
                    .neighbor = neighbor,
                    .edge = edge,
                };
            }
        };

        /// Create iterator for neighbors and their edge weights
        pub fn neighborIterator(self: *Self, node: NodeIndex) NeighborIterator {
            const range = self.csr_graph.neighborsRange(node);
            return NeighborIterator{
                .csr_graph = &self.csr_graph,
                .node = node,
                .current_index = range.start,
                .end_index = range.end,
            };
        }
    };
}

/// Dense adjacency matrix storage implementation
/// Suitable for dense graphs where SIMD operations can be highly effective
pub fn MatrixStorage(comptime NodeType: type, comptime EdgeType: type) type {
    return struct {
        const Self = @This();

        pub const NodeIndex = u32;
        pub const EdgeIndex = usize;

        allocator: std.mem.Allocator,
        node_weights: std.ArrayListUnmanaged(NodeType) = .empty,
        // Store adjacency matrix as optional edge weights (null = no edge)
        adjacency_matrix: std.ArrayListUnmanaged(?EdgeType) = .empty,
        node_capacity: usize,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .node_capacity = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.node_weights.deinit(self.allocator);
            self.adjacency_matrix.deinit(self.allocator);
        }

        pub fn addNode(self: *Self, weight: NodeType) !NodeIndex {
            const new_node = @as(NodeIndex, @intCast(self.node_weights.items.len));

            // Add node weight
            try self.node_weights.append(self.allocator, weight);

            // Expand adjacency matrix
            const new_capacity = self.node_weights.items.len;
            if (new_capacity > self.node_capacity) {
                const old_capacity = self.node_capacity;
                self.node_capacity = new_capacity;

                // Resize matrix to accommodate new node
                try self.adjacency_matrix.resize(self.allocator, new_capacity * new_capacity);

                // Initialize new entries to null
                for (old_capacity * old_capacity..new_capacity * new_capacity) |i| {
                    self.adjacency_matrix.items[i] = null;
                }

                // Move existing data if needed (matrix expansion)
                if (old_capacity > 0) {
                    var row = old_capacity;
                    while (row > 0) {
                        row -= 1;
                        const old_start = row * old_capacity;
                        const new_start = row * new_capacity;

                        // Move row data
                        var col = old_capacity;
                        while (col > 0) {
                            col -= 1;
                            self.adjacency_matrix.items[new_start + col] =
                                self.adjacency_matrix.items[old_start + col];
                        }

                        // Clear old positions
                        for (old_start..old_start + old_capacity) |i| {
                            if (i >= new_start) break;
                            self.adjacency_matrix.items[i] = null;
                        }
                    }
                }
            }

            return new_node;
        }

        pub fn addEdge(self: *Self, source: NodeIndex, target: NodeIndex, weight: EdgeType) !bool {
            if (source >= self.nodeCount() or target >= self.nodeCount()) return false;

            const index = source * self.node_capacity + target;
            if (self.adjacency_matrix.items[index] != null) {
                return false; // Edge already exists
            }

            self.adjacency_matrix.items[index] = weight;
            return true;
        }

        pub fn containsEdge(self: *Self, source: NodeIndex, target: NodeIndex) bool {
            if (source >= self.nodeCount() or target >= self.nodeCount()) return false;

            const index = source * self.node_capacity + target;
            return self.adjacency_matrix.items[index] != null;
        }

        pub fn nodeCount(self: *Self) usize {
            return self.node_weights.items.len;
        }

        pub fn edgeCount(self: *Self) usize {
            var count: usize = 0;
            for (self.adjacency_matrix.items) |edge| {
                if (edge != null) count += 1;
            }
            return count;
        }

        pub fn getNodeWeight(self: *const Self, node: NodeIndex) NodeType {
            return self.node_weights.items[node];
        }

        pub fn setNodeWeight(self: *Self, node: NodeIndex, weight: NodeType) void {
            self.node_weights.items[node] = weight;
        }

        /// Get neighbors of a node - requires building slice from matrix row
        pub fn neighborsSlice(self: *Self, node: NodeIndex, temp_allocator: std.mem.Allocator) ![]NodeIndex {
            var neighbors = std.ArrayList(NodeIndex).init(temp_allocator);

            const row_start = node * self.node_capacity;
            const row_end = row_start + self.nodeCount();

            for (row_start..row_end) |i| {
                if (self.adjacency_matrix.items[i] != null) {
                    try neighbors.append(@intCast(i - row_start));
                }
            }

            return try neighbors.toOwnedSlice();
        }

        /// Get edge weights from a node - requires building slice from matrix row
        pub fn edgesSlice(self: *Self, node: NodeIndex, temp_allocator: std.mem.Allocator) ![]EdgeType {
            var edges = std.ArrayList(EdgeType).init(temp_allocator);

            const row_start = node * self.node_capacity;
            const row_end = row_start + self.nodeCount();

            for (row_start..row_end) |i| {
                if (self.adjacency_matrix.items[i]) |weight| {
                    try edges.append(weight);
                }
            }

            return try edges.toOwnedSlice();
        }

        /// Get out-degree of a node
        pub fn outDegree(self: *Self, node: NodeIndex) usize {
            var degree: usize = 0;

            const row_start = node * self.node_capacity;
            const row_end = row_start + self.nodeCount();

            for (row_start..row_end) |i| {
                if (self.adjacency_matrix.items[i] != null) degree += 1;
            }

            return degree;
        }

        /// Iterator for neighbors with edge weights - lazy row scanning
        pub const NeighborIterator = struct {
            const Iterator = @This();

            pub const Item = struct {
                neighbor: NodeIndex,
                edge: EdgeType,
            };

            matrix_storage: *const Self,
            node: NodeIndex,
            current_col: NodeIndex,
            node_count: NodeIndex,

            pub fn next(iter: *Iterator) ?Item {
                const row_start = iter.node * iter.matrix_storage.node_capacity;

                // Scan row for next non-null edge
                while (iter.current_col < iter.node_count) {
                    const matrix_index = row_start + iter.current_col;
                    const current_col = iter.current_col;
                    iter.current_col += 1;

                    if (iter.matrix_storage.adjacency_matrix.items[matrix_index]) |edge_weight| {
                        return Item{
                            .neighbor = current_col,
                            .edge = edge_weight,
                        };
                    }
                }

                return null;
            }
        };

        /// Create iterator for neighbors and their edge weights - no allocations required
        pub fn neighborIterator(self: *Self, node: NodeIndex) NeighborIterator {
            return NeighborIterator{
                .matrix_storage = self,
                .node = node,
                .current_col = 0,
                .node_count = @intCast(self.nodeCount()),
            };
        }
    };
}
