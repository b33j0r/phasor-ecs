# phasor-ecs

A flexible Entity Component System (ECS) framework for Zig applications, with a focus on game development.

`phasor-ecs` provides a structured way to organize your game or application logic using the ECS architectural pattern. It is built on top of
`phasor-db` (entity-component database) and `phasor-graph` (graph library for dependency resolution).

**Important:** `phasor-ecs` is not a game engine. It provides the ECS framework which combines a database with schedules and systems. For a
complete game engine, see `phasor` (not yet released).

## Features

- **Entity Component System**: Organize your game data and logic with entities, components, and systems
- **Flexible scheduling**: Define execution order with dependency-based schedules
- **Command system**: Safely modify entities and components from systems with deferred execution
- **Resource management**: Global data access with type-safe resources
- **Event system**: Communication between systems with event publishers and subscribers
- **Plugin architecture**: Extend your application with modular, reusable plugins
- **Phase system**: Manage game states with a structured phase transition system

## Installation

### Using Zig's Package Manager

Add `phasor-ecs` to your `build.zig.zon` file by fetching it:

```shell
zig fetch --save git+https://github.com/b33j0r/phasor-ecs
```

And add it to your `build.zig`:

```zig
const phasor_ecs_dep = b.dependency("phasor_ecs", .{});
const phasor_ecs_mod = phasor_ecs_dep.module("phasor-ecs");

const exe = b.addExecutable(.{
    .name = "your-app-name",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "phasor-ecs", .path = .{ .id = phasor_ecs_mod.id } },
    },
});
```

## Basic Usage

Here's a minimal example showing how to use phasor-ecs:

```zig
const std = @import("std");
const phasor = @import("phasor-ecs");

// Define components
const Position = struct {
    x: f32,
    y: f32,
};

const Direction = struct {
    x: f32,
    y: f32,
};

// Define a system
fn moveEntitiesSystem(query: phasor.Query(.{Position, Direction})) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        var position = entity.getMut(Position).?;
        const direction = entity.get(Direction).?;

        position.x += direction.x;
        position.y += direction.y;
    }
}

// Define a resource
const GameConfig = struct {
    move_speed: f32,
};

// Define a system that uses a resource
fn speedSystem(
    query: phasor.Query(.{Direction}),
    config: phasor.Res(GameConfig),
) !void {
    const speed = config.move_speed;
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        var direction = entity.getMut(Direction).?;

        // Normalize and apply speed
        const length = @sqrt(direction.x * direction.x + direction.y * direction.y);
        if (length > 0.001) {
            direction.x = direction.x / length * speed;
            direction.y = direction.y / length * speed;
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // Create an app with default schedules
    var app = try phasor.App.default(allocator);
    defer app.deinit();

    // Add a resource
    try app.world.insertResource(GameConfig{ .move_speed = 5.0 });

    // Add systems to the Update schedule
    try app.addSystem("Update", moveEntitiesSystem);
    try app.addSystem("Update", speedSystem);

    // Create entities with components
    var commands = app.world.commands();
    defer commands.deinit();

    _ = try commands.createEntity(.{
        Position{ .x = 0, .y = 0 },
        Direction{ .x = 1, .y = 0 },
    });

    _ = try commands.createEntity(.{
        Position{ .x = 10, .y = 10 },
        Direction{ .x = 0, .y = 1 },
    });

    try commands.apply();

    // Run a single frame
    try app.step();
}
```

## Core Concepts

### Entities and Components

Entities are lightweight identifiers that represent game objects.
Components are plain data structures that hold the actual data. Entities
can have multiple components attached to them.

```zig
// Define some components
const Tag = struct {};
const Counter = struct { value: i32 };
const Metadata = struct { name: []const u8 };

// Create an entity with multiple components
const entity_id = try commands.createEntity(.{
    Tag{},
    Counter{ .value = 0 },
    Metadata{ .name = "Entity 1" },
});
```

### Systems

Systems contain the logic that operates on entities and their components.
They are organized by schedules and run based on the schedule's
execution order.

```zig
// System that counts entities with a Tag component
fn countTaggedEntities(
    query: phasor.Query(.{Tag}),
    counter: phasor.ResMut(GlobalCounter),
) !void {
    counter.value = @intCast(query.count());
}

// System that increments all Counter components
fn incrementCounters(query: phasor.Query(.{Counter})) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        var counter = entity.getMut(Counter).?;
        counter.value += 1;
    }
}
```

