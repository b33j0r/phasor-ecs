pub const db = @import("phasor-db");
pub const Entity = db.Entity;
pub const Without = db.Without;

pub const graph = @import("phasor-graph");

pub const App = @import("App.zig");
pub const Exit = App.Exit;

pub const CommandBuffer = @import("CommandBuffer.zig");
pub const Command = @import("Command.zig");
pub const Plugin = @import("Plugin.zig");
pub const ResourceManager = @import("ResourceManager.zig");
pub const Schedule = @import("Schedule.zig");
pub const ScheduleManager = @import("ScheduleManager.zig");
pub const System = @import("System.zig");
pub const World = @import("World.zig");

const subapp_mod = @import("subapp.zig");
pub const SubApp = subapp_mod.SubApp;

const events = @import("events.zig");
pub const Events = events.Events;
pub const EventReader = events.EventReader;
pub const EventWriter = events.EventWriter;


pub const Commands = @import("Commands.zig");
pub const Scoped = Commands.Scoped;

const systems_mod = @import("systems.zig");
pub const Res = systems_mod.Res;
pub const ResMut = systems_mod.ResMut;
pub const ResOpt = systems_mod.ResOpt;
pub const Query = systems_mod.Query;
pub const GroupBy = systems_mod.GroupBy;

const phasor_actor = @import("phasor-actor");
pub const Actor = phasor_actor.Actor;
pub const Signal = phasor_actor.Signal;

comptime {
    // Ensure that the dependencies are seen by the semantic analyzer
    _ = db;
    _ = graph;
    _ = App;
    _ = CommandBuffer;
    _ = Commands;
    _ = Plugin;
    _ = ResourceManager;
    _ = Schedule;
    _ = ScheduleManager;
    _ = System;
    _ = World;
    _ = systems_mod;
}
