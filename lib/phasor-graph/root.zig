const std = @import("std");
pub const csr = @import("csr.zig");
pub const dijkstra = @import("dijkstra.zig");
pub const traversal = @import("traversal.zig");
pub const topology = @import("topology.zig");
pub const storage = @import("storage.zig");

// Re-export Dijkstra types and functions for public API compatibility
pub const DijkstraResult = dijkstra.DijkstraResult;

// Re-export storage types for public API
pub const StorageInterface = storage.StorageInterface;
pub const CsrStorage = storage.CsrStorage;
pub const MatrixStorage = storage.MatrixStorage;
pub const Graph = @import("graph.zig").Graph;
