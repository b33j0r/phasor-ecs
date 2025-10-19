const test_simple = @import("test_simple.zig");
const test_hierarchical = @import("test_hierarchical.zig");
const test_plugin = @import("test_plugin.zig");

test "ref all decls" {
    _ = test_simple;
    _ = test_hierarchical;
    _ = test_plugin;
}
