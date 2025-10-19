/// A stack of PhaseContexts, one per active phase level (root..leaf)
pub fn PhaseContextStack(PhasesT: type) type {
    return struct {
        allocator: std.mem.Allocator,
        stack: std.ArrayListUnmanaged(*PhaseContext) = .empty,
        app: *App,

        pub const Phases = PhasesT;
        const Self = @This();

        pub fn init(alloc: std.mem.Allocator, app: *App) !Self {
            return .{ .allocator = alloc, .app = app };
        }

        pub fn deinit(self: *Self) void {
            var i: usize = self.stack.items.len;
            while (i > 0) {
                i -= 1;
                const ctx = self.stack.items[i];
                ctx.deinit();
                self.allocator.destroy(ctx);
            }
            self.stack.deinit(self.allocator);
        }

        pub fn push(self: *Self) !*PhaseContext {
            const ctx = try self.allocator.create(PhaseContext);
            errdefer self.allocator.destroy(ctx);
            ctx.* = try PhaseContext.init(self.allocator, self.app);
            try self.stack.append(self.allocator, ctx);
            return ctx;
        }

        pub fn pop(self: *Self) ?*PhaseContext {
            if (self.stack.items.len == 0) return null;
            return self.stack.pop();
        }

        pub fn top(self: *Self) ?*PhaseContext {
            if (self.stack.items.len == 0) return null;
            return self.stack.items[self.stack.items.len - 1];
        }

        pub fn depth(self: *const Self) usize {
            return self.stack.items.len;
        }

        pub fn forEach(self: *Self, f: *const fn (*PhaseContext, *World) anyerror!void, world: *World) !void {
            for (self.stack.items) |ctx| try f(ctx, world);
        }

        pub fn forEachReverse(self: *Self, f: *const fn (*PhaseContext, *World) anyerror!void, world: *World) !void {
            var i = self.stack.items.len;
            while (i > 0) {
                i -= 1;
                try f(self.stack.items[i], world);
            }
        }
    };
}

// Imports
const std = @import("std");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const World = phasor_ecs.World;

const PhaseContext = @import("PhaseContext.zig");
