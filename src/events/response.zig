const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const EventError = @import("errors.zig").EventError;
const Headers = @import("headers.zig").Headers;
const HeaderField = @import("headers.zig").HeaderField;
const Stream = @import("../stream.zig").Stream;

pub const StatusLine = struct {
    statusCode: i32,
};

pub const Response = struct {
    allocator: *Allocator,
    statusCode: i32,
    headers: Headers,


    pub fn init(allocator: *Allocator, statusCode: i32, headers: Headers) Response {
        return Response{ .allocator = allocator, .statusCode = statusCode, .headers = headers };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
    }

    pub fn parse(stream: *Stream, allocator: *Allocator) EventError!Response {
        var statusLine = try Response.parseStatusLine(stream);

        var headers = try Headers.parse(allocator, stream);

        return Response.init(allocator, statusLine.statusCode, headers);
    }

    pub fn parseStatusLine(stream: *Stream) EventError!StatusLine {
        var line = stream.readLine() catch return error.NeedData;

        if (line.len < 12) {
            return error.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return error.RemoteProtocolError;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return error.RemoteProtocolError;

        return StatusLine{ .statusCode = statusCode };
    }

    pub fn getContentLength(self: *Response) EventError!usize {
        var rawContentLength: []const u8 = "0";
        for (self.headers.fields) |field| {
            if (std.mem.eql(u8, field.name, "content-length")) {
                rawContentLength = field.value;
            }
        }

        const contentLength = std.fmt.parseInt(usize, rawContentLength, 10) catch {
            return error.RemoteProtocolError;
        };

        return contentLength;
    }
};

const testing = std.testing;

test "Parse Status Line- When the status line does not end with a CRLF - Returns NeedData" {
    var content = "HTTP/1.1 200 OK".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.NeedData, statusLine);
}

test "Parse Status Line - When the http version is not HTTP/1.1 - Returns RemoteProtocolError" {
    var content = "HTTP/2.0 200 OK\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.RemoteProtocolError, statusLine);
}

test "Parse Status Line - When the status code is not made of 3 digits - Returns RemoteProtocolError" {
    var content = "HTTP/1.1 20x OK\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.RemoteProtocolError, statusLine);
}

test "Parse Status Line" {
    var content = "HTTP/1.1 405 Method Not Allowed\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = try Response.parseStatusLine(&stream);

    testing.expect(statusLine.statusCode == 405);
    testing.expect(stream.isEmpty());
}

test "Parse" {
    var content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 12\r\n\r\n".*;
    var stream = Stream.init(&content);

    var response = try Response.parse(&stream, testing.allocator);
    defer response.deinit();

    testing.expect(response.statusCode == 200);
    testing.expect(response.headers.fields.len == 2);
}

test "Get Content Length" {
    var fields = ArrayList(HeaderField).init(testing.allocator);
    defer fields.deinit();
    try fields.append(HeaderField{ .name = "content-length", .value = "12" });
    var headers = Headers.fromOwnedSlice(testing.allocator, fields.toOwnedSlice());
    var response = Response.init(testing.allocator, 200, headers);
    defer response.deinit();

    var contentLength = try response.getContentLength();

    testing.expect(contentLength == 12);
}

test "Get Content Length - When value is not a integer - Returns RemoteProtocolError" {
    var fields = ArrayList(HeaderField).init(testing.allocator);
    defer fields.deinit();
    try fields.append(HeaderField{ .name = "content-length", .value = "XXX" });
    var headers = Headers.fromOwnedSlice(testing.allocator, fields.toOwnedSlice());
    var response = Response.init(testing.allocator, 200, headers);
    defer response.deinit();

    var contentLength = response.getContentLength();

    testing.expectError(error.RemoteProtocolError, contentLength);
}
