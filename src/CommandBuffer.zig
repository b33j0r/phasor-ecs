allocator: std.mem.Allocator,
commands: std.ArrayListUnmanaged(Command) = .empty,

const std = @import("std");
const root = @import("root.zig");
const Command = root.Command;

const CommandBuffer = @This();

pub fn init(allocator: std.mem.Allocator) CommandBuffer {
    return CommandBuffer{
        .allocator = allocator,
        .commands = .empty,
    };
}

pub fn deinit(self: *CommandBuffer) void {
    // Clean up any remaining commands
    for (self.commands.items) |*cmd| {
        cmd.cleanup();
    }
    self.commands.deinit(self.allocator);
}

pub fn queue(self: *CommandBuffer, cmd: Command) !void {
    try self.commands.append(self.allocator, cmd);
}

pub fn queueContext(self: *CommandBuffer, context: anytype) !void {
    const cmd = try Command.from(self.allocator, context);
    try self.queue(cmd);
}

pub fn flush(self: *CommandBuffer, world: *root.World) !void {
    for (self.commands.items) |*cmd| {
        try cmd.execute(world);
        cmd.cleanup();
    }
    self.commands.clearRetainingCapacity();
}
