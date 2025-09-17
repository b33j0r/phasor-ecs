const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const Entity = phasor_ecs.Entity;
const Query = phasor_ecs.Query;
const Res = phasor_ecs.Res;
const ResMut = phasor_ecs.ResMut;
const PhasesPlugin = phasor_ecs.PhasesPlugin;
const PhaseContext = phasor_ecs.PhaseContext;
const Schedule = phasor_ecs.Schedule;
const Exit = phasor_ecs.Exit;

const Phases = union(enum) {
    MainMenu: MainMenu,
    InGame: InGame,
};

const PhasesPluginImpl = PhasesPlugin(Phases, Phases.MainMenu);
const CurrentPhase = PhasesPluginImpl.CurrentPhase;
const NextPhase = PhasesPluginImpl.NextPhase;

const MainMenu = struct {
    pub fn enter(_: *MainMenu, ctx: *PhaseContext) !void {
        try ctx.addUpdateSystem(MainMenu.transition_to_next);
    }
    fn transition_to_next(commands: *Commands) !void {
        try commands.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Playing = .{} } } });
    }
};

const InGame = union(enum) {
    Playing: Playing,
    Paused: Paused,
};

const Playing = struct {
    pub fn enter(_: *Playing, ctx: *PhaseContext) !void {
        try ctx.addUpdateSystem(Playing.check_for_pause);
    }
    fn check_for_pause(commands: *Commands) !void {
        // For testing purposes, we transition to Paused immediately
        try commands.insertResource(NextPhase{ .phase = Phases{ .InGame = .{ .Paused = .{} } } });
    }
};

const Paused = struct {
    pub fn enter(_: *Paused, ctx: *PhaseContext) !void {
        // Again for testing purposes, we exit the app immediately
        try ctx.world.insertResource(Exit{ .code = 0 });
    }
};

test "PhasePlugin transitions" {
    const allocator = std.testing.allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    try app.addPlugin(PhasesPluginImpl{});

    try app.step();
    try app.runSchedulesFrom("BetweenFrames");
    try std.testing.expect(!app.world.hasResource(Exit));

    try app.step();
    try app.runSchedulesFrom("BetweenFrames");
    try std.testing.expect(!app.world.hasResource(Exit));

    try app.step();
    try app.runSchedulesFrom("BetweenFrames");
    const exit_res = app.world.getResource(Exit).?;
    try std.testing.expect(exit_res.code == 0);
}
