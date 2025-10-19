const phase_plugin_mod = @import("phase_plugin.zig");
pub const PhasePlugin = phase_plugin_mod.PhasePlugin;

pub const PhaseContext = @import("PhaseContext.zig");

const phase_context_stack_mod = @import("phase_context_stack.zig");
pub const PhaseContextStack = phase_context_stack_mod.PhaseContextStack;

test "ref all decls" {
    _ = PhasePlugin;
    _ = PhaseContext;
    _ = phase_context_stack_mod;
}
