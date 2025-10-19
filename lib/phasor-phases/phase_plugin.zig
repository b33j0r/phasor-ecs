/// Hierarchical Phases plugin with LCA-diff transitions.
/// Usage:
///   const MyPlugin = PhasePlugin(MyPhases, MyPhases{ .MainMenu = .{} });
pub fn PhasePlugin(PhasesT: type, initial_phase: PhasesT) type {
    return struct {
        allocator: std.mem.Allocator,

        /// Public types/resources
        pub const Phases = PhasesT;
        pub const Stack = PhaseContextStack(Phases);
        pub const NextPhase = struct { phase: Phases };
        pub const CurrentPhase = struct { phase: Phases };
        pub const PhaseContextStackResource = struct { stack: Stack };

        const Self = @This();

        pub fn build(self: *Self, app: *App) !void {
            const stack = try Stack.init(self.allocator, app);
            try app.insertResource(PhaseContextStackResource{ .stack = stack });

            try app.addSystem("Startup", handleInitialPhase);
            try app.addSystem("PostStartup", handlePhaseTransitions);
            try app.addSystem("BetweenFrames", handlePhaseTransitions);
            try app.addSystem("Update", updateCurrentPhaseStack);
        }

        pub fn cleanup(_: *Self, app: *App) !void {
            const world = app.world;
            if (app.getResource(PhaseContextStackResource)) |res| {
                // Run exits deepest→root, then drop contexts.
                try res.stack.forEachReverse(runExitSystems, world);
                while (res.stack.depth() > 0) {
                    if (res.stack.pop()) |ctx| {
                        ctx.deinit();
                        res.stack.allocator.destroy(ctx);
                    }
                }
                res.stack.deinit();
                _ = app.removeResource(PhaseContextStackResource);
            }
        }

        fn handleInitialPhase(commands: *Commands) !void {
            if (!commands.hasResource(NextPhase)) {
                try commands.insertResource(NextPhase{ .phase = initial_phase });
            }
        }

        fn handlePhaseTransitions(commands: *Commands) !void {
            const next_opt = try getNextPhase(commands);
            if (next_opt == null) return;

            const next_phase = next_opt.?;
            const world = commands.world;

            const stack_res = commands.getResource(PhaseContextStackResource) orelse return error.MissingPhaseContextStack;

            if (commands.getResource(CurrentPhase)) |cur_res| {
                const cur = cur_res.phase;

                if (@TypeOf(cur) == @TypeOf(next_phase)) {
                    // Same union root → do LCA diff transition
                    try exitDiff(&stack_res.stack, world, cur, next_phase);
                    try enterDiff(&stack_res.stack, world, cur, next_phase);
                } else {
                    // Different roots → full teardown and rebuild
                    try stack_res.stack.forEachReverse(runExitSystems, world);
                    while (stack_res.stack.depth() > 0) {
                        if (stack_res.stack.pop()) |ctx| {
                            ctx.deinit();
                            stack_res.stack.allocator.destroy(ctx);
                        }
                    }
                    try enterWhole(&stack_res.stack, world, next_phase);
                }

                cur_res.phase = next_phase;
            } else {
                // First activation
                try enterWhole(&stack_res.stack, world, next_phase);
                try commands.insertResource(CurrentPhase{ .phase = next_phase });
            }

            try clearNextPhase(commands);
        }

        fn updateCurrentPhaseStack(commands: *Commands) !void {
            if (commands.getResource(CurrentPhase) == null) return;
            const world = commands.world;

            const stack_res = commands.getResource(PhaseContextStackResource) orelse return error.MissingPhaseContextStack;
            // Update runs root→leaf (each level's active update pipeline)
            try stack_res.stack.forEach(runUpdateSystems, world);
        }

        fn getNextPhase(commands: *Commands) !?Phases {
            return if (commands.getResource(NextPhase)) |n| n.phase else null;
        }

        pub fn setNextPhase(commands: *Commands, phase: Phases) !void {
            if (commands.getResource(NextPhase)) |n| {
                n.phase = phase;
            } else {
                try commands.insertResource(NextPhase{ .phase = phase });
            }
        }

        fn clearNextPhase(commands: *Commands) !void {
            _ = commands.removeResource(NextPhase);
        }

        fn runEnterSystems(ctx: *PhaseContext, world: *World) !void {
            try ctx.runEnter(world);
        }
        fn runExitSystems(ctx: *PhaseContext, world: *World) !void {
            try ctx.runExit(world);
        }
        fn runUpdateSystems(ctx: *PhaseContext, world: *World) !void {
            try ctx.update(world);
        }

        /// Enter the entire subtree `v` (parent first, then child), pushing
        /// a PhaseContext for each level and *running* enter systems immediately.
        fn enterWhole(stack: *Stack, world: *World, v: anytype) !void {
            const T = @TypeOf(v);
            switch (@typeInfo(T)) {
                .@"union" => {
                    const ctx = try stack.push();
                    if (@hasDecl(T, "enter")) {
                        var copy = v;
                        try T.enter(&copy, ctx);
                    }
                    // Run this level's enter systems now.
                    try runEnterSystems(ctx, world);

                    // Recurse to active child
                    switch (v) {
                        inline else => |inner| {
                            if (@TypeOf(inner) != void) try enterWhole(stack, world, inner);
                        },
                    }
                },
                .@"struct" => {
                    const ctx = try stack.push();
                    if (@hasDecl(T, "enter")) {
                        var copy = v;
                        try T.enter(&copy, ctx);
                    }
                    try runEnterSystems(ctx, world);
                },
                else => {},
            }
        }

        /// Exit the entire subtree `v` (child first, then parent), *running*
        /// exit systems just before popping each PhaseContext.
        fn exitWhole(stack: *Stack, world: *World, v: anytype) !void {
            const T = @TypeOf(v);
            switch (@typeInfo(T)) {
                .@"union" => {
                    // Exit active child first
                    switch (v) {
                        inline else => |inner| {
                            if (@TypeOf(inner) != void) try exitWhole(stack, world, inner);
                        },
                    }
                    // Then exit this union level
                    if (@hasDecl(T, "exit")) {
                        const ctx = stack.top().?;
                        var copy = v;
                        try T.exit(&copy, ctx);
                    }
                    // Run exit and pop
                    if (stack.pop()) |ctx| {
                        try runExitSystems(ctx, world);
                        ctx.deinit();
                        stack.allocator.destroy(ctx);
                    }
                },
                .@"struct" => {
                    if (@hasDecl(T, "exit")) {
                        const ctx = stack.top().?;
                        var copy = v;
                        try T.exit(&copy, ctx);
                    }
                    if (stack.pop()) |ctx| {
                        try runExitSystems(ctx, world);
                        ctx.deinit();
                        stack.allocator.destroy(ctx);
                    }
                },
                else => {},
            }
        }

        /// Exit only the *active child* subtree of union `u`, keeping the parent's context.
        fn exitActiveChildOnly(stack: *Stack, world: *World, u: anytype) !void {
            switch (u) {
                inline else => |inner| {
                    if (@TypeOf(inner) != void) try exitWhole(stack, world, inner);
                },
            }
        }

        /// Enter only the *child* subtree of union `u`, assuming the parent context is already mounted.
        fn enterChildOnly(stack: *Stack, world: *World, u: anytype) !void {
            switch (u) {
                inline else => |inner| {
                    if (@TypeOf(inner) != void) try enterWhole(stack, world, inner);
                },
            }
        }

        /// Exit diff: exit from current leaf up to (but not including) the LCA
        fn exitDiff(stack: *Stack, world: *World, cur: anytype, nxt: anytype) !void {
            const CurT = @TypeOf(cur);
            const NxtT = @TypeOf(nxt);

            switch (@typeInfo(CurT)) {
                .@"union" => {
                    if (CurT == NxtT) {
                        const cur_tag = std.meta.activeTag(cur);
                        const nxt_tag = std.meta.activeTag(nxt);
                        if (cur_tag == nxt_tag) {
                            // Same parent and same child → dive deeper; no exit at this level
                            switch (cur) {
                                inline else => |cur_inner, tag| {
                                    const nxt_inner = @field(nxt, @tagName(tag));
                                    try exitDiff(stack, world, cur_inner, nxt_inner);
                                },
                            }
                            return;
                        }
                        // Same union, different tag → exit just the active child
                        try exitActiveChildOnly(stack, world, cur);
                        return;
                    }
                    // Different union types → exit entire current branch
                    try exitWhole(stack, world, cur);
                },
                .@"struct" => {
                    // Leaf types differ → exit this leaf
                    if (CurT != NxtT) {
                        try exitWhole(stack, world, cur);
                    }
                },
                else => {},
            }
        }

        /// Enter diff: enter from just below the LCA down to the new leaf
        fn enterDiff(stack: *Stack, world: *World, cur: anytype, nxt: anytype) !void {
            const CurT = @TypeOf(cur);
            const NxtT = @TypeOf(nxt);

            switch (@typeInfo(NxtT)) {
                .@"union" => {
                    if (CurT == NxtT) {
                        const cur_tag = std.meta.activeTag(cur);
                        const nxt_tag = std.meta.activeTag(nxt);
                        if (cur_tag == nxt_tag) {
                            // Same parent and same child → dive deeper; no enter at this level
                            switch (nxt) {
                                inline else => |nxt_inner, tag| {
                                    const cur_inner = @field(cur, @tagName(tag));
                                    try enterDiff(stack, world, cur_inner, nxt_inner);
                                },
                            }
                            return;
                        }
                        // Same union, different tag → enter only the new child
                        try enterChildOnly(stack, world, nxt);
                        return;
                    }
                    // Different union types → enter full next branch
                    try enterWhole(stack, world, nxt);
                },
                .@"struct" => {
                    // Leaf types differ → enter new leaf
                    if (CurT != NxtT) {
                        try enterWhole(stack, world, nxt);
                    }
                },
                else => {},
            }
        }
    };
}

// Imports
const std = @import("std");

const ecs = @import("phasor-ecs");
const App = ecs.App;
const Commands = ecs.Commands;
const World = ecs.World;

const root = @import("root.zig");
const PhaseContext = root.PhaseContext;
const PhaseContextStack = root.PhaseContextStack;
