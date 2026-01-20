const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add phasor-db as a dependency module
    const phasor_db_dep = b.dependency("phasor_db", .{});
    const phasor_db_mod = phasor_db_dep.module("phasor-db");

    // Add phasor-graph as a dependency module
    const phasor_graph_dep = b.dependency("phasor_graph", .{});
    const phasor_graph_mod = phasor_graph_dep.module("phasor-graph");

    // Add phasor-channel as a dependency module
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
    const phasor_common_mod = b.addModule("phasor-common", .{
        .root_source_file = b.path("lib/phasor-common/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
        },
    });

    const phasor_common_tests = b.addTest(.{
        .root_module = phasor_common_mod,
    });
    const run_phasor_common_tests = b.addRunArtifact(phasor_common_tests);

    // The phasor-phases module (depends on phasor-ecs)
    const phasor_phases_mod = b.addModule("phasor-phases", .{
        .root_source_file = b.path("lib/phasor-phases/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
        },
    });

    const phasor_phases_tests_mod = b.addModule("phasor_phases_tests", .{
        .root_source_file = b.path("lib/phasor-phases/tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-phases", .module = phasor_phases_mod },
        },
    });
    const phasor_phases_tests = b.addTest(.{
        .root_module = phasor_phases_tests_mod,
    });
    const run_phasor_phases_tests = b.addRunArtifact(phasor_phases_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_phasor_ecs_mod_tests.step);
    test_step.dependOn(&run_phasor_ecs_dir_tests.step);
    test_step.dependOn(&run_phasor_phases_tests.step);
    test_step.dependOn(&run_phasor_common_tests.step);
}
