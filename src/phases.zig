const std = @import("std");
const root = @import("root.zig");

const App = root.App;
const Commands = root.Commands;
const Schedule = root.Schedule;
const World = root.World;

// ─────────────────────────────────────────────────────────────────────────────
// Schedules & Context (compatible with your existing code)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
//// IR (Path → Diff → Plan)
// ─────────────────────────────────────────────────────────────────────────────

const NodeKind = enum { Union, Struct };

const EnterFn = *const fn (*anyopaque, *PhaseContext) anyerror!void;
const ExitFn = *const fn (*anyopaque, *PhaseContext) anyerror!void;

fn noEnter(_: *anyopaque, _: *PhaseContext) anyerror!void {}
fn noExit(_: *anyopaque, _: *PhaseContext) anyerror!void {}

fn wrapEnter(comptime T: type) EnterFn {
    if (@hasDecl(T, "enter")) {
        return struct {
            fn f(p: *anyopaque, ctx: *PhaseContext) anyerror!void {
                const tp: *T = @ptrCast(@alignCast(p));
                return T.enter(tp, ctx);
            }
        }.f;
    }
    return noEnter;
}

fn wrapExit(comptime T: type) ExitFn {
    if (@hasDecl(T, "exit")) {
        return struct {
            fn f(p: *anyopaque, ctx: *PhaseContext) anyerror!void {
                const tp: *T = @ptrCast(@alignCast(p));
                return T.exit(tp, ctx);
            }
        }.f;
    }
    return noExit;
}

const NodeRef = struct {
    /// Stable identity for LCA comparison. For unions we use the TYPE name (not tag),
    /// so swapping variants under the same parent still shares the union node.
    label: []const u8,
    ptr: *anyopaque,
    kind: NodeKind,
    enter_fn: EnterFn,
    exit_fn: ExitFn,
};

const NodeChain = struct {
    buf: [16]NodeRef = undefined,
    len: usize = 0,

    fn push(self: *NodeChain, n: NodeRef) !void {
        if (self.len == self.buf.len) return error.TooDeep;
        self.buf[self.len] = n;
        self.len += 1;
    }

    fn slice(self: *const NodeChain) []const NodeRef {
        return self.buf[0..self.len];
    }
};

/// Build a normalized path from root → leaf. Labels use type names only.
fn buildChain(comptime T: type, ptr: anytype, chain: *NodeChain) !void {
    comptime std.debug.assert(@typeInfo(@TypeOf(ptr)) == .pointer);

    switch (@typeInfo(T)) {
        .@"union" => |u| {
            // Push the union node itself (LCA will match on type name).
            try chain.push(.{
                .label = @typeName(T),
                .ptr = @ptrCast(@constCast(ptr)),
                .kind = .Union,
                .enter_fn = wrapEnter(T),
                .exit_fn = wrapExit(T),
            });

            // Recurse into the active payload.
            const tag = std.meta.activeTag(ptr.*);
            inline for (u.fields) |f| {
                if (std.mem.eql(u8, @tagName(tag), f.name)) {
                    const FT = f.type;
                    const child_ptr = &@field(ptr.*, f.name);

                    switch (@typeInfo(FT)) {
                        .@"union" => try buildChain(FT, child_ptr, chain),
                        .@"struct" => try chain.push(.{
                            .label = @typeName(FT),
                            .ptr = @ptrCast(@constCast(child_ptr)),
                            .kind = .Struct,
                            .enter_fn = wrapEnter(FT),
                            .exit_fn = wrapExit(FT),
                        }),
                        else => {},
                    }
                }
            }
        },
        .@"struct" => {
            try chain.push(.{
                .label = @typeName(T),
                .ptr = @ptrCast(ptr),
                .kind = .Struct,
                .enter_fn = wrapEnter(T),
                .exit_fn = wrapExit(T),
            });
        },
        else => return error.UnsupportedPhaseType,
    }
}

fn lowestCommonIndex(a: *const NodeChain, b: *const NodeChain) usize {
    const as = a.slice();
    const bs = b.slice();
    const n = @min(as.len, bs.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!std.mem.eql(u8, as[i].label, bs[i].label)) break;
    }
    return i; // first differing index; nodes [0..i) are common
}

