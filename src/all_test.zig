test "hoodie" {
    _ = @import("unicode/all_test.zig");
    _ = @import("lsp/all_test.zig");
    _ = @import("time/time_test.zig");
    _ = @import("strings/strings_test.zig");
    _ = @import("pkg/all_test.zig");
    _ = @import("lsp/all_test.zig");
    _ = @import("flags/cli_test.zig");
    _ = @import("html/html_test.zig");
    _ = @import("image/all_test.zig");
    _ = @import("compress/all_test.zig");
    _ = @import("path/all_test.zig");
    _ = @import("ignore/ignore_test.zig");
    _ = @import("encoding/csv/csv_test.zig");
}