### World and Resources

The World manages entities, components, and resources. Resources
are global data objects that systems can access.

```zig
// Define a resource
const GlobalCounter = struct { value: u32 };

// Add the resource to the world
try world.insertResource(GlobalCounter{ .value = 0 });

// Access the resource in a system
fn displayCounterSystem(counter: phasor.Res(GlobalCounter)) !void {
std.debug.print("Count: {}\n", .{counter.value});
}
```

### Schedules

Schedules organize systems into logical groups and control their
execution order. The default schedules include:

- `PreStartup`, `Startup`, `PostStartup` - Run once at app initialization
- `BeginFrame`, `Update`, `Render`, `EndFrame` - Run each frame
- `BetweenFrames` - Run between frames
- `PreShutdown`, `Shutdown`, `PostShutdown` - Run when app is shutting down

```zig
// Add a custom schedule
_ = try app.addSchedule("Initialize");

// Define execution order
try app.scheduleAfter("Initialize", "BeginFrame");
try app.scheduleBefore("Initialize", "Update");

// NOTE and TODO
// The schedule graph currently does a DFS from a root node
// like "BeginFrame", so it's important that you add an edge
// reachable in the path from this root. "After" edges are
// currently implemented as flipped "Before" edges.

// Add a system to the schedule
try app.addSystem("Initialize", setupSystem);
```

## Advanced Features

### Commands

Commands provide a way to safely modify entities and components from systems through deferred execution:

```zig
fn spawnEntitiesSystem(commands: *phasor.Commands) !void {
    // Create a new entity
    const entity_id = try commands.createEntity(.{
        Counter{ .value = 0 },
    });

    // Add components to an existing entity
    try commands.addComponents(entity_id, .{
        Metadata{ .name = "Dynamic Entity" },
    });

    // Remove an entity
    try commands.removeEntity(other_entity_id);
}
```

### Scoped Commands

Scoped commands allow you to add a component to all entities created within a scope:

```zig
fn spawnGroupedEntities(commands: *phasor.Commands) !void {
    const Group = struct { };

    // Create a scope that adds the Group component to all entities
    var group_commands = try commands.scoped(Group);

    // All entities created with group_commands will have the Group component
    _ = try group_commands.createEntity(.{
        Counter{ .value = 0 },
    });

    _ = try group_commands.createEntity(.{
        Counter{ .value = 10 },
    });
}
```

### Events

The event system allows communication between systems:

```zig
// Define an event type
const CounterEvent = struct {
    entity_id: phasor.Entity,
    old_value: i32,
    new_value: i32,
};

// Register the event type in your initialization code
pub fn init(app: *phasor.App) !void {
    // Register event with a capacity of 16
    try app.registerEvent(CounterEvent, 16);
}

// Send events
fn detectCounterChanges(
    query: phasor.Query(.{Counter}),
    writer: phasor.EventWriter(CounterEvent),
) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        const counter = entity.get(Counter).?;
        if (counter.value > 100) {
            try writer.send(CounterEvent{
                .entity_id = entity.id,
                .old_value = counter.value,
                .new_value = 0, // Reset planned
            });
        }
    }
}

// Receive and process events
fn handleCounterEvents(
    commands: *phasor.Commands,
    reader: phasor.EventReader(CounterEvent),
) !void {
    while (try reader.tryRecv()) |event| {
        // Reset counter when it exceeds threshold
        try commands.addComponents(event.entity_id, .{
            Counter{ .value = event.new_value },
        });
    }
}
```

### Queries

Queries allow you to efficiently access entities with specific component combinations:

```zig
// Basic query for entities with both components
fn basicQuerySystem(
    query: phasor.Query(.{Counter, Metadata})
) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        const counter = entity.get(Counter).?;
        const metadata = entity.get(Metadata).?;
        std.debug.print("{s}: {}\n", .{metadata.name, counter.value});
    }
}

// Query with exclusion - entities with Counter but without Tag
fn exclusionQuerySystem(
    query: phasor.Query(.{Counter, phasor.Without(Tag)})
) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        const counter = entity.get(Counter).?;
        std.debug.print("Untagged counter: {}\n", .{counter.value});
    }
}
```

