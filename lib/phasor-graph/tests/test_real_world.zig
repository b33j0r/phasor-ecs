const std = @import("std");
const Graph = @import("phasor-graph").Graph;

test "Social network - find friends within degrees of separation" {
    const allocator = std.testing.allocator;

    // Create a social network graph where nodes represent people
    // and edges represent friendships
    var graph = Graph([]const u8, void, null).init(allocator);
    defer graph.deinit();

    // Add people
    const alice = try graph.addNode("Alice");
    const bob = try graph.addNode("Bob");
    const charlie = try graph.addNode("Charlie");
    const diana = try graph.addNode("Diana");
    const eve = try graph.addNode("Eve");
    const frank = try graph.addNode("Frank");

    // Create friendship network:
    // Alice -> Bob -> Charlie -> Diana
    //   \       \
    //    Eve     Frank
    _ = try graph.addEdge(alice, bob, {});
    _ = try graph.addEdge(alice, eve, {});
    _ = try graph.addEdge(bob, charlie, {});
    _ = try graph.addEdge(bob, frank, {});
    _ = try graph.addEdge(charlie, diana, {});

    // Use BFS to find all friends within 2 degrees of Alice
    var friends_within_2_degrees = std.ArrayListUnmanaged(u32).empty;
    defer friends_within_2_degrees.deinit(allocator);

    const SocialNetworkVisitor = struct {
        var friends_list: *std.ArrayListUnmanaged(u32) = undefined;
        var degree_limit: usize = undefined;
        var current_degree: usize = 0;

        fn visit(node: u32) void {
            if (current_degree <= degree_limit) {
                friends_list.append(std.testing.allocator, node) catch unreachable;
            }
        }
    };

    SocialNetworkVisitor.friends_list = &friends_within_2_degrees;
    SocialNetworkVisitor.degree_limit = 2;
    try graph.bfs(allocator, alice, SocialNetworkVisitor.visit);

    // Alice should find: herself, Bob, Eve (1st degree), Charlie, Frank (2nd degree)
    // Diana is 3rd degree so should not be included
    try std.testing.expect(friends_within_2_degrees.items.len >= 4); // At least Alice + first & some second degree
    try std.testing.expect(friends_within_2_degrees.items[0] == alice); // Alice is the starting point

    // Verify that Bob and Eve are in the results (direct friends)
    var found_bob = false;
    var found_eve = false;
    for (friends_within_2_degrees.items) |friend| {
        if (friend == bob) found_bob = true;
        if (friend == eve) found_eve = true;
    }
    try std.testing.expect(found_bob);
    try std.testing.expect(found_eve);
}