const Action = union(enum) { Exit: usize, Enter: usize };

const Plan = struct {
    actions: [32]Action = undefined,
    len: usize = 0,

    fn push(self: *Plan, a: Action) !void {
        if (self.len == self.actions.len) return error.PlanTooLarge;
        self.actions[self.len] = a;
        self.len += 1;
    }
};

fn buildPlan(plan: *Plan, old_chain: *const NodeChain, new_chain: *const NodeChain, lca: usize) void {
    // Exits: old leaf → lca (exclusive)
    var i: isize = @as(isize, @intCast(old_chain.len)) - 1;
    while (i >= 0 and @as(isize, @intCast(i)) >= lca) : (i -= 1) {
        plan.push(.{ .Exit = @as(usize, @intCast(i)) }) catch unreachable;
    }
    // Enters: lca → new leaf (inclusive)
    var j: usize = lca;
    while (j < new_chain.len) : (j += 1) {
        plan.push(.{ .Enter = j }) catch unreachable;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public plugin API (same shape as your old one, but using the IR core)
// ─────────────────────────────────────────────────────────────────────────────

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

            // Seed the very first transition to the initial phase.
            try app.insertResource(NextPhase{ .phase = initial_phase });

            // BetweenFrames drives transitions; Update runs the live pipeline.
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

        // ───────────── Systems ─────────────

        /// Run active update pipeline every frame.
        fn run_phase_update_schedule(commands: *Commands) !void {
            const world = commands.world;
            if (world.getResource(PhaseSchedules)) |ps| {
                try ps.update.run(world);
            }
        }

        /// Transition driver: build IRs, compute plan, run exits/enters, rebuild update.
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

            // Prepare staging
            ps_ptr.clearEnterExit(allocator);

            var ctx = PhaseContext{
                .app = app,
                .world = world,
                .schedules = ps_ptr,
            };

            // Build chains (old may be empty on first activation)
            var old_chain: NodeChain = .{};
            var new_chain: NodeChain = .{};
            var have_old = false;

            if (world.hasResource(CurrentPhase)) {
                const curr_res: *CurrentPhase = world.getResource(CurrentPhase).?;
                try buildChain(Phases, &curr_res.phase, &old_chain);
                have_old = true;
            }
            try buildChain(Phases, next_phase_ptr, &new_chain);

            const lca = if (have_old) lowestCommonIndex(&old_chain, &new_chain) else 0;

            var plan: Plan = .{};
            buildPlan(&plan, &old_chain, &new_chain, lca);

            // Execute EXITS (leaf → LCA), then flush exit schedule immediately
            var k: usize = 0;
            while (k < plan.len) : (k += 1) {
                const act = plan.actions[k];
                switch (act) {
                    .Exit => |idx| {
                        const n = old_chain.buf[idx];
                        try n.exit_fn(n.ptr, &ctx);
                    },
                    else => {},
                }
            }
            try ps_ptr.exit.run(world);
            ps_ptr.clearEnterExit(allocator);

            // Commit CurrentPhase = NextPhase
            if (world.hasResource(CurrentPhase)) _ = world.removeResource(CurrentPhase);
            try world.insertResource(CurrentPhase{ .phase = next_res.phase });

            // Rebuild UPDATE before Enter (so enter can add to a clean pipeline)
            ps_ptr.clearUpdate(allocator);

            // Execute ENTERS (LCA → leaf), then flush enter schedule immediately
            k = 0;
            while (k < plan.len) : (k += 1) {
                const act2 = plan.actions[k];
                switch (act2) {
                    .Enter => |idx| {
                        const n2 = new_chain.buf[idx];
                        try n2.enter_fn(n2.ptr, &ctx);
                    },
                    else => {},
                }
            }
            try ps_ptr.enter.run(world);
            ps_ptr.clearEnterExit(allocator);

            // Clear the transition request
            _ = world.removeResource(NextPhase);
        }
    };
}
