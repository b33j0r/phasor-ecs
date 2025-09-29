/// Used by the main app side (outside the actor)
pub fn InboxSender(comptime InboxT: type) type {
    return struct {
        const Self = @This();
        pub fn send(self: *Self, msg: InboxT) !void {
            _ = self;
            _ = msg;
        }
    };
}

/// Used by the main app side (outside the actor)
pub fn OutboxReceiver(comptime OutboxT: type) type {
    return struct {
        const Self = @This();
        pub fn recv(self: *Self) !OutboxT {
            _ = self;
            return error.NotImplemented;
        }
    };
}

/// Used by the subapp side (inside the actor)
pub fn InboxReceiver(comptime InboxT: type) type {
    return struct {
        const Self = @This();
        pub fn recv(self: *Self) !InboxT {
            _ = self;
            return error.NotImplemented;
        }
    };
}

/// Used by the subapp side (inside the actor)
pub fn OutboxSender(comptime OutboxT: type) type {
    return struct {
        const Self = @This();
        pub fn send(self: *Self, msg: OutboxT) !void {
            _ = self;
            _ = msg;
        }
    };
}
