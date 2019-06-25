// DO NOT EDIT!
// autogenerated by hoodie pkg exports
const LibExeObjStep = @import("std").build.LibExeObjStep;
pub const Pkg = struct {
    name: []const u8,
    path: []const u8,
};
pub const packages = [_]Pkg{
    Pkg{ .name = "all_test", .path = "src/all_test.zig" },
    Pkg{ .name = "cmd", .path = "src/cmd/cmd.zig" },
    Pkg{ .name = "compress/all_test", .path = "src/compress/all_test.zig" },
    Pkg{ .name = "compress/flate/bits", .path = "src/compress/flate/bits.zig" },
    Pkg{ .name = "compress/flate/flate_test", .path = "src/compress/flate/flate_test.zig" },
    Pkg{ .name = "compress/flate/huffman", .path = "src/compress/flate/huffman.zig" },
    Pkg{ .name = "compress/flate/huffman_test", .path = "src/compress/flate/huffman_test.zig" },
    Pkg{ .name = "flags", .path = "src/flags/flags.zig" },
    Pkg{ .name = "hoodie", .path = "src/hoodie.zig" },
    Pkg{ .name = "html", .path = "src/html/html.zig" },
    Pkg{ .name = "image", .path = "src/image/image.zig" },
    Pkg{ .name = "json", .path = "src/json/json.zig" },
    Pkg{ .name = "lsp/all_test", .path = "src/lsp/all_test.zig" },
    Pkg{ .name = "lsp/diff", .path = "src/lsp/diff/diff.zig" },
    Pkg{ .name = "lsp/jsonrpc2", .path = "src/lsp/jsonrpc2/jsonrpc2.zig" },
    Pkg{ .name = "lsp/protocol", .path = "src/lsp/protocol/protocol.zig" },
    Pkg{ .name = "lsp/server", .path = "src/lsp/server/server.zig" },
    Pkg{ .name = "lsp/snippet", .path = "src/lsp/snippet/snippet.zig" },
    Pkg{ .name = "lsp/span", .path = "src/lsp/span/span.zig" },
    Pkg{ .name = "markdown", .path = "src/markdown/markdown.zig" },
    Pkg{ .name = "net/all_test", .path = "src/net/all_test.zig" },
    Pkg{ .name = "net/url", .path = "src/net/url/url.zig" },
    Pkg{ .name = "outline", .path = "src/outline/outline.zig" },
    Pkg{ .name = "path/filepath", .path = "src/path/filepath/filepath.zig" },
    Pkg{ .name = "path/match", .path = "src/path/match.zig" },
    Pkg{ .name = "path/match_test", .path = "src/path/match_test.zig" },
    Pkg{ .name = "pkg/all_test", .path = "src/pkg/all_test.zig" },
    Pkg{ .name = "pkg/dirhash", .path = "src/pkg/dirhash/dirhash.zig" },
    Pkg{ .name = "pkg/exports", .path = "src/pkg/exports/exports.zig" },
    Pkg{ .name = "pkg/module", .path = "src/pkg/module.zig" },
    Pkg{ .name = "pkg/module_info", .path = "src/pkg/module_info.zig" },
    Pkg{ .name = "pkg/semver", .path = "src/pkg/semver/semver.zig" },
    Pkg{ .name = "result", .path = "src/result/result.zig" },
    Pkg{ .name = "strings", .path = "src/strings/strings.zig" },
    Pkg{ .name = "template", .path = "src/template/template.zig" },
    Pkg{ .name = "time", .path = "src/time/time.zig" },
    Pkg{ .name = "token", .path = "src/token/token.zig" },
    Pkg{ .name = "unicode", .path = "src/unicode/index.zig" },
    Pkg{ .name = "zig/types", .path = "src/zig/types.zig" },
};
pub fn setupPakcages(steps: []*LibExeObjStep) void {
    for (steps) |step| {
        for (packages) |pkg| {
            step.addPackagePath(pkg.name, pkg.path);
        }
    }
}
