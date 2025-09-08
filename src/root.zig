pub const db = @import("phasor-db");
pub const graph = @import("phasor-graph");

pub const App = @import("App.zig");
pub const Plugin = @import("Plugin.zig");
pub const Schedule = @import("Schedule.zig");
pub const ScheduleManager = @import("ScheduleManager.zig");
pub const System = @import("System.zig");
pub const World = @import("World.zig");

const systems_mod = @import("systems.zig");
pub const Res = systems_mod.Res;
pub const Query = systems_mod.Query;
pub const Without = systems_mod.Without;
pub const GroupBy = systems_mod.GroupBy;

const plugins_mod = @import("plugins/mod.zig");
pub const FramePlugin = plugins_mod.FramePlugin;

comptime {
    // Ensure that the dependencies are seen by the semantic analyzer
    _ = db;
    _ = graph;
    _ = systems_mod;
    _ = plugins_mod;
}
