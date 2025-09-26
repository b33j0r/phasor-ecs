const std = @import("std");
const graph = @import("phasor-graph");
const print = std.debug.print;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const N = struct {
        id: usize,
        name: []const u8,
    };

    const E = struct {
        terrain: union(enum) {
            grass,
            water,
            mountain,
        },

        const Self = @This();

        pub fn cost(self: Self) u32 {
            return switch (self.terrain) {
                .grass => 1,
                .water => 2,
                .mountain => 3,
            };
        }

        // Required for Dijkstra's algorithm
        pub const zero = Self{ .terrain = .grass };

        pub fn add(a: Self, b: Self) Self {
            // Combine terrains - mountain is hardest, so it dominates
            const combined_terrain = switch (a.terrain) {
                .mountain => .mountain,
                .water => switch (b.terrain) {
                    .mountain => .mountain,
                    else => .water,
                },
                .grass => b.terrain,
            };
            return Self{ .terrain = combined_terrain };
        }

        pub fn compare(a: Self, b: Self) std.math.Order {
            return std.math.order(a.cost(), b.cost());
        }
    };

    var g = graph.Graph(N, E, null).init(allocator);
    defer g.deinit();

    print("=== Phasor Graph Demo ===\n", .{});

    // Add nodes representing different locations
    const village = try g.addNode(N{ .id = 0, .name = "Village" });
    const forest = try g.addNode(N{ .id = 1, .name = "Forest" });
    const lake = try g.addNode(N{ .id = 2, .name = "Lake" });
    const mountain = try g.addNode(N{ .id = 3, .name = "Mountain" });
    const castle = try g.addNode(N{ .id = 4, .name = "Castle" });

    print("Added {} nodes\n", .{g.nodeCount()});

    // Add edges with different terrain types
    _ = try g.addEdge(village, forest, E{ .terrain = .grass });
    _ = try g.addEdge(village, lake, E{ .terrain = .water });
    _ = try g.addEdge(forest, mountain, E{ .terrain = .mountain });
    _ = try g.addEdge(forest, castle, E{ .terrain = .grass });
    _ = try g.addEdge(lake, castle, E{ .terrain = .water });
    _ = try g.addEdge(mountain, castle, E{ .terrain = .mountain });

    print("Added {} edges\n", .{g.edgeCount()});

    // Demonstrate neighbor access
    print("\n=== Neighbors of Village ===\n", .{});
    const neighbors = g.neighbors(village);
    for (neighbors) |neighbor| {
        const node_info = g.getNodeWeight(neighbor);
        print("Connected to: {} ({s})\n", .{ neighbor, node_info.name });
    }

    // Demonstrate neighbor iterator with edge weights
    print("\n=== Village connections with terrain ===\n", .{});
    var iter = g.neighborIterator(village);
    while (iter.next()) |connection| {
        const node_info = g.getNodeWeight(connection.neighbor);
        const terrain = switch (connection.edge.terrain) {
            .grass => "grass",
            .water => "water",
            .mountain => "mountain",
        };
        print("To {s} via {s} (cost: {})\n", .{ node_info.name, terrain, connection.edge.cost() });
    }

    // Demonstrate BFS
    print("\n=== BFS from Village ===\n", .{});
    const BfsVisitor = struct {
        fn visit(node: u32) void {
            // Simple visitor that just prints node index
            print("BFS visited node: {}\n", .{node});
        }
    };

    try g.bfs(allocator, village, BfsVisitor.visit);

    // Demonstrate DFS
    print("\n=== DFS from Village ===\n", .{});
    const DfsVisitor = struct {
        fn visit(node: u32) void {
            // Simple visitor that just prints node index
            print("DFS visited node: {}\n", .{node});
        }
    };

    try g.dfs(allocator, village, DfsVisitor.visit);

    print("\n=== Graph Analysis ===\n", .{});
    print("Total nodes: {}\n", .{g.nodeCount()});
    print("Total edges: {}\n", .{g.edgeCount()});
    print("Village out-degree: {}\n", .{g.outDegree(village)});
    print("Forest out-degree: {}\n", .{g.outDegree(forest)});
}
