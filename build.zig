const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add phasor-graph as a dependency
    const phasor_graph_dep = b.dependency("phasor_graph", .{});
    const phasor_graph_mod = phasor_graph_dep.module("phasor-graph");

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

    // Add phasor-channel as a local module
    const phasor_channel_mod = b.addModule("phasor-channel", .{
        .root_source_file = b.path("lib/phasor-channel/channel.zig"),
        .target = target,
        .optimize = optimize,
    });
    const phasor_channel_tests_mod = b.addModule("phasor_channel_tests", .{
        .root_source_file = b.path("lib/phasor-channel/test_channel.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-channel", .module = phasor_channel_mod },
        },
    });
    const phasor_channel_tests = b.addTest(.{
        .root_module = phasor_channel_tests_mod,
    });
    const run_phasor_channel_tests = b.addRunArtifact(phasor_channel_tests);

    // Add phasor-actor as a local module (depends on phasor-channel)
    const phasor_actor_mod = b.addModule("phasor-actor", .{
        .root_source_file = b.path("lib/phasor-actor/actor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-channel", .module = phasor_channel_mod },
        },
    });
    const phasor_actor_tests_mod = b.addModule("phasor_actor_tests", .{
        .root_source_file = b.path("lib/phasor-actor/test_actor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-actor", .module = phasor_actor_mod },
            .{ .name = "phasor-channel", .module = phasor_channel_mod },
        },
    });
    const phasor_actor_tests = b.addTest(.{
        .root_module = phasor_actor_tests_mod,
    });
    const run_phasor_actor_tests = b.addRunArtifact(phasor_actor_tests);

    const phasor_ecs_mod = b.addModule("phasor-ecs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-db", .module = phasor_db_mod },
            .{ .name = "phasor-actor", .module = phasor_actor_mod },
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

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_phasor_ecs_mod_tests.step);
    test_step.dependOn(&run_phasor_ecs_dir_tests.step);
    test_step.dependOn(&run_phasor_db_tests.step);
    test_step.dependOn(&run_phasor_channel_tests.step);
    test_step.dependOn(&run_phasor_actor_tests.step);

    // Example: rooms
    const rooms_example_mod = b.addModule("rooms_example", .{
        .root_source_file = b.path("examples/rooms/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
        },
    });
    const rooms_example = b.addExecutable(.{
        .name = "examples_rooms",
        .root_module = rooms_example_mod,
    });
    const run_rooms = b.addRunArtifact(rooms_example);
    const examples_rooms_step = b.step("examples-rooms", "Build and run the rooms example");
    examples_rooms_step.dependOn(&run_rooms.step);
}
