const std = @import("std");
const ParserError = @import("errors.zig").ParserError;
const Buffer = @import("../buffer.zig").Buffer;


pub const StatusLine = struct {
    statusCode: i32,
    reason: []const u8,

    pub fn parse(buffer: *Buffer) !StatusLine {
        // Does not have a enough data to read the HTTP version and the status code.
        var line = buffer.readLine() catch return ParserError.NeedData;

        if (line.len < 12) {
            return ParserError.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return ParserError.BadFormat;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return ParserError.BadFormat;
        const reason = line[13..];

        return StatusLine { .statusCode = statusCode, .reason = reason };
    }
};


const testing = std.testing;

test "Parse - When the status line does not end with a CRLF - Returns error NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 200 OK");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(ParserError.NeedData, statusLine);
}

test "Parse - When the http version is not HTTP/1.1 - Returns error BadFormat" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/2.0 200 OK\r\n");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(ParserError.BadFormat, statusLine);
}

test "Parse - When the status code is not made of 3 digits - Returns error BadFormat" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 20x OK\r\n");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(ParserError.BadFormat, statusLine);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 405 Method Not Allowed\r\n");
    var statusLine = try StatusLine.parse(&buffer);

    testing.expect(statusLine.statusCode == 405);
    testing.expect(std.mem.eql(u8, statusLine.reason, "Method Not Allowed"));
}