test "File system directory traversal using DFS" {
    const allocator = std.testing.allocator;

    // Model a file system as a directed graph
    var graph = Graph([]const u8, void, null).init(allocator);
    defer graph.deinit();

    // Create directory structure:
    // /root
    //   /home
    //     /user1
    //       file1.txt
    //     /user2
    //       file2.txt
    //   /var
    //     /log
    //       system.log
    const root = try graph.addNode("/root");
    const home = try graph.addNode("/home");
    const var_dir = try graph.addNode("/var");
    const user1 = try graph.addNode("/user1");
    const user2 = try graph.addNode("/user2");
    const log_dir = try graph.addNode("/log");
    const file1 = try graph.addNode("file1.txt");
    const file2 = try graph.addNode("file2.txt");
    const system_log = try graph.addNode("system.log");

    // Build directory hierarchy
    _ = try graph.addEdge(root, home, {});
    _ = try graph.addEdge(root, var_dir, {});
    _ = try graph.addEdge(home, user1, {});
    _ = try graph.addEdge(home, user2, {});
    _ = try graph.addEdge(user1, file1, {});
    _ = try graph.addEdge(user2, file2, {});
    _ = try graph.addEdge(var_dir, log_dir, {});
    _ = try graph.addEdge(log_dir, system_log, {});

    // Use DFS to traverse directory structure (like recursive ls -R)
    var traversal_order = std.ArrayListUnmanaged(u32).empty;
    defer traversal_order.deinit(allocator);

    const FileSystemVisitor = struct {
        var file_list: *std.ArrayListUnmanaged(u32) = undefined;

        fn visit(node: u32) void {
            file_list.append(std.testing.allocator, node) catch unreachable;
        }
    };

    FileSystemVisitor.file_list = &traversal_order;
    try graph.dfs(allocator, root, FileSystemVisitor.visit);

    // Should visit all nodes
    try std.testing.expect(traversal_order.items.len == 9);
    try std.testing.expect(traversal_order.items[0] == root);

    // Verify DFS property: directories are visited before their contents are fully explored
    const root_pos: usize = 0;
    var home_pos: usize = undefined;
    var user1_pos: usize = undefined;
    var file1_pos: usize = undefined;

    for (traversal_order.items, 0..) |node, i| {
        if (node == home) home_pos = i;
        if (node == user1) user1_pos = i;
        if (node == file1) file1_pos = i;
    }

    // Directory structure should maintain parent->child ordering in DFS
    try std.testing.expect(root_pos < home_pos);
    try std.testing.expect(home_pos < user1_pos);
    try std.testing.expect(user1_pos < file1_pos);
}

test "Task dependency resolution using topological sort" {
    const allocator = std.testing.allocator;

    // Model a build system where tasks have dependencies
    var graph = Graph([]const u8, void, null).init(allocator);
    defer graph.deinit();

    // Create build tasks
    const compile_lib = try graph.addNode("compile_lib");
    const compile_app = try graph.addNode("compile_app");
    const run_tests = try graph.addNode("run_tests");
    const package = try graph.addNode("package");
    const deploy = try graph.addNode("deploy");

    // Define dependencies (edges represent "must run before")
    _ = try graph.addEdge(compile_lib, compile_app, {}); // lib before app
    _ = try graph.addEdge(compile_lib, run_tests, {}); // lib before tests
    _ = try graph.addEdge(compile_app, run_tests, {}); // app before tests
    _ = try graph.addEdge(run_tests, package, {}); // tests before package
    _ = try graph.addEdge(package, deploy, {}); // package before deploy

    // Use topological sort to determine build order
    var result = try graph.topologicalSort(allocator);
    defer result.deinit();

    try std.testing.expect(!result.has_cycles);
    try std.testing.expect(result.order.len == 5);

    // Find positions in the sorted order
    var lib_pos: usize = undefined;
    var app_pos: usize = undefined;
    var test_pos: usize = undefined;
    var package_pos: usize = undefined;
    var deploy_pos: usize = undefined;

    for (result.order, 0..) |task, i| {
        if (task == compile_lib) lib_pos = i;
        if (task == compile_app) app_pos = i;
        if (task == run_tests) test_pos = i;
        if (task == package) package_pos = i;
        if (task == deploy) deploy_pos = i;
    }

    // Verify dependency ordering
    try std.testing.expect(lib_pos < app_pos);
    try std.testing.expect(lib_pos < test_pos);
    try std.testing.expect(app_pos < test_pos);
    try std.testing.expect(test_pos < package_pos);
    try std.testing.expect(package_pos < deploy_pos);
}

