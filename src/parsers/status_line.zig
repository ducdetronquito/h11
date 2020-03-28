const std = @import("std");
const Buffer = std.Buffer;
const ParserError = @import("errors.zig").ParserError;


pub const StatusLine = struct {
    statusCode: i32,
    reason: []const u8,

    pub fn parse(buffer: std.Buffer) !StatusLine {
        // Does not have a enough data to read the HTTP version and the status code.
        if (buffer.len() < 12) {
            return ParserError.NeedData;
        }

        if (!buffer.startsWith("HTTP/1.1 ")) {
            return ParserError.BadFormat;
        }

        const slice = buffer.toSliceConst();

        const statusCode = std.fmt.parseInt(i32, slice[9..12], 10) catch return ParserError.BadFormat;

        const reason = try StatusLine.parseReason(slice);

        return StatusLine { .statusCode = statusCode, .reason = reason };
    }

    fn parseReason(buffer: []const u8) ![]const u8 {
        // FIXME: As of yet, the reason is considered to be every character before a CRLF.
        // The exact pattern can be found here: https://tools.ietf.org/html/rfc7230#section-3.1.2
        const slice = buffer[13..];
        for (slice) |item, i| {
            if (item == '\n') {
                if (slice[i - 1] == '\r') {
                    return slice[0..i - 1];
                }
            }
        }
        return ParserError.NeedData;
    }
};

const Allocator = std.mem.Allocator;
const testing = std.testing;


test "Parse - When the http version is not HTTP/1.1 - Returns error BadFormat" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var data = try Buffer.init(allocator, "HTTP/2.0 200 OK\r\n");
    defer data.deinit();

    testing.expectError(ParserError.BadFormat, StatusLine.parse(data));
}


test "Parse - When the status code is not made of 3 digits - Returns error BadFormat" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var data = try Buffer.init(allocator, "HTTP/1.1 20x");
    defer data.deinit();

    testing.expectError(ParserError.BadFormat, StatusLine.parse(data));
}


test "Parse - When the status line does not end with a CRLF - Returns error NeedData" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var data = try Buffer.init(allocator, "HTTP/1.1 200 OK");
    defer data.deinit();

    testing.expectError(ParserError.NeedData, StatusLine.parse(data));
}


test "Parse - When the buffer does not contains a complete http version and status code - Returns error NeedData" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var data = try Buffer.init(allocator, "HTTP/1.1 20");
    defer data.deinit();

    testing.expectError(ParserError.NeedData, StatusLine.parse(data));
}


test "Parse - Success" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var data = try Buffer.init(allocator, "HTTP/1.1 405 Method Not Allowed\r\n");
    defer data.deinit();

    const statusLine = try StatusLine.parse(data);
    testing.expect(statusLine.statusCode == 405);
    testing.expect(std.mem.eql(u8, statusLine.reason, "Method Not Allowed"));
}
