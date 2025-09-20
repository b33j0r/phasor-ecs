const std = @import("std");
const root = @import("root.zig");

const App = root.App;
const Commands = root.Commands;
const Schedule = root.Schedule;
const World = root.World;

/// Per-transition and active-update schedules.
/// - `enter` and `exit` are single-use staging schedules executed immediately during a transition.
/// - `update` is the active pipeline for the current path (rebuilt each transition).
pub const PhaseSchedules = struct {
    enter: Schedule,
    update: Schedule,
    exit: Schedule,

    pub fn init(allocator: std.mem.Allocator) PhaseSchedules {
        return .{
            .enter = Schedule.init(allocator),
            .update = Schedule.init(allocator),
            .exit = Schedule.init(allocator),
        };
    }

    /// Clears all schedules and re-initializes them fresh.
    pub fn reset(self: *PhaseSchedules, allocator: std.mem.Allocator) void {
        self.enter.deinit();
        self.update.deinit();
        self.exit.deinit();
        self.* = PhaseSchedules.init(allocator);
    }

    /// Clears only enter and exit staging (used between the two halves of a transition).
    pub fn clearEnterExit(self: *PhaseSchedules, allocator: std.mem.Allocator) void {
        self.enter.deinit();
        self.exit.deinit();
        self.enter = Schedule.init(allocator);
        self.exit = Schedule.init(allocator);
    }

    /// Clears the active update pipeline (to be rebuilt during `enter`).
    pub fn clearUpdate(self: *PhaseSchedules, allocator: std.mem.Allocator) void {
        self.update.deinit();
        self.update = Schedule.init(allocator);
    }

    pub fn deinit(self: *PhaseSchedules) void {
        self.enter.deinit();
        self.update.deinit();
        self.exit.deinit();
    }
};

/// Context passed to phase `enter/exit` to register systems.
pub const PhaseContext = struct {
    app: *App,
    world: *World,
    schedules: *PhaseSchedules,

    pub fn addEnterSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try self.schedules.enter.add(system_fn);
    }
    pub fn addUpdateSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try self.schedules.update.add(system_fn);
    }
    pub fn addExitSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try self.schedules.exit.add(system_fn);
    }
};

