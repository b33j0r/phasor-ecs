/// Errors you may see on the user side.
pub const ActorError = error{
    Stopped, // used here to mean "stop timed out; thread may still be running"
    InboxClosed,
    OutboxClosed,
    InboxSendFailed,
    OutboxSendFailed,
    ChannelClosed,
};

/// Spawn options (capacities, etc.)
pub const ActorOptions = struct {
    inbox_capacity: usize = 1024,
    outbox_capacity: usize = 1024,
    /// Poll sleep in microseconds while waiting for messages or stop.
    poll_sleep_us: u64 = 200, // small but non-zero to avoid busy spin
};

/// Actor(InboxT, OutboxT) => type that can spawn a worker thread which:
/// - receives InboxT from the user via an inbox channel
/// - lets your worker write OutboxT back via `Outbox`
///
/// Worker contract:
///   pub fn step(ctx: *@This(), cmd: *InboxT, outbox: *Outbox) void
///
/// Lifecycle (user side):
///   - `send(cmd)` to enqueue work
///   - `recv()` / `tryRecv()` to read responses
///   - `waitForStop(ms)` to request a graceful stop and join the thread
///
/// IMPORTANT: The actor **borrows** the worker context. The caller must keep the
/// context alive until after `waitForStop` returns.
pub fn Actor(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        allocator: std.mem.Allocator,

        const Self = @This();
        pub const InboxChannel = Channel(InboxT);
        pub const OutboxChannel = Channel(OutboxT);
        const BoolSignal = Signal(bool);

        // An interface for sending to the outbox from inside a `step` function.
        pub const Outbox = struct {
            internal_outbox: *OutboxChannel.Sender,

            /// Send a message to the outbox (actor -> user).
            pub fn send(self: *Outbox, msg: OutboxT) !void {
                self.internal_outbox.send(msg) catch {
                    return ActorError.OutboxSendFailed;
                };
            }
        };

        // An interface for receiving from the inbox inside the worker.
        pub const Inbox = struct {
            internal_inbox: *InboxChannel.Receiver,

            /// Blocking receive of an `InboxT`.
            pub fn recv(self: *Inbox) !InboxT {
                return self.internal_inbox.recv();
            }

            /// Non-blocking receive of an `InboxT`.
            pub fn tryRecv(self: *Inbox) !?InboxT {
                return self.internal_inbox.tryRecv();
            }
        };

        /// User handle: endpoints + thread + signals.
        pub const Handle = struct {
            allocator: std.mem.Allocator,

            // user endpoints
            inbox: InboxChannel.Sender,
            outbox: OutboxChannel.Receiver,

            // thread
            thread: std.Thread,

            // signals
            shutdown: BoolSignal,
            stopped: BoolSignal,

            opts: ActorOptions,

            /// Send a command to the actor.
            pub fn send(self: *Handle, msg: InboxT) !void {
                self.inbox.send(msg) catch {
                    return ActorError.InboxSendFailed;
                };
            }

            /// Blocking receive of an `OutboxT`.
            pub fn recv(self: *Handle) !OutboxT {
                return self.outbox.recv();
            }

            /// Non-blocking receive of an `OutboxT`.
            pub fn tryRecv(self: *Handle) !?OutboxT {
                return self.outbox.tryRecv();
            }

            /// Ask the actor to stop and (best-effort) wait for it to exit.
            /// Sets the shutdown flag and waits up to `timeout_ms`.
            /// If it exits in time, joins the thread and returns.
            /// If not, returns `error.Stopped` (thread may still be running).
            pub fn waitForStop(self: *Handle, timeout_ms: u64) !void {
                // Request shutdown
                self.shutdown.set(true);

                const start_ns = std.time.nanoTimestamp();
                const budget_ns: i128 = @as(i128, @intCast(timeout_ms)) * std.time.ns_per_ms;

                // Poll the stopped signal
                while (!self.stopped.get()) {
                    // Time check
                    const elapsed = std.time.nanoTimestamp() - start_ns;
                    if (elapsed >= budget_ns) {
                        return ActorError.Stopped; // timeout; do not join
                    }
                    // brief sleep to yield CPU
                    std.Thread.sleep(self.opts.poll_sleep_us * 1000);
                }

                // The worker flipped stopped=true; now we can safely join
                self.thread.join();
            }

            /// Clean up user endpoints and signals (does not auto-stop).
            pub fn deinit(self: *Handle) void {
                // Close user endpoints
                self.inbox.close();
                self.outbox.close();
                self.inbox.deinit();
                self.outbox.deinit();

                // Drop signals
                self.shutdown.deinit();
                self.stopped.deinit();
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

            // Signals
            var shutdown_sig = try BoolSignal.init(self.allocator, false);
            errdefer shutdown_sig.deinit();

            var stopped_sig = try BoolSignal.init(self.allocator, false);
            errdefer stopped_sig.deinit();

            // Start thread
            const th = try std.Thread.spawn(.{}, workerMain(ContextT), .{
                context_ptr,
                in_pair.receiver,
                out_pair.sender,
                shutdown_sig.clone(), // pass clones to thread
                stopped_sig.clone(),
                options,
            });

            return .{
                .allocator = self.allocator,
                .inbox = in_pair.sender,
                .outbox = out_pair.receiver,
                .thread = th,
                .shutdown = shutdown_sig,
                .stopped = stopped_sig,
                .opts = options,
            };
        }

        /// Per-ContextT worker main, so we can call ctx.step without runtime anytype.
        fn workerMain(comptime ContextT: type) fn (*ContextT, InboxChannel.Receiver, OutboxChannel.Sender, BoolSignal, BoolSignal, ActorOptions) void {
            return struct {
                fn run(
                    ctx: *ContextT,
                    inbox_recv: InboxChannel.Receiver,
                    outbox_send: OutboxChannel.Sender,
                    shutdown: BoolSignal,
                    stopped: BoolSignal,
                    opts: ActorOptions,
                ) void {
                    _ = opts;

                    var inbox_receiver = @constCast(&inbox_recv);
                    var outbox_sender = @constCast(&outbox_send);
                    var outbox = Outbox{ .internal_outbox = outbox_sender };
                    var inbox = Inbox{ .internal_inbox = inbox_receiver };

                    ctx.work(&inbox, &outbox, shutdown, stopped) catch |err| {
                        std.debug.print("Actor worker error: {s}\n", .{@errorName(err)});
                    };

                    // Finish: close recv/send from worker side
                    inbox_receiver.close();
                    outbox_sender.close();

                    // Deinit thread-owned endpoints
                    inbox_receiver.deinit();
                    outbox_sender.deinit();

                    // Mark stopped so Handle.waitForStop() can join
                    stopped.set(true);

                    // Drop the thread's clones of signals
                    shutdown.deinit();
                    stopped.deinit();
                }
            }.run;
        }
    };
}

// Imports
const std = @import("std");

const channel_mod = @import("phasor-channel");
const Channel = channel_mod.Channel;

const signal_mod = @import("signal.zig");
const Signal = signal_mod.Signal;
