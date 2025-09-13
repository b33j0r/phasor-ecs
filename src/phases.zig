const std = @import("std");
const root = @import("root.zig");
const App = root.App;
const Commands = root.Commands;
const Schedule = root.Schedule;

pub const PhaseContext = struct {
    app: *App,
    commands: *Commands,

    pub fn addSchedule(self: PhaseContext, name: []const u8) !*Schedule {
        const sched = try self.app.addSchedule(name);
        // By default, place custom schedules between Update and Render for per-frame execution
        try self.app.scheduleAfter(name, "Update");
        try self.app.scheduleBefore(name, "Render");
        return sched;
    }

    pub fn removeSchedule(self: PhaseContext, name: []const u8) !void {
        try self.app.removeSchedule(name);
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

        fn phase_transition_system(commands: *Commands) !void {
            // Only proceed if a next phase is requested
            if (!commands.world.hasResource(NextPhase)) {
                return;
            }

            var ctx = PhaseContext{
                .app = Self.app_ptr.?,
                .commands = commands,
            };

            const next_phase_res: *NextPhase = commands.world.getResource(NextPhase).?;
            const current_phase: ?*CurrentPhase = commands.world.getResource(CurrentPhase);

            if (current_phase) |curr_phase| {
                // Call exit on current leaf
                try call_exit_on_leaf(@TypeOf(curr_phase.phase), &curr_phase.phase, &ctx);
                // Remove CurrentPhase resource
                _ = commands.removeResource(CurrentPhase);
            }

            // Update CurrentPhase resource first, so enter gets a stable address
            try commands.insertResource(CurrentPhase{ .phase = next_phase_res.phase });
            const new_curr: *CurrentPhase = commands.world.getResource(CurrentPhase).?;

            // Call enter on the new leaf
            try call_enter_on_leaf(@TypeOf(new_curr.phase), &new_curr.phase, &ctx);

            // Remove NextPhase resource
            _ = commands.removeResource(NextPhase);
        }
    };
}
