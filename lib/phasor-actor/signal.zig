const std = @import("std");

/// A thread-safe, reference-counted signal carrying a value of type `T`.
/// Stores its allocator so any clone can safely deinit.
pub fn Signal(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        value: *std.atomic.Value(T),
        ref_count: *std.atomic.Value(usize),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, initial_value: T) !Self {
            const val_ptr = try allocator.create(std.atomic.Value(T));
            val_ptr.* = std.atomic.Value(T).init(initial_value);

            const rc_ptr = try allocator.create(std.atomic.Value(usize));
            rc_ptr.* = std.atomic.Value(usize).init(1);

            return .{
                .allocator = allocator,
                .value = val_ptr,
                .ref_count = rc_ptr,
            };
        }

        /// Drop one reference; free storage on last drop using the original allocator.
        pub fn deinit(self: *const Self) void {
            if (self.ref_count.fetchSub(1, .seq_cst) == 1) {
                self.allocator.destroy(self.value);
                self.allocator.destroy(self.ref_count);
            }
        }

        pub fn clone(self: *const Self) Self {
            _ = self.ref_count.fetchAdd(1, .seq_cst);
            return .{
                .allocator = self.allocator,
                .value = self.value,
                .ref_count = self.ref_count,
            };
        }

        pub fn get(self: *const Self) T {
            return self.value.load(.seq_cst);
        }

        pub fn set(self: *const Self, new_value: T) void {
            self.value.store(new_value, .seq_cst);
        }
    };
}

test "Signal: bool shutdown flag" {
    const allocator = std.testing.allocator;
    var flag = try Signal(bool).init(allocator, false);
    defer flag.deinit();

    try std.testing.expect(!flag.get());
    flag.set(true);
    try std.testing.expect(flag.get());
}

test "Signal: clone propagates changes" {
    const allocator = std.testing.allocator;
    var flag1 = try Signal(i32).init(allocator, 0);
    defer flag1.deinit();

    var flag2 = flag1.clone();
    defer flag2.deinit();

    try std.testing.expect(flag1.get() == 0);
    flag2.set(42);
    try std.testing.expect(flag1.get() == 42);
}