## Plugin Architecture

Plugins allow you to encapsulate and reuse functionality across applications:

```zig
const CounterPlugin = struct {
    // Optional: name for the plugin (defaults to struct name)
    pub const name = "CounterPlugin";

    // Optional: whether only one instance of this plugin can be added (defaults to true)
    pub const is_unique = true;

    // Required: build function that sets up the plugin
    pub fn build(self: *CounterPlugin, app: *phasor.App) !void {
        // Register resources
        try app.world.insertResource(GlobalCounter{ .value = 0 });

        // Add systems
        try app.addSystem("Update", countTaggedEntities);
        try app.addSystem("Update", incrementCounters);
        try app.addSystem("Update", displayCounterSystem);
    }

    // Optional: cleanup function called when app is shutting down
    pub fn cleanup(self: *CounterPlugin, app: *phasor.App) void {
        // Clean up resources if needed
    }
};

// In your main function
pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var app = try phasor.App.default(allocator);
    defer app.deinit();

    // Add the plugin to your app
    try app.addPlugin(CounterPlugin{});

    try app.run();
}
```

### Phase System

The phase system helps manage game states and transitions:

```zig
// Define your application phases
const AppPhases = union(enum) {
    MainMenu: MainMenu,
    Game: Game,
    Pause: Pause,
};

// Create a plugin that manages these phases
const AppPhasesPlugin = phasor.PhasesPlugin(AppPhases, AppPhases.MainMenu);

// Define phase behavior
const MainMenu = struct {
    pub fn enter(self: *MainMenu, ctx: *phasor.PhaseContext) !void {
        try ctx.addUpdateSystem(MainMenu.handleInput);
    }

    fn handleInput(commands: *phasor.Commands) !void {
        // In a real app, you'd check for user input
        // For this example, just transition to game phase
        try commands.insertResource(AppPhasesPlugin.NextPhase{
            .phase = AppPhases{ .Game = .{} }
        });
    }
};

const Game = struct {
    pub fn enter(self: *Game, ctx: *phasor.PhaseContext) !void {
        try ctx.addUpdateSystem(Game.update);
    }

    fn update(commands: *phasor.Commands) !void {
        // Game logic
        // When appropriate, transition to pause
        if (shouldPause()) {
            try commands.insertResource(AppPhasesPlugin.NextPhase{
                .phase = AppPhases{ .Pause = .{} }
            });
        }
    }

    fn shouldPause() bool {
        return true; // Just for demonstration
    }
};

const Pause = struct {
    pub fn enter(self: *Pause, ctx: *phasor.PhaseContext) !void {
        try ctx.addUpdateSystem(Pause.handleInput);
    }

    fn handleInput(commands: *phasor.Commands) !void {
        // When appropriate, transition back to game
        try commands.insertResource(AppPhasesPlugin.NextPhase{
            .phase = AppPhases{ .Game = .{} }
        });
    }
};

// In your initialization code
try app.addPlugin(AppPhasesPlugin{});
```

## Example: Simple Counter

This example shows a complete application using phasor-ecs to create a simple counter system:

```zig
const std = @import("std");
const phasor = @import("phasor-ecs");
const App = phasor.App;
const Commands = phasor.Commands;
const Query = phasor.Query;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const Exit = phasor.Exit;

// Component for counter entities
const Counter = struct { value: i32 };

// Resource for tracking max counter value
const MaxCounter = struct { value: i32 };

// Resource for control
const IterationCount = struct {
    current: i32,
    max: i32,
};

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    // Add startup system to initialize entities
    try app.addSystem("Startup", initializeEntities);

    // Add update systems
    try app.addSystem("Update", incrementCounters);
    try app.addSystem("Update", trackMaxCounter);
    try app.addSystem("Update", checkIteration);

    // Add resources
    try app.world.insertResource(MaxCounter{ .value = 0 });
    try app.world.insertResource(IterationCount{ .current = 0, .max = 5 });

    return try app.run();
}

fn initializeEntities(commands: *Commands) !void {
    // Create three counter entities with different starting values
    _ = try commands.createEntity(.{Counter{ .value = 0 }});
    _ = try commands.createEntity(.{Counter{ .value = 5 }});
    _ = try commands.createEntity(.{Counter{ .value = 10 }});
}

fn incrementCounters(query: Query(.{Counter})) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        var counter = entity.getMut(Counter).?;
        counter.value += 1;
        std.debug.print("Counter: {}\n", .{counter.value});
    }
}

fn trackMaxCounter(
    query: Query(.{Counter}),
    max_counter: ResMut(MaxCounter),
) !void {
    var iterator = query.iterator();
    while (iterator.next()) |entity| {
        const counter = entity.get(Counter).?;
        if (counter.value > max_counter.value) {
            max_counter.value = counter.value;
        }
    }
    std.debug.print("Max counter: {}\n", .{max_counter.value});
}

fn checkIteration(
    iter: ResMut(IterationCount),
    commands: *Commands
) !void {
    iter.current += 1;
    std.debug.print("Iteration: {}/{}\n", .{iter.current, iter.max});

    if (iter.current >= iter.max) {
        std.debug.print("Reached max iterations, exiting...\n", .{});
        try commands.insertResource(Exit{ .code = 0 });
    }
}
```

