const std = @import("std");

const phasor_db = @import("phasor-db");
const Entity = phasor_db.Entity;
const GroupByResult = phasor_db.GroupByResult;
const QueryResult = phasor_db.QueryResult;

const ecs = @import("root.zig");
const Commands = ecs.Commands;

const meta = @import("meta.zig");
const Cons = meta.Cons;
const consValue = meta.consValue;

// System Parameters
//
// System parameters are used to determine the dependency
// graph of systems. They are specified as comptime wrappers.

/// `Res(T)` is a comptime wrapper to specify
/// a resource of type `T` as a system parameter.
pub fn Res(comptime ResourceT: type) type {
    return struct {
        ptr: *const T,

        const Self = @This();
        pub const T = ResourceT;

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.ptr = commands.world.getResourceMut(ResourceT).?;
        }
    };
}

/// `ResMut(T)` is a comptime wrapper to specify
/// a resource of type `T` as a system parameter.
pub fn ResMut(comptime ResourceT: type) type {
    return struct {
        ptr: *T,

        const Self = @This();
        pub const T = ResourceT;

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.ptr = commands.world.getResourceMut(ResourceT).?;
        }
    };
}

/// `ResOpt(T)` is a comptime wrapper to specify
/// an optional resource of type `T` as a system parameter.
pub fn ResOpt(comptime ResourceT: type) type {
    return struct {
        ptr: ?*const T,
        const Self = @This();
        pub const T = ResourceT;

        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.ptr = commands.world.getResourceMut(ResourceT);
        }
    };
}

/// `Query` is a declarative comptime construct to specify
/// a query for components in the ECS database.
///
/// When used as a system parameter, it is a wrapper that fetches a QueryResult
/// from the Transaction during system parameter initialization.
pub fn Query(comptime Parts: anytype) type {
    return struct {
        result: QueryResult = undefined,

        const Self = @This();

        /// Initializes this system parameter by executing the query on the world via commands.
        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.result = try commands.world.entities.query(Parts);
        }

        /// Free resources held by the underlying QueryResult.
        pub fn deinit(self: *Self) void {
            self.result.deinit();
        }

        /// Returns true if the query has no matching entities.
        pub fn isEmpty(self: *const Self) bool {
            return self.result.count() == 0;
        }

        /// Number of entities matching the query.
        pub fn count(self: *const Self) usize {
            return self.result.count();
        }

        /// Iterator over entities matching the query.
        pub fn iterator(self: *const Self) QueryResult.Iterator {
            return self.result.iterator();
        }

        /// Convenience to get the first entity matching the query, if any.
        pub fn first(self: *const Self) ?Entity {
            return self.result.first();
        }

        /// Group the results by a trait.
        pub fn groupBy(self: *const Self, TraitT: anytype) !GroupByResult {
            return self.result.groupBy(TraitT);
        }

        /// Collect the results into an array.
        pub fn listAlloc(self: *const Self, allocator: std.mem.Allocator) ![]Entity {
            return self.result.listAlloc(allocator);
        }

        /// Collect the results into an array and sort them.
        pub fn sortAlloc(
            self: *const Self,
            allocator: std.mem.Allocator,
            ctx: anytype,
        ) ![]Entity {
            return self.result.sortAlloc(allocator, ctx);
        }
    };
}

/// `GroupBy(TraitT)` is a system parameter that provides grouped query results
/// for all entities/components implementing the given trait.
///
/// Usage in a system function:
///   fn my_system(groups: GroupBy(MyTrait)) !void { ... }
///
/// It mirrors the Query system parameter style, but groups across the entire
/// database by the specified trait.
pub fn GroupBy(comptime TraitT: anytype) type {
    return struct {
        result: GroupByResult = undefined,

        const Self = @This();

        /// Initializes this system parameter by grouping the entire DB by TraitT.
        pub fn init_system_param(self: *Self, commands: *Commands) !void {
            self.result = try commands.world.entities.groupBy(TraitT);
        }

        /// Free resources held by the underlying GroupByResult.
        pub fn deinit(self: *Self) void {
            self.result.deinit();
        }

        /// Number of groups.
        pub fn count(self: *const Self) usize {
            return self.result.count();
        }

        /// Iterator over groups.
        pub fn iterator(self: *const Self) GroupByResult.GroupIterator {
            return self.result.iterator();
        }
    };
}
