const std = @import("std");

// External channel module
const channel_mod = @import("phasor-channel");
const Channel = channel_mod.Channel;

/// Errors you may see on the user side.
pub const ActorError = error{
    Stopped,
    InboxClosed,
    OutboxClosed,
    InboxSendFailed,
    OutboxSendFailed,
    ChannelClosed,
};

/// Control wrapper for inbox messages (user -> actor thread)
fn InboxMessage(comptime T: type) type {
    return union(enum) {
        message: T,
        stop,
    };
}

/// Status/message wrapper for outbox messages (actor thread -> user)
fn OutboxMessage(comptime T: type) type {
    return union(enum) {
        message: T,
        stopped,
    };
}

/// Spawn options (capacities, etc.)
pub const ActorOptions = struct {
    inbox_capacity: usize = 1024,
    outbox_capacity: usize = 1024,
};

/// Actor(InboxT, OutboxT) => type that can spawn a worker thread which:
/// - receives InboxT from the user via an inbox channel
/// - lets your worker write OutboxT back via `Outbox`
///
/// Worker contract:
///   pub fn step(ctx: *@This(), cmd: *InboxT, outbox: *DoublerActor.Outbox) void
///
/// Lifecycle (user side):
///   - `send(cmd)` to enqueue work
///   - `recv()` to get responses (blocks until a OutboxT arrives)
///   - `waitForStop(ms)` to request a graceful stop and join the thread
///
/// IMPORTANT: The actor **borrows** the worker context. The caller must keep the
/// context alive until after `waitForStop` returns.
pub fn Actor(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        allocator: std.mem.Allocator,

        const Self = @This();

        const InternalInboxT = InboxMessage(InboxT);
        const InternalOutboxT = OutboxMessage(OutboxT);

        const InboxChannel = Channel(InternalInboxT);
        const OutboxChannel = Channel(InternalOutboxT);

        // An interface for sending to the outbox from inside a `step` function.
        pub const Outbox = struct {
            internal_outbox: *OutboxChannel.Sender,

            /// Send a message to the outbox (actor -> user).
            pub fn send(self: *Outbox, msg: OutboxT) !void {
                self.internal_outbox.send(.{ .message = msg }) catch {
                    return ActorError.OutboxSendFailed;
                };
            }
        };

        /// User handle: endpoints + thread.
        pub const Handle = struct {
            allocator: std.mem.Allocator,

            // user endpoints
            inbox: InboxChannel.Sender,
            outbox: OutboxChannel.Receiver,

            // thread
            thread: std.Thread,

            /// Send a command to the actor.
            pub fn send(self: *Handle, cmd: InboxT) !void {
                self.inbox.send(.{ .message = cmd }) catch {
                    return ActorError.InboxSendFailed;
                };
            }

            /// Blocking receive of a `OutboxT`.
            /// Skips `.stopped` notices so you can drain replies first.
            /// Panics if outbox closes without a message (programming error in happy path).
            pub fn recv(self: *Handle) !OutboxT {
                while (true) {
                    const next = self.outbox.next() orelse {
                        return ActorError.OutboxClosed;
                    };
                    switch (next) {
                        .message => |m| return m,
                        .stopped => {
                            return ActorError.Stopped;
                        },
                    }
                }
            }

            /// Ask the actor to stop and (best-effort) wait for it to acknowledge.
            /// Sends `.stop`, waits up to `timeout_ms` for `.stopped`, then joins.
            /// Regardless of timeout, we join and close/deinit the endpoints.
            pub fn waitForStop(self: *Handle, timeout_ms: u64) !void {
                // Best-effort: if the inbox is already closed, just proceed to join
                _ = self.inbox.send(.{ .stop = {} }) catch {};

                const start_ms = std.time.milliTimestamp();
                var saw_stopped = false;

                while (true) {
                    if (timeout_ms > 0) {
                        const now = std.time.milliTimestamp();
                        if (now - start_ms > timeout_ms) {
                            break;
                        }
                    }

                    if (self.outbox.next()) |msg| {
                        switch (msg) {
                            .message => {
                                // Late reply racing with stop; ignore during shutdown
                            },
                            .stopped => {
                                saw_stopped = true;
                                break;
                            },
                        }
                    } else {
                        // Outbox closed without explicit `.stopped`—proceed
                        break;
                    }

                    // Small yield to avoid busy spin if worker is unwinding
                    std.Thread.sleep(200_000); // 0.2 ms
                }

                // Join worker thread (no matter what)
                self.thread.join();

                // Close + deinit user endpoints
                self.inbox.close();
                self.outbox.close();
                self.inbox.deinit();
                self.outbox.deinit();
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Spawn a worker thread.
        ///
        /// `context_ptr` MUST be a pointer to a caller-owned context (borrowed).
        /// The context must outlive the actor until `waitForStop` returns.
        pub fn spawn(
            self: *Self,
            context_ptr: anytype,
            options: ActorOptions,
        ) !Handle {
            const info = @typeInfo(@TypeOf(context_ptr));
            if (info != .pointer) {
                @compileError("Actor.spawn requires a pointer to context (borrowed). Use: var ctx = Worker{}; try spawn(&ctx, ...) ");
            }
            const ContextT = info.pointer.child;

            // Channels
            var in_pair = try InboxChannel.create(self.allocator, options.inbox_capacity);
            errdefer {
                in_pair.sender.deinit();
                in_pair.receiver.deinit();
            }

            var out_pair = try OutboxChannel.create(self.allocator, options.outbox_capacity);
            errdefer {
                out_pair.sender.deinit();
                out_pair.receiver.deinit();
            }

            // Start thread
            const th = try std.Thread.spawn(.{}, workerMain(ContextT), .{
                context_ptr,
                in_pair.receiver,
                out_pair.sender,
            });

            return .{
                .allocator = self.allocator,
                .inbox = in_pair.sender,
                .outbox = out_pair.receiver,
                .thread = th,
            };
        }

        /// Per-ContextT worker main, so we can call ctx.step without runtime anytype.
        fn workerMain(comptime ContextT: type) fn (*ContextT, InboxChannel.Receiver, OutboxChannel.Sender) void {
            return struct {
                fn run(
                    ctx: *ContextT,
                    inbox_recv: Channel(InternalInboxT).Receiver,
                    outbox_send: Channel(InternalOutboxT).Sender,
                ) void {
                    var inbox_receiver = @constCast(&inbox_recv);
                    var outbox_sender = @constCast(&outbox_send);
                    var outbox = Outbox{ .internal_outbox = outbox_sender };

                    // Dispatch loop
                    while (inbox_receiver.next()) |msg| {
                        switch (msg) {
                            .message => |m| {
                                ContextT.step(ctx, &m, &outbox);
                            },
                            .stop => {
                                break;
                            },
                        }
                    }

                    // Stop receiving messages
                    inbox_receiver.close();

                    // Send the stopped message
                    _ = outbox_sender.send(.{ .stopped = {} }) catch {};

                    // Close the outbox
                    outbox_sender.close();

                    // Deinit thread-owned endpoints
                    inbox_receiver.deinit();
                    outbox_sender.deinit();
                }
            }.run;
        }
    };
}
