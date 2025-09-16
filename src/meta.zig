const std = @import("std");

pub fn Cons(comptime Head: type, tail: anytype) type {
    // Tail must be a tuple type
    const TailType = @TypeOf(tail);
    const fields = std.meta.fields(TailType);

    var types: [fields.len + 1]type = undefined;
    types[0] = Head;
    inline for (fields, 0..) |f, i| {
        types[i + 1] = f.type;
    }
    return std.meta.Tuple(&types);
}

pub fn consValue(head: anytype, tail: anytype) Cons(@TypeOf(head), tail) {
    const TailType = @TypeOf(tail);
    const fields = std.meta.fields(TailType);

    var result: Cons(@TypeOf(head), tail) = undefined;
    result[0] = head;
    inline for (fields, 0..) |f, i| {
        result[i + 1] = @field(tail, f.name);
    }
    return result;
}

test Cons {
    const tuple1 = Cons(i32, .{});
    const tuple2 = Cons(u8, tuple1);
    const tuple3 = Cons(bool, tuple2);
    std.testing.expect(@TypeOf(tuple3) == .{ bool, u8, i32 });
}
