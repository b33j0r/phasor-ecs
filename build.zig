const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add phasor-db as a lib module
    const phasor_db_mod = b.addModule(
        "phasor-db",
        .{
            .root_source_file = b.path("lib/phasor-db/root.zig"),
            .target = target,
            .optimize = optimize,
        },
    );
    const phasor_db_tests_mod = b.addModule("phasor_db_tests", .{
        .root_source_file = b.path("lib/phasor-db/tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-db", .module = phasor_db_mod },
        },
    });
    const phasor_db_tests = b.addTest(.{
        .root_module = phasor_db_tests_mod,
    });
    const run_phasor_db_tests = b.addRunArtifact(phasor_db_tests);

    // Add phasor-graph as a local module
    const phasor_graph_mod = b.addModule("phasor-graph", .{
        .root_source_file = b.path("lib/phasor-graph/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const phasor_graph_tests_mod = b.addModule("phasor_graph_tests", .{
        .root_source_file = b.path("lib/phasor-graph/tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-graph", .module = phasor_graph_mod },
        },
    });
    const phasor_graph_tests = b.addTest(.{
        .root_module = phasor_graph_tests_mod,
    });
    const run_phasor_graph_tests = b.addRunArtifact(phasor_graph_tests);

    // Add phasor-channel as a local module
    const phasor_channel_dep = b.dependency("phasor_channel", .{});
    const phasor_channel_mod = phasor_channel_dep.module("phasor-channel");

    // The main phasor-ecs module (depends on phasor-db, phasor-channel, phasor-graph)
    const phasor_ecs_mod = b.addModule("phasor-ecs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-db", .module = phasor_db_mod },
            .{ .name = "phasor-channel", .module = phasor_channel_mod },
            .{ .name = "phasor-graph", .module = phasor_graph_mod },
        },
    });

    const phasor_ecs_mod_tests = b.addTest(.{
        .root_module = phasor_ecs_mod,
    });

    const run_phasor_ecs_mod_tests = b.addRunArtifact(phasor_ecs_mod_tests);

    const phasor_ecs_tests_dir_tests_mod = b.addModule("phasor_ecs_tests", .{
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-db", .module = phasor_db_mod },
            .{ .name = "phasor-graph", .module = phasor_graph_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
        },
    });

    const phasor_ecs_dir_tests = b.addTest(.{
        .root_module = phasor_ecs_tests_dir_tests_mod,
    });

    const run_phasor_ecs_dir_tests = b.addRunArtifact(phasor_ecs_dir_tests);

    // The phasor-common module (depends on phasor-ecs)
    _ = b.addModule("phasor-common", .{
        .root_source_file = b.path("lib/phasor-common/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
        },
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_phasor_ecs_mod_tests.step);
    test_step.dependOn(&run_phasor_ecs_dir_tests.step);
    test_step.dependOn(&run_phasor_db_tests.step);
    test_step.dependOn(&run_phasor_graph_tests.step);
}
