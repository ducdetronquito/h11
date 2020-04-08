const std = @import("std");
const Buffer = @import("../../buffer.zig").Buffer;
const EventError = @import("../errors.zig").EventError;


pub const StatusLine = struct {
    statusCode: i32,

    pub fn parse(buffer: *Buffer) !StatusLine {
        var line = buffer.readLine() catch return EventError.NeedData;

        if (line.len < 12) {
            return EventError.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return EventError.RemoteProtocolError;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return EventError.RemoteProtocolError;

        return StatusLine { .statusCode = statusCode };
    }
};


const testing = std.testing;

test "Parse - When the status line does not end with a CRLF - Returns error NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 200 OK");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(EventError.NeedData, statusLine);
}

test "Parse - When the http version is not HTTP/1.1 - Returns error RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/2.0 200 OK\r\n");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(EventError.RemoteProtocolError, statusLine);
}

test "Parse - When the status code is not made of 3 digits - Returns error RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 20x OK\r\n");
    var statusLine = StatusLine.parse(&buffer);

    testing.expectError(EventError.RemoteProtocolError, statusLine);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 405 Method Not Allowed\r\n");
    var statusLine = try StatusLine.parse(&buffer);

    testing.expect(statusLine.statusCode == 405);
    testing.expect(buffer.isEmpty());
}
