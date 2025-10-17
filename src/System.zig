run: *const fn (commands: *Commands) anyerror!void,
register: *const fn (world: *World) anyerror!void,
unregister: *const fn (world: *World) anyerror!void,

pub fn from(comptime system_fn: anytype) !System {
    // Validate that system_fn is a function
    const fn_type = @TypeOf(system_fn);
    const type_info = @typeInfo(fn_type);
    if (type_info != .@"fn") {
        return error.InvalidSystemFunction;
    }

    // Registration function - called once when system is added to schedule
    const registerFn = &struct {
        pub fn register(world: *World) !void {
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
            inline for (std.meta.fields(ArgsTupleType)) |field| {
                const ParamType = field.type;
                const param_type_info = @typeInfo(ParamType);
                if (param_type_info == .@"struct" or param_type_info == .@"union" or param_type_info == .@"enum") {
                    if (@hasDecl(ParamType, "register_system_param")) {
                        try ParamType.register_system_param(system_fn, world);
                    }
                }
            }
        }
    }.register;

    // Run function - called every frame
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
                    try param_instance.init_system_param(system_fn, commands);
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

    const unregisterFn = struct {
        pub fn unregister(world: *World) !void {
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
            inline for (std.meta.fields(ArgsTupleType)) |field| {
                const ParamType = field.type;
                const param_type_info = @typeInfo(ParamType);
                if (param_type_info == .@"struct" or param_type_info == .@"union" or param_type_info == .@"enum") {
                    if (@hasDecl(ParamType, "unregister_system_param")) {
                        try ParamType.unregister_system_param(system_fn, world);
                    }
                }
            }
        }
    }.unregister;

    return System{
        .run = runFn,
        .register = registerFn,
        .unregister = unregisterFn,
    };
}

// Imports
const std = @import("std");

const root = @import("root.zig");
const Commands = root.Commands;
const Scoped = root.Scoped;
const System = root.System;
const World = root.World;
const SubscriptionManager = root.SubscriptionManager;