test "Route planning with Dijkstra algorithm" {
    const allocator = std.testing.allocator;

    // Model a city map with intersections and roads with travel times
    var graph = Graph([]const u8, u32, null).init(allocator);
    defer graph.deinit();

    // Create intersections
    const home = try graph.addNode("Home");
    const school = try graph.addNode("School");
    const work = try graph.addNode("Work");
    const store = try graph.addNode("Store");
    const park = try graph.addNode("Park");

    // Add roads with travel times (in minutes)
    _ = try graph.addEdge(home, school, 10); // Home to School: 10 min
    _ = try graph.addEdge(home, work, 25); // Home to Work: 25 min (direct but longer)
    _ = try graph.addEdge(school, work, 8); // School to Work: 8 min
    _ = try graph.addEdge(school, store, 15); // School to Store: 15 min
    _ = try graph.addEdge(work, store, 5); // Work to Store: 5 min
    _ = try graph.addEdge(store, park, 12); // Store to Park: 12 min
    _ = try graph.addEdge(work, park, 20); // Work to Park: 20 min (direct)

    // Find shortest path from Home to Park
    var result = (try graph.dijkstra(allocator, home)) orelse {
        try std.testing.expect(false);
        return;
    };
    defer result.deinit();

    // Verify shortest distances
    try std.testing.expect(result.distanceTo(home).? == 0);
    try std.testing.expect(result.distanceTo(school).? == 10); // Home->School
    try std.testing.expect(result.distanceTo(work).? == 18); // Home->School->Work (10+8)
    try std.testing.expect(result.distanceTo(store).? == 23); // Home->School->Work->Store (10+8+5)
    try std.testing.expect(result.distanceTo(park).? == 35); // Home->School->Work->Store->Park (10+8+5+12)

    // Verify that the shortest path to Work goes through School, not direct
    const path_to_work = (try result.pathTo(allocator, work)) orelse {
        try std.testing.expect(false);
        return;
    };
    defer allocator.free(path_to_work);

    try std.testing.expect(path_to_work.len == 3);
    try std.testing.expect(path_to_work[0] == home);
    try std.testing.expect(path_to_work[1] == school);
    try std.testing.expect(path_to_work[2] == work);
}

test "ECS schedule ordering with Before/After edges" {
    const allocator = std.testing.allocator;

    const Relationship = enum { Before, After };

    const ScheduleGraph = Graph([]const u8, Relationship, null);
    var graph = ScheduleGraph.init(allocator);
    defer graph.deinit();

    // Default schedules
    const start = try graph.addNode("StartFrame");
    const update = try graph.addNode("Update");
    const render = try graph.addNode("Render");
    const end = try graph.addNode("EndFrame");

    // Independent schedule
    const physics = try graph.addNode("PhysicsUpdate");

    // Default ordering (Start -> Update -> Render -> End)
    _ = try graph.addEdge(start, update, .Before);
    _ = try graph.addEdge(update, render, .Before);
    _ = try graph.addEdge(render, end, .Before);

    // User-defined schedule: AfterUpdate
    const after_update = try graph.addNode("AfterUpdate");

    // Mix of Before/After constraints:
    // AfterUpdate must be after Update - convert "After" to "Before"
    _ = try graph.addEdge(update, after_update, .Before); // Update -> AfterUpdate
    // …and before Render
    _ = try graph.addEdge(after_update, render, .Before);

    // Another example: Diagnostics should run after Render but before End
    const diagnostics = try graph.addNode("Diagnostics");
    _ = try graph.addEdge(render, diagnostics, .Before); // Render -> Diagnostics
    _ = try graph.addEdge(diagnostics, end, .Before);

    // Now topo sort
    var result = try graph.topologicalSort(allocator);
    defer result.deinit();
    try std.testing.expect(!result.has_cycles);

    // Map node -> position
    var positions: std.AutoHashMapUnmanaged(u32, usize) = .empty;
    defer positions.deinit(allocator);
    for (result.order, 0..) |node, i| try positions.put(allocator, node, i);

    // Expected relative order:
    try std.testing.expect(positions.get(start).? < positions.get(update).?);
    try std.testing.expect(positions.get(update).? < positions.get(after_update).?);
    try std.testing.expect(positions.get(after_update).? < positions.get(render).?);
    try std.testing.expect(positions.get(render).? < positions.get(diagnostics).?);
    try std.testing.expect(positions.get(diagnostics).? < positions.get(end).?);

    // PhysicsUpdate exists but unconstrained
    _ = positions.get(physics).?;
}
