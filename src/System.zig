run: *const fn (commands: *Commands) anyerror!void,

const std = @import("std");

const root = @import("root.zig");
const Commands = root.Commands;
const Scoped = root.Scoped;
const System = root.System;
const World = root.World;

pub fn from(comptime system_fn: anytype) !System {
    // Validate that system_fn is a function
    const fn_type = @TypeOf(system_fn);
    const type_info = @typeInfo(fn_type);
    if (type_info != .@"fn") {
        return error.InvalidSystemFunction;
    }

    const runFn = &struct {
        pub fn run(commands: *Commands) !void {
            // Make an arg tuple type for the system function
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
            var args_tuple: ArgsTupleType = undefined;

            // Fill in the args tuple based on parameter types
            inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                const ParamType = field.type;

                // Check if this is a Transaction parameter
                if (ParamType == *Commands) {
                    // Get transaction from database
                    args_tuple[i] = commands;
                } else if (@hasDecl(ParamType, "init_system_param")) {
                    // It's a system parameter (e.g., Res(T), Query(...), GroupBy(...))
                    var param_instance: ParamType = undefined;
                    try param_instance.init_system_param(commands);
                    args_tuple[i] = param_instance;
                } else {
                    @compileError("Unsupported system parameter type: " ++ @typeName(ParamType));
                }
            }

            // Call the original system function with the prepared arguments
            defer {
                inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                    const ParamType = field.type;
                    if (ParamType != *Commands and
                        @hasDecl(ParamType, "deinit"))
                    {
                        (&args_tuple[i]).deinit();
                    }
                }
            }
            return @call(.auto, system_fn, args_tuple);
        }
    }.run;

    return System{ .run = runFn };
}