## API Reference

### Core Types

- `App`: Main application container
- `World`: Entity and resource storage
- `Entity`: Identifier for game objects
- `Schedule`: Container for systems with defined execution order
- `ScheduleManager`: Manages schedules and their dependencies
- `System`: Logic that operates on entities and components
- `Plugin`: Modular extension for applications

### Resource Management

- `ResourceManager`: Stores and retrieves global resources
- `Res(T)`: Read-only access to a resource of type T
- `ResMut(T)`: Read-write access to a resource of type T
- `ResOpt(T)`: Optional read-only access to a resource of type T

### Entity Commands

- `Commands`: Deferred command execution for entity operations
- `CommandBuffer`: Low-level command queue
- `Scoped`: Commands that add a component to all created entities

### Events

- `Events(T)`: Storage for events of type T
- `EventReader(T)`: Reads events of type T
- `EventWriter(T)`: Writes events of type T

### Queries

- `Query(.{...})`: Query entities with specific component combinations
- `GroupBy(T)`: Group query results by a component trait
- `Without(T)`: Exclude entities with component T from query results

### Traits

Traits are a powerful feature that allows you to categorize and group components by shared characteristics. Unlike traditional component hierarchies, traits provide a flexible way to establish relationships between components that share common behaviors or properties.

- **Component Trait Implementation**: Components can implement traits by defining specific fields:
  - `__trait__`: Identifies the trait type the component belongs to
  - `__group_key__`: Specifies a value for grouping components with the same trait

- **GroupBy System Parameter**: The `GroupBy(TraitT)` system parameter provides an efficient way to process entities grouped by a shared trait

- **Use Cases**: Traits are ideal for:
  - Processing entities with similar behaviors but different component types
  - Implementing polymorphic behavior in an ECS architecture
  - Creating modular, extensible component systems

#### Example:

```zig
// Define a trait for components that can be damaged
const Damageable = struct {};

// Components implementing the Damageable trait
const Wood = struct {
    health: i32,
    
    // Trait implementation
    pub const __trait__ = Damageable;
    pub const __group_key__ = 1; // Wood group
};

const Stone = struct {
    health: i32,
    
    // Trait implementation
    pub const __trait__ = Damageable;
    pub const __group_key__ = 2; // Stone group
};

// System that processes all Damageable components by group
fn processDamage(groups: GroupBy(Damageable)) !void {
    var iterator = groups.iterator();
    
    while (iterator.next()) |group| {
        const group_key = group.key;
        
        // Process entities in each damage group differently
        if (group_key == 1) { // Wood
            // Process wood entities...
            var entity_iter = group.entities.iterator();
            while (entity_iter.next()) |entity| {
                var wood = entity.getMut(Wood).?;
                wood.health -= 5; // Wood takes more damage
            }
        } else if (group_key == 2) { // Stone
            // Process stone entities...
            var entity_iter = group.entities.iterator();
            while (entity_iter.next()) |entity| {
                var stone = entity.getMut(Stone).?;
                stone.health -= 1; // Stone takes less damage
            }
        }
    }
}
```


### Phases

- `PhasesPlugin(T, start)`: Create a plugin that manages phase transitions
- `PhaseContext`: Context provided to phases for setup

## License

Check the [LICENSE](LICENSE) file for details.

---

phasor-ecs v0.2.0