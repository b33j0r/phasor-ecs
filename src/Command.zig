//! A type-erased command that can be queued in a CommandBuffer.
allocator: std.mem.Allocator,
ptr: *anyopaque,
vtable: ErasedVTable,

const std = @import("std");
const root = @import("root.zig");

const Command = @This();

const ErasedVTable = struct {
    execute: *const fn (ctx: *anyopaque, world: *root.World) anyerror!void,
    // Optional user cleanup; Command will always destroy the context allocation after this
    cleanup: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
    // Required destructor to free the allocated context of unknown T
    destroy: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};

/// Create a Command from a context value.
pub fn from(allocator: std.mem.Allocator, context: anytype) !Command {
    const T = @TypeOf(context);

    const vtable = ErasedVTable{
        .execute = struct {
            fn f(ctx: *anyopaque, world: *root.World) anyerror!void {
                const typed: *T = @ptrCast(@alignCast(ctx));
                try typed.execute(world);
            }
        }.f,
        .cleanup = if (@hasDecl(T, "cleanup"))
            &struct {
                fn f(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                    const typed: *T = @ptrCast(@alignCast(ctx));
                    typed.cleanup(alloc);
                }
            }.f
        else
            null,
        .destroy = struct {
            fn f(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                const typed: *T = @ptrCast(@alignCast(ctx));
                alloc.destroy(typed);
            }
        }.f,
    };

    const ctx_ptr = try allocator.create(T);
    ctx_ptr.* = context;

    return Command{
        .allocator = allocator,
        .ptr = @ptrCast(ctx_ptr),
        .vtable = vtable,
    };
}

pub fn execute(self: *Command, world: *root.World) anyerror!void {
    try self.vtable.execute(self.ptr, world);
}

pub fn cleanup(self: *Command) void {
    if (self.vtable.cleanup) |cl| cl(self.ptr, self.allocator);
    self.vtable.destroy(self.ptr, self.allocator);
}
