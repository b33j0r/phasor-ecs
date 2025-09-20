const std = @import("std");
const phasor_ecs = @import("phasor-ecs");

const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const PhasesPlugin = phasor_ecs.PhasesPlugin;
const PhaseContext = phasor_ecs.PhaseContext;

const Phases = union(enum) {
    MainMenu: MainMenu,
    InGame: InGame,
};

const PhasesPluginImpl = PhasesPlugin(Phases, Phases.MainMenu);
const NextPhase = PhasesPluginImpl.NextPhase;

/// InGame (parent managing shared entities for Playing/Paused)
const InGame = union(enum) {
    Playing: Playing,
    Paused: Paused,

    pub fn enter(_: *InGame, ctx: *PhaseContext) !void {
        if (!ctx.world.hasResource(GameWorld)) {
            try ctx.world.insertResource(GameWorld{ .entities_created = false });
        }
        try ctx.world.insertResource(PhaseEvent{ .message = "InGame.enter" });
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "InGame.enter");
    }

    pub fn exit(_: *InGame, ctx: *PhaseContext) !void {
        try ctx.world.insertResource(PhaseEvent{ .message = "InGame.exit" });
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "InGame.exit");
    }
};

/// MainMenu
const MainMenu = struct {
    pub fn enter(_: *MainMenu, ctx: *PhaseContext) !void {
        // NOTE: we keep this system, but tests won’t run Update unless they want to.
        try ctx.addUpdateSystem(MainMenu.transition_to_in_game);
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "MainMenu.enter");
    }
    pub fn exit(_: *MainMenu, ctx: *PhaseContext) !void {
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "MainMenu.exit");
    }
    fn transition_to_in_game(commands: *Commands) !void {
        try commands.insertResource(
            NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } },
        );
    }
};

/// Playing
const Playing = struct {
    pub fn enter(_: *Playing, ctx: *PhaseContext) !void {
        try ctx.addUpdateSystem(Playing.create_game_entities);
        try ctx.addUpdateSystem(Playing.check_for_pause);
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "Playing.enter");
    }
    pub fn exit(_: *Playing, ctx: *PhaseContext) !void {
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "Playing.exit");
    }
    fn create_game_entities(commands: *Commands) !void {
        if (commands.world.getResourceMut(GameWorld)) |gw| {
            if (!gw.entities_created) {
                gw.entities_created = true;
                try commands.insertResource(PhaseEvent{ .message = "Game entities created" });
            }
        }
    }
    fn check_for_pause(commands: *Commands) !void {
        if (commands.world.getResource(GameWorld)) |gw| {
            if (gw.entities_created) {
                try commands.insertResource(
                    NextPhase{ .phase = Phases{ .InGame = .{ .Paused = .{} } } },
                );
            }
        }
    }
};

/// Paused
const Paused = struct {
    pub fn enter(_: *Paused, ctx: *PhaseContext) !void {
        try ctx.addUpdateSystem(Paused.unpause_game);
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "Paused.enter");
    }
    pub fn exit(_: *Paused, ctx: *PhaseContext) !void {
        if (ctx.world.getResource(TransitionTracker)) |t|
            try t.events.append(t.allocator, "Paused.exit");
    }
    fn unpause_game(commands: *Commands) !void {
        if (commands.world.getResource(GameWorld)) |gw| {
            if (gw.entities_created) {
                try commands.insertResource(
                    NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } },
                );
                try commands.insertResource(PhaseEvent{ .message = "Returned to Playing" });
            }
        }
    }
};

const GameWorld = struct {
    entities_created: bool,
};

const PhaseEvent = struct {
    message: []const u8,
};

const TransitionTracker = struct {
    events: std.ArrayListUnmanaged([]const u8) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) TransitionTracker {
        return .{ .allocator = alloc };
    }
    pub fn deinit(self: *TransitionTracker) void {
        self.events.deinit(self.allocator);
    }
};

test "phases transition full round trip (deterministic)" {
    const alloc = std.testing.allocator;
    var app = try App.default(alloc);
    defer app.deinit();

    var tracker = TransitionTracker.init(alloc);
    defer tracker.deinit();
    try app.insertResource(tracker);

    try app.addPlugin(PhasesPluginImpl{});

    // Process initial NextPhase -> MainMenu.enter
    try app.runSchedulesFrom("BetweenFrames");

    // Manually drive transitions (NO Update in between):
    // MainMenu -> InGame.Playing
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Playing -> InGame.Paused
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Paused = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Paused -> InGame.Playing
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Playing -> InGame.Paused
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Paused = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Paused -> MainMenu
    try app.insertResource(NextPhase{ .phase = Phases{ .MainMenu = .{} } });
    try app.runSchedulesFrom("BetweenFrames");

    const expected = [_][]const u8{
        "MainMenu.enter",
        "MainMenu.exit",
        "InGame.enter",
        "Playing.enter",
        "Playing.exit",
        "Paused.enter",
        "Paused.exit",
        "Playing.enter",
        "Playing.exit",
        "Paused.enter",
        "Paused.exit",
        "InGame.exit",
        "MainMenu.enter",
    };

    const got = app.world.getResource(TransitionTracker).?.events.items;
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, 0..) |e, i| {
        try std.testing.expectEqualStrings(e, got[i]);
    }
}

test "GameWorld persists inside InGame" {
    const alloc = std.testing.allocator;
    var app = try App.default(alloc);
    defer app.deinit();

    try app.addPlugin(PhasesPluginImpl{});

    // Enter MainMenu
    try app.runSchedulesFrom("BetweenFrames");

    // MainMenu -> InGame.Playing (manual), then run Update once to create entities
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");
    try app.runSchedulesFrom("Update");

    // InGame.Playing -> InGame.Paused (manual)
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Paused = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Paused -> InGame.Playing (manual)
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    try std.testing.expect(app.world.hasResource(GameWorld));
    try std.testing.expect(app.world.getResource(GameWorld).?.entities_created);
}

test "PhaseEvents include InGame enter/exit" {
    const alloc = std.testing.allocator;
    var app = try App.default(alloc);
    defer app.deinit();

    try app.addPlugin(PhasesPluginImpl{});

    // Enter MainMenu
    try app.runSchedulesFrom("BetweenFrames");

    // MainMenu -> InGame.Playing
    try app.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    try app.runSchedulesFrom("BetweenFrames");

    // InGame.Playing -> MainMenu
    try app.insertResource(NextPhase{ .phase = Phases{ .MainMenu = .{} } });
    try app.runSchedulesFrom("BetweenFrames");

    try std.testing.expect(app.world.hasResource(PhaseEvent));
}
