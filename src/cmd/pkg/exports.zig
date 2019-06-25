const std = @import("std");
const flags = @import("flags");
const path = std.fs.path;
const fmt = @import("../fmt.zig");
const exports = @import("../../pkg/exports/exports.zig");

const Export = exports.Export;
const Pkg = Export.Pkg;
const File = std.fs.File;
const Command = flags.Command;
const Flag = flags.Flag;
const Context = flags.Context;

pub const command = Command{
    .name = "exports",
    .flags = null,
    .action = exprtsCmd,
    .sub_commands = null,
};

fn exprtsCmd(ctx: *const Context) anyerror!void {
    if (ctx.firstArg()) |arg| {
        const root = try path.resolve(ctx.allocator, [_][]const u8{arg});
        return generate(ctx, root);
    }
    return generate(ctx, try std.process.getCwdAlloc(ctx.allocator));
}

const build_file = "build.zig";
const src_dir = "src";
const exports_file = "EXPORTS.zig";

fn generate(ctx: *const Context, root: []const u8) anyerror!void {
    const stdout = ctx.stdout.?;
    const full_build_file = try path.join(
        ctx.allocator,
        [_][]const u8{ root, build_file },
    );
    if (!exports.fileExists(full_build_file)) {
        try stdout.print("=> can't fing  build file at {}\n", full_build_file);
        return;
    }
    try stdout.print("=> found build file at {}\n", full_build_file);
    const full_src_dir = try path.join(
        ctx.allocator,
        [_][]const u8{ root, src_dir },
    );
    if (!exports.fileExists(full_src_dir)) {
        try stdout.print("=> can't fing  sources directory at {}\n", full_src_dir);
        return;
    }
    try stdout.print("=> found sources directory at {}\n", full_src_dir);

    var e = &exports.Export.init(ctx.allocator, root);
    try e.dir(full_src_dir);

    const full_exports_file = try path.join(
        ctx.allocator,
        [_][]const u8{ root, exports_file },
    );

    var buf = &try std.Buffer.init(ctx.allocator, "");
    defer buf.deinit();

    var file = try File.openWrite(full_exports_file);
    defer file.close();
    try render(e, &std.io.BufferOutStream.init(buf).stream);
    try fmt.format(
        ctx.allocator,
        buf.toSlice(),
        &file.outStream().stream,
    );
    try stdout.print("OK  generated   {}\n", full_exports_file);
}

const header =
    \\ // DO NOT EDIT!
    \\ // autogenerated by hoodie pkg exports 
    \\const LibExeObjStep = @import("std").build.LibExeObjStep;
    \\pub const Pkg = struct {
    \\    name: []const u8,
    \\    path: []const u8,
    \\};
;

const footer =
    \\pub fn setupPakcages(steps: []*LibExeObjStep) void {
    \\    for (steps) |step| {
    \\        for (packages) |pkg| {
    \\            step.addPackagePath(pkg.name, pkg.path);
    \\        }
    \\    }
    \\}
;
fn render(e: *Export, out: var) anyerror!void {
    std.sort.sort(*Pkg, e.list.toSlice(), sortPkg);
    try out.print("{}\n", header);
    try out.print("{}",
        \\ pub const packages=[_]Pkg{
    );
    try e.dumpStream(out);
    try out.print("{}",
        \\ };
    );
    try out.print("{}\n", footer);
}

fn sortPkg(lhs: *Pkg, rhs: *Pkg) bool {
    return std.mem.compare(u8, lhs.name, rhs.name) == .LessThan;
}
