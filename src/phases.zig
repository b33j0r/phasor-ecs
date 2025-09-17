const std = @import("std");
const root = @import("root.zig");
const App = root.App;
const Commands = root.Commands;
const Schedule = root.Schedule;
const World = root.World;

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

    pub fn deinit(self: *PhaseSchedules) void {
        self.enter.deinit();
        self.update.deinit();
        self.exit.deinit();
    }
};

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

pub fn PhasesPlugin(comptime PhasesT: type, initial_phase: PhasesT) type {
    return struct {
        pub const Phases = PhasesT;

        pub const CurrentPhase = struct {
            phase: Phases,
        };

        pub const NextPhase = struct {
            phase: Phases,
        };

        const Self = @This();
        var app_ptr: ?*App = null;

        pub fn build(_: *Self, app: *App) !void {
            // Stash app pointer for PhaseContext construction inside systems
            Self.app_ptr = app;

            // We want to capture the transition into the initial phase,
            // so we use NextPhase instead of CurrentPhase here:
            try app.insertResource(NextPhase{ .phase = initial_phase });

            // Ensure phase transitions run every frame at the end of the frame
            try app.addSystem("BetweenFrames", Self.phase_transition_system);
            // Run the active phase's update schedule during the normal Update schedule
            try app.addSystem("Update", Self.run_phase_update_schedule);
        }

        pub fn cleanup(_: *Self, app: *App) void {
            // On app shutdown, deinit and remove any remaining phase resources
            if (app.world.hasResource(PhaseSchedules)) {
                const ps = app.world.getResource(PhaseSchedules).?;
                ps.deinit();
                _ = app.world.removeResource(PhaseSchedules);
            }
            if (app.world.hasResource(CurrentPhase)) {
                _ = app.world.removeResource(CurrentPhase);
            }
            if (app.world.hasResource(NextPhase)) {
                _ = app.world.removeResource(NextPhase);
            }
        }

        fn call_enter_on_leaf(comptime T: type, ptr: *T, ctx_val: *PhaseContext) anyerror!void {
            const info = @typeInfo(T);
            switch (info) {
                .@"union" => |u| {
                    if (u.tag_type == null) return; // unsupported untagged union
                    switch (ptr.*) {
                        inline else => |*payload| {
                            try call_enter_on_leaf(@TypeOf(payload.*), payload, ctx_val);
                        },
                    }
                },
                .@"struct" => {
                    if (@hasDecl(T, "enter")) {
                        // Determine expected ctx parameter
                        const FnT = @TypeOf(T.enter);
                        const f_info = @typeInfo(FnT).@"fn";
                        if (f_info.params.len >= 2) {
                            if (f_info.params[1].type) |CtxT| {
                                if (CtxT == PhaseContext) {
                                    return T.enter(ptr, ctx_val.*);
                                } else if (CtxT == *PhaseContext) {
                                    return T.enter(ptr, ctx_val);
                                }
                            }
                        }
                        // If signature unexpected, do nothing
                    }
                },
                else => {},
            }
        }

        fn call_exit_on_leaf(comptime T: type, ptr: *T, ctx_val: *PhaseContext) anyerror!void {
            const info = @typeInfo(T);
            switch (info) {
                .@"union" => |u| {
                    if (u.tag_type == null) return; // unsupported untagged union
                    switch (ptr.*) {
                        inline else => |*payload| {
                            try call_exit_on_leaf(@TypeOf(payload.*), payload, ctx_val);
                        },
                    }
                },
                .@"struct" => {
                    if (@hasDecl(T, "exit")) {
                        const FnT = @TypeOf(T.exit);
                        const f_info = @typeInfo(FnT).@"fn";
                        if (f_info.params.len >= 2) {
                            if (f_info.params[1].type) |CtxT| {
                                if (CtxT == PhaseContext) {
                                    return T.exit(ptr, ctx_val.*);
                                } else if (CtxT == *PhaseContext) {
                                    return T.exit(ptr, ctx_val);
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }

        fn run_phase_update_schedule(commands: *Commands) !void {
            const world = commands.world;
            const ps_opt = world.getResource(PhaseSchedules);
            if (ps_opt) |ps| {
                try ps.update.run(world);
            }
        }

        fn phase_transition_system(commands: *Commands) !void {
            const world = commands.world;
            // Only proceed if a next phase is requested
            if (!world.hasResource(NextPhase)) {
                return;
            }

            const app = Self.app_ptr.?;

            const next_phase_res: *NextPhase = world.getResource(NextPhase).?;
            const current_phase: ?*CurrentPhase = world.getResource(CurrentPhase);

            // If there is an existing phase, call its exit, run the exit schedule, and clean up schedules
            if (current_phase) |curr_phase| {
                var ctx_old = PhaseContext{ .app = app, .world = world, .schedules = undefined };
                if (world.getResource(PhaseSchedules)) |ps| {
                    ctx_old.schedules = ps;
                } else {
                    // If missing schedules (should not happen), create a temporary empty one for ctx
                    var temp = PhaseSchedules.init(app.allocator);
                    defer temp.deinit();
                    ctx_old.schedules = &temp;
                }
                try call_exit_on_leaf(@TypeOf(curr_phase.phase), &curr_phase.phase, &ctx_old);
                if (world.getResource(PhaseSchedules)) |ps| {
                    // Run exit schedule then deinit and remove
                    try ps.exit.run(world);
                    ps.deinit();
                    _ = world.removeResource(PhaseSchedules);
                }
                // Remove CurrentPhase resource
                _ = world.removeResource(CurrentPhase);
            }

            // Set new CurrentPhase resource so enter gets a stable address
            try world.insertResource(CurrentPhase{ .phase = next_phase_res.phase });
            const new_curr: *CurrentPhase = world.getResource(CurrentPhase).?;

            // Create and insert new schedules for this phase
            const new_ps = PhaseSchedules.init(app.allocator);
            try world.insertResource(new_ps);
            const ps_ptr = world.getResource(PhaseSchedules).?;

            // Prepare context with schedules and call enter on the new leaf
            var ctx_new = PhaseContext{ .app = app, .world = world, .schedules = ps_ptr };
            try call_enter_on_leaf(@TypeOf(new_curr.phase), &new_curr.phase, &ctx_new);

            // Run enter schedule once
            try ps_ptr.enter.run(world);

            // Remove NextPhase resource
            _ = world.removeResource(NextPhase);
        }
    };
}
