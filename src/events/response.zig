const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const EventError = @import("errors.zig").EventError;
const Headers = @import("headers.zig").Headers;
const HeaderField = @import("headers.zig").HeaderField;

pub const StatusLine = struct {
    pub statusCode: i32,
};

pub const Response = struct {
    pub statusCode: i32,
    pub headers: ArrayList(HeaderField),

    pub fn deinit(self: *const Response) void {
        self.headers.deinit();
    }

    pub fn parse(buffer: *Buffer, allocator: *Allocator) !Response {
        var statusLine = try Response.parseStatusLine(buffer);

        var headers = try Headers.parse(allocator, buffer);
        errdefer headers.deinit();

        return Response{ .statusCode = statusLine.statusCode, .headers = headers };
    }

    pub fn parseStatusLine(buffer: *Buffer) !StatusLine {
        var line = buffer.readLine() catch return EventError.NeedData;

        if (line.len < 12) {
            return EventError.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return EventError.RemoteProtocolError;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return EventError.RemoteProtocolError;

        return StatusLine{ .statusCode = statusCode };
    }

    pub fn getContentLength(self: *Response) !usize {
        // TODO: At some point we may want to verify that the content-length value
        // is a valid unsigned integer when parsing the headers.
        var rawContentLength: []const u8 = "0";
        for (self.headers.toSliceConst()) |header| {
            if (std.mem.eql(u8, header.name, "content-length")) {
                rawContentLength = header.value;
            }
        }

        const contentLength = std.fmt.parseInt(usize, rawContentLength, 10) catch {
            return EventError.RemoteProtocolError;
        };

        return contentLength;
    }
};

const testing = std.testing;

test "Parse Status Line- When the status line does not end with a CRLF - Returns NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 200 OK");
    var statusLine = Response.parseStatusLine(&buffer);

    testing.expectError(EventError.NeedData, statusLine);
}

test "Parse Status Line - When the http version is not HTTP/1.1 - Returns RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/2.0 200 OK\r\n");
    var statusLine = Response.parseStatusLine(&buffer);

    testing.expectError(EventError.RemoteProtocolError, statusLine);
}

test "Parse Status Line - When the status code is not made of 3 digits - Returns RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 20x OK\r\n");
    var statusLine = Response.parseStatusLine(&buffer);

    testing.expectError(EventError.RemoteProtocolError, statusLine);
}

test "Parse Status Line" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 405 Method Not Allowed\r\n");
    var statusLine = try Response.parseStatusLine(&buffer);

    testing.expect(statusLine.statusCode == 405);
    testing.expect(buffer.isEmpty());
}

test "Parse" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 12\r\n\r\n");

    var response = try Response.parse(&buffer, allocator);
    testing.expect(response.statusCode == 200);
    testing.expect(response.headers.len == 2);
}

test "Get Content Length" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headers = ArrayList(HeaderField).init(allocator);
    try headers.append(HeaderField{ .name = "content-length", .value = "12" });
    var response = Response{ .statusCode = 200, .headers = headers };

    var contentLength: usize = try response.getContentLength();
    testing.expect(contentLength == 12);
}

test "Get Content Length - When value is not a integer - Returns RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headers = ArrayList(HeaderField).init(allocator);
    try headers.append(HeaderField{ .name = "content-length", .value = "XXX" });
    var response = Response{ .statusCode = 200, .headers = headers };

    testing.expectError(EventError.RemoteProtocolError, response.getContentLength());
}
