/// A generic actor that runs `work_fn` on a background thread. It communicates
/// with the outside world via two channels: an inbox and an outbox. After calling
/// `spawn()`, the user gets an `ActorHandle` which contains the user-side
/// endpoints of the channels.
pub fn Actor(comptime ContextT: type, comptime InboxT: type, comptime OutboxT: type) type {
    // Sanity checks on ContextT
    if (ContextT == void) {
        @compileError("ContextT cannot be void, it provides the `work` method");
    }
    // Check for a work method on ContextT
    if (!@hasDecl(ContextT, "work")) {
        @compileError("ContextT must have a `work` method");
    }
    const work_fn = ContextT.work;
    if (@typeInfo(@TypeOf(work_fn)) != .@"fn") {
        @compileError("ContextT.work must be a function");
    }

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        pub const ActorHandle = struct {
            inbox: Channel(InboxT).Sender,
            outbox: Channel(OutboxT).Receiver,
            thread: std.Thread,

            pub fn deinit(self: *ActorHandle) void {
                // Graceful shutdown
                self.inbox.close();
                self.outbox.close();
                self.thread.join();
                self.inbox.deinit();
                self.outbox.deinit();
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn spawn(self: *Self, ctx_or_ptr: anytype, inbox_capacity: usize, outbox_capacity: usize) !ActorHandle {
            // ctx must be a pointer to ContextT or a ContextT itself
            const ctx: *ContextT = ctx_block: switch (@typeInfo(@TypeOf(ctx_or_ptr))) {
                .pointer => {
                    break :ctx_block ctx_or_ptr;
                },
                .@"struct" => {
                    break :ctx_block @constCast(&ctx_or_ptr);
                },
                else => @compileError("ctx must be a pointer to ContextT or a ContextT itself"),
            };
            // Create channels
            var in_pair = try Channel(InboxT).create(self.allocator, inbox_capacity);
            errdefer {
                in_pair.sender.deinit();
                in_pair.receiver.deinit();
            }

            var out_pair = try Channel(OutboxT).create(self.allocator, outbox_capacity);
            errdefer {
                out_pair.sender.deinit();
                out_pair.receiver.deinit();
            }

            const th = try std.Thread.spawn(.{}, workerMain, .{ ctx, in_pair.receiver, out_pair.sender });

            return .{
                .inbox = in_pair.sender, // user sends to actor
                .outbox = out_pair.receiver, // user receives from actor
                .thread = th,
            };
        }

        fn workerMain(
            ctx: *ContextT,
            c_inbox: Channel(InboxT).Receiver,
            c_outbox: Channel(OutboxT).Sender,
        ) void {
            var inbox = @constCast(&c_inbox);
            var outbox = @constCast(&c_outbox);
            ctx.work(inbox, outbox);
            // Signal EOF and drop worker-owned endpoints
            outbox.close();
            outbox.deinit();
            inbox.deinit();
        }
    };
}

// Imports
const std = @import("std");

const phasor_channel = @import("phasor-channel");
const Channel = phasor_channel.Channel;
