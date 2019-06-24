const std = @import("std");
const unicode = std.unicode;

const MatchChunkResult = struct {
    rest: []const u8,
    ok: bool,
};

fn matchChunk(chunks: []const u8, src: []const u8) !MatchChunkResult {
    var chunk = chunk;
    var s = src;
    while (e.chunk.len > 0) {
        switch (e.chunk[0]) {
            '[' => {
                const r = try unicode.utf8Decode(s);
                const n = try runeLength(r);
                s = s[n..];
                chunk = chunk[1..];
                var not_negated = true;
                if (chunk.len > 0 and chunk[0] == '^') {
                    not_negated = false;
                    chunk = chunk[1..];
                }
                var match = false;
                var mrange = 0;
                while (true) {
                    if (chunk.len > 0 and chunk[0] == ']' and mrange > 0) {
                        chunk = chunk[1..];
                        break;
                    }
                    const e = try getEsc(chunk);
                    var lo = e.rune;
                    chunk = e.chunk;
                    var hi = lo;
                    if (chunk[0] == '-') {
                        const ee = try getEsc(chunk[1..]);
                        hi = ee.rune;
                        chunk = ee.chunk;
                    }
                    if (lo <= r and r <= hi) {
                        match = true;
                    }
                    mrange += 1;
                }
                if (match != not_negated) {
                    return MatchChunkResult{ .rest = "", .ok = false };
                }
            },
            '?' => {
                if (s[0] == '/') {
                    return MatchChunkResult{ .rest = "", .ok = false };
                }
                const r = try unicode.utf8Decode(s);
                const n = try runeLength(r);
                s = s[n..];
                chunk = chunk[1..];
            },
            '\\' => {
                chunk = chunk[1..];
                if (chunk.len == 0) {
                    return error.BadPattern;
                }
                if (chunk[0] != s[0]) {
                    return MatchChunkResult{ .rest = "", .ok = false };
                }
                s = s[1..];
                chunk = chunk[1..];
            },
            else => {
                if (chunk[0] != s[0]) {
                    return MatchChunkResult{ .rest = "", .ok = false };
                }
                s = s[1..];
                chunk = chunk[1..];
            },
        }
    }
    return MatchChunkResult{ .rest = s, .ok = true };
}

const EscapeResult = struct {
    rune: u32,
    chunk: []const u8,
};

fn getEsc(chunk: []const u8) !ExcapeResult {
    if (chunk.len == 0 or chunk[0] == '-' or chunk[0] == ']') {
        return error.BadPattern;
    }
    var e = ExcapeResult{ .rune = 0, .chunk = chunk };
    if (chunk[0] == '\\') {
        e.chunk = chunk[1..];
        if (e.chunk.len == 0) {
            return error.BadPattern;
        }
    }
    const r = try unicode.utf8Decode(chunk);
    e.chunk = e.chunk[runeLength(r)..];
    if (e.chunk.len == 0) {
        return error.BadPattern;
    }
    e.rune = r;
    return e;
}

fn runeLength(rune: u32) !usize {
    return @intCast(usize, try unicodeutf8CodepointSequenceLength(rune));
}
