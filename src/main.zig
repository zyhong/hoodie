const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const os = std.os;
const io = std.io;
const heap = std.heap;
const builtin = @import("builtin");

const outline = @import("outline.zig").outline;
const format = @import("fmt.zig").format;
const max_src_size = 2 * 1024 * 1024 * 1024; // 2 GiB

// taken from https://github.com/Hejsil/zig-clap
pub const OsIterator = struct {
    const Error = os.ArgIterator.NextError;

    arena: heap.ArenaAllocator,
    args: os.ArgIterator,

    pub fn init(allocator: *mem.Allocator) OsIterator {
        return OsIterator{
            .arena = heap.ArenaAllocator.init(allocator),
            .args = os.args(),
        };
    }

    pub fn deinit(iter: *OsIterator) void {
        iter.arena.deinit();
    }

    pub fn next(iter: *OsIterator) Error!?[]const u8 {
        if (builtin.os == builtin.Os.windows) {
            return try iter.args.next(&iter.arena.allocator) orelse return null;
        } else {
            return iter.args.nextPosix();
        }
    }
};

var stdout_file: os.File = undefined;
var stdout_file_out_stream: os.File.OutStream = undefined;
var stdout_stream: ?*io.OutStream(os.File.WriteError) = null;

pub fn main() anyerror!void {
    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();
    var stdin_file = try io.getStdIn();
    var stdin = stdin_file.inStream();

    var iter = OsIterator.init(allocator);
    defer iter.deinit();
    _ = try iter.next(); //exe
    while (try iter.next()) |param| {
        if (mem.eql(u8, param, "outline")) {
            if (try iter.next()) |file_name| {
                const stdout = try getStdoutStream();
                if (mem.eql(u8, file_name, "-modified")) {
                    const source_code = try stdin.stream.readAllAlloc(allocator, max_src_size);
                    defer allocator.free(source_code);
                    return outline(allocator, source_code, stdout);
                }
                if (std.io.readFileAlloc(allocator, file_name)) |data| {
                    defer allocator.free(data);
                    return outline(allocator, data, stdout);
                } else |err| {
                    std.debug.warn("{}\n", err);
                    os.exit(1);
                }
            } else {
                debug.warn("{}\n", outline_help_missing_filename);
                os.exit(1);
            }
            return;
        } else if (mem.eql(u8, param, "fmt")) {
            const stdout = try getStdoutStream();
            return format(allocator, stdout);
        }
    }
}

const outline_help_missing_filename =
    \\missing filename to outline command
    \\  USAGE
    \\hoodie outline [FILENAME]
    \\  FILENAME is absolute or relatime path to the zig source file.
;

pub fn getStdoutStream() !*io.OutStream(os.File.WriteError) {
    if (stdout_stream) |st| {
        return st;
    } else {
        stdout_file = try io.getStdOut();
        stdout_file_out_stream = stdout_file.outStream();
        const st = &stdout_file_out_stream.stream;
        stdout_stream = st;
        return st;
    }
}