/// Build a hierarchical phases plugin from a tagged-union type.
pub fn PhasesPlugin(comptime PhasesT: type, initial_phase: PhasesT) type {
    return struct {
        pub const Phases = PhasesT;

        /// The currently active phase (leaf).
        pub const CurrentPhase = struct { phase: Phases };
        /// Set to request a transition. Cleared automatically after transition is applied.
        pub const NextPhase = struct { phase: Phases };

        const Self = @This();
        var app_ptr: ?*App = null;

        /// Optional convenience: request a phase change from any system.
        pub fn requestTransition(_: *Self, commands: *Commands, next: Phases) !void {
            if (commands.world.hasResource(NextPhase)) {
                _ = commands.world.removeResource(NextPhase);
            }
            try commands.world.insertResource(NextPhase{ .phase = next });
        }

        pub fn build(_: *Self, app: *App) !void {
            Self.app_ptr = app;

            try app.insertResource(NextPhase{ .phase = initial_phase });

            try app.addSystem("BetweenFrames", Self.handle_phase_transitions);
            try app.addSystem("Update", Self.run_phase_update_schedule);
        }

        pub fn cleanup(_: *Self, app: *App) void {
            if (app.world.hasResource(PhaseSchedules)) {
                app.world.getResource(PhaseSchedules).?.deinit();
                _ = app.world.removeResource(PhaseSchedules);
            }
            if (app.world.hasResource(CurrentPhase)) _ = app.world.removeResource(CurrentPhase);
            if (app.world.hasResource(NextPhase)) _ = app.world.removeResource(NextPhase);
        }

        /// Run active update pipeline every frame.
        fn run_phase_update_schedule(commands: *Commands) !void {
            const world = commands.world;
            if (world.getResource(PhaseSchedules)) |ps| {
                try ps.update.run(world);
            }
        }

        /// Internal helper: recursive DCA with an explicit `is_root` flag.
        fn dcaImpl(comptime T: type, a: *const T, b: *const T, depth: usize, comptime is_root: bool) usize {
            const ti = @typeInfo(T);
            switch (ti) {
                .@"union" => |u| {
                    if (u.tag_type == null) return depth;

                    const tag_a = std.meta.activeTag(a.*);
                    const tag_b = std.meta.activeTag(b.*);

                    if (tag_a != tag_b) {
                        // At root, different tags => nothing in common.
                        // At deeper unions, count THIS union node as common, so return depth + 1.
                        return if (is_root) depth else depth + 1;
                    }

                    // Same tag: this union node is common.
                    return switch (a.*) {
                        inline else => |*pa, tag| {
                            const pb = &@field(b.*, @tagName(tag));
                            const PT = @TypeOf(pa.*);
                            return dcaImpl(PT, pa, pb, depth + 1, false);
                        },
                    };
                },
                .@"struct" => return depth + 1,
                else => return depth + 1,
            }
        }

        fn deepestCommonDepth(comptime T: type, a: *const T, b: *const T) usize {
            return dcaImpl(T, a, b, 0, true);
        }

        fn handle_phase_transitions(commands: *Commands) !void {
            const world = commands.world;
            if (!world.hasResource(NextPhase)) return;

            const app = Self.app_ptr.?;
            const allocator = app.allocator;

            const next_res: *NextPhase = world.getResource(NextPhase).?;
            const next_phase_ptr: *const Phases = &next_res.phase;

            // Ensure PhaseSchedules exists
            var ps_ptr: *PhaseSchedules = blk: {
                if (world.getResource(PhaseSchedules)) |ps| break :blk ps;
                try world.insertResource(PhaseSchedules.init(allocator));
                break :blk world.getResource(PhaseSchedules).?;
            };

            // Always start a transition by clearing enter/exit staging.
            ps_ptr.clearEnterExit(allocator);

            var ctx = PhaseContext{
                .app = app,
                .world = world,
                .schedules = ps_ptr,
            };

            // Compute DCA ONCE vs. old current and next.
            var common_depth: usize = 0;
            const had_current = world.hasResource(CurrentPhase);
            if (had_current) {
                const curr_res: *CurrentPhase = world.getResource(CurrentPhase).?;
                const curr_phase_ptr: *const Phases = &curr_res.phase;

                common_depth = deepestCommonDepth(Phases, curr_phase_ptr, next_phase_ptr);

                // Exit tail (leaf -> up) strictly below the DCA.
                try exitTailFromDepth(Phases, curr_phase_ptr, &ctx, common_depth, 1);
                try ps_ptr.exit.run(world);
                ps_ptr.clearEnterExit(allocator);

                // Swap CurrentPhase to NEXT.
                _ = world.removeResource(CurrentPhase);
                try world.insertResource(CurrentPhase{ .phase = next_res.phase });
            } else {
                // First activation: treat as crossing root.
                common_depth = 0;
                try world.insertResource(CurrentPhase{ .phase = next_res.phase });
            }

            // Rebuild the active update pipeline for the new path.
            ps_ptr.clearUpdate(allocator);

            // Enter tail (down -> leaf) strictly below the SAME DCA.
            const now_curr: *CurrentPhase = world.getResource(CurrentPhase).?;
            try enterTailFromDepth(Phases, &now_curr.phase, &ctx, common_depth, 1);
            try ps_ptr.enter.run(world);
            ps_ptr.clearEnterExit(allocator);

            // Clear the transition request.
            _ = world.removeResource(NextPhase);
        }

        /// Exit nodes with depth > common_depth (leaf → root).
        fn exitTailFromDepth(comptime T: type, node: *const T, ctx: *PhaseContext, common_depth: usize, current_depth: usize) anyerror!void {
            const ti = @typeInfo(T);
            switch (ti) {
                .@"union" => {
                    // Dive to the active payload first (leaf-first).
                    switch (node.*) {
                        inline else => |*payload| {
                            const PT = @TypeOf(payload.*);
                            try exitTailFromDepth(PT, payload, ctx, common_depth, current_depth + 1);
                        },
                    }
                    if (current_depth > common_depth) {
                        try call_exit_on_node(T, @constCast(node), ctx);
                    }
                },
                else => {
                    if (current_depth > common_depth) {
                        try call_exit_on_node(T, @constCast(node), ctx);
                    }
                },
            }
        }

        /// Enter nodes with depth > common_depth (root → leaf).
        fn enterTailFromDepth(comptime T: type, node: *const T, ctx: *PhaseContext, common_depth: usize, current_depth: usize) anyerror!void {
            const ti = @typeInfo(T);
            switch (ti) {
                .@"union" => {
                    if (current_depth > common_depth) {
                        try call_enter_on_node(T, @constCast(node), ctx);
                    }
                    // Then descend into the active payload.
                    switch (node.*) {
                        inline else => |*payload| {
                            const PT = @TypeOf(payload.*);
                            try enterTailFromDepth(PT, payload, ctx, common_depth, current_depth + 1);
                        },
                    }
                },
                else => {
                    if (current_depth > common_depth) {
                        try call_enter_on_node(T, @constCast(node), ctx);
                    }
                },
            }
        }

        /// Calls `T.enter(self: *T, ctx: *PhaseContext)` or `T.enter(self: *T, ctx: PhaseContext)` if present.
        fn call_enter_on_node(comptime T: type, ptr: *T, ctx_val: *PhaseContext) anyerror!void {
            const ti = @typeInfo(T);
            if (ti != .@"struct" and ti != .@"union") return;
            if (!@hasDecl(T, "enter")) return;

            const FnT = @TypeOf(T.enter);
            if (@typeInfo(FnT) != .@"fn") return;
            const f = @typeInfo(FnT).@"fn";
            if (f.params.len < 2) return;

            if (f.params[0].type) |P0| {
                if (P0 != *T and P0 != *const T) return;
            } else return;

            if (f.params[1].type) |P1| {
                if (P1 == *PhaseContext) {
                    return T.enter(ptr, ctx_val);
                } else if (P1 == PhaseContext) {
                    return T.enter(ptr, ctx_val.*);
                }
            }
        }

        /// Calls `T.exit(self: *T, ctx: *PhaseContext)` or `T.exit(self: *T, ctx: PhaseContext)` if present.
        fn call_exit_on_node(comptime T: type, ptr: *T, ctx_val: *PhaseContext) anyerror!void {
            const ti = @typeInfo(T);
            if (ti != .@"struct" and ti != .@"union") return;
            if (!@hasDecl(T, "exit")) return;

            const FnT = @TypeOf(T.exit);
            if (@typeInfo(FnT) != .@"fn") return;
            const f = @typeInfo(FnT).@"fn";
            if (f.params.len < 2) return;

            if (f.params[0].type) |P0| {
                if (P0 != *T and P0 != *const T) return;
            } else return;

            if (f.params[1].type) |P1| {
                if (P1 == *PhaseContext) {
                    return T.exit(ptr, ctx_val);
                } else if (P1 == PhaseContext) {
                    return T.exit(ptr, ctx_val.*);
                }
            }
        }
    };
}
