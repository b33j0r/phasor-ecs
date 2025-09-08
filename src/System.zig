run: *const fn (transaction: *Transaction) anyerror!void,

const std = @import("std");

const root = @import("root.zig");
const System = root.System;

const phasor_db = @import("phasor-db");
const Transaction = phasor_db.Transaction;

pub fn from(comptime system_fn: anytype) !System {
    // Validate that system_fn is a function
        const fn_type = @TypeOf(system_fn);
    const type_info = @typeInfo(fn_type);
    if (type_info != .@"fn") {
        return error.InvalidSystemFunction;
    }

    if (type_info.@"fn".params.len == 0) {
        return error.SystemMustHaveParameters;
    }

    const runFn = &struct {
        pub fn run(transaction: *Transaction) !void {
            // Make an arg tuple type for the system function
                const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
            var args_tuple: ArgsTupleType = undefined;

            // Fill in the args tuple based on parameter types
                inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                const ParamType = field.type;

                // Check if this is a Transaction parameter
                    if (ParamType == *Transaction) {
                    // Get transaction from database
                        args_tuple[i] = transaction;
                } else if (@hasDecl(ParamType, "init_system_param")) {
                    // It's a system parameter (e.g., Res(T))
                        var param_instance: ParamType = undefined;
                    try param_instance.init_system_param(transaction);
                    args_tuple[i] = param_instance;
                } else {
                    @compileError("Unsupported system parameter type: " ++ @typeName(ParamType));
                }
            }

            // Call the original system function with the prepared arguments
                return @call(.auto, system_fn, args_tuple);
        }
    }.run;

    return System{ .run = runFn };
}