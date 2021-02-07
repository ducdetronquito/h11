const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const parse_headers = @import("utils.zig").parse_headers;
const headers = @import("headers.zig");
const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

pub const Response = struct {
    allocator: *Allocator,
    headers: Headers,
    statusCode: StatusCode,
    version: Version,
    raw_bytes: []const u8,

    pub fn deinit(self: Response) void {
        var _headers = self.headers;
        _headers.deinit();
        self.allocator.free(self.raw_bytes);
    }

    pub fn parse(allocator: *Allocator, buffer: []const u8) ParsingError!Response {
        const statusLine = readLine(buffer) orelse return error.Incomplete;
        if (statusLine.len < 12) {
            return error.Invalid;
        }

        const httpVersion = Version.from_bytes(statusLine[0..8]) orelse return error.Invalid;
        switch (httpVersion) {
            .Http11 => {},
            else => return error.Invalid,
        }

        if (statusLine[8] != ' ') {
            return error.Invalid;
        }

        const rawStatusCode = std.fmt.parseInt(u16, statusLine[9..12], 10) catch return error.Invalid;
        const statusCode = StatusCode.from_u16(rawStatusCode) catch return error.Invalid;

        if (statusLine.len > 12 and statusLine[12] != ' ' and statusLine[12] != '\r') {
            return error.Invalid;
        }

        var _headers = try parse_headers(allocator, buffer[statusLine.len + 2 ..], 128);
        return Response{
            .allocator = allocator,
            .headers = _headers,
            .version = httpVersion,
            .statusCode = statusCode,
            .raw_bytes = buffer,
        };
    }

    pub fn parseFromStream(allocator: *Allocator, reader: anytype, buffer: []u8) !Response {
        var statusLine = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return error.EndOfStream;

        if (statusLine[statusLine.len - 1] != '\r') {
            return ParsingError.Invalid;
        }
        statusLine = statusLine[0..statusLine.len - 1];

        if (statusLine.len < 12) {
            return ParsingError.Invalid;
        }

        const httpVersion = Version.from_bytes(statusLine[0..8]) orelse return ParsingError.Invalid;
        switch (httpVersion) {
            .Http11 => {},
            else => return ParsingError.Invalid,
        }

        if (statusLine[8] != ' ') {
            return ParsingError.Invalid;
        }

        const rawStatusCode = std.fmt.parseInt(u16, statusLine[9..12], 10) catch return ParsingError.Invalid;
        const statusCode = StatusCode.from_u16(rawStatusCode) catch return ParsingError.Invalid;

        if (statusLine.len > 12 and statusLine[12] != ' ' and statusLine[12] != '\r') {
            return ParsingError.Invalid;
        }

        var _headers = try headers.parse(allocator, reader, buffer[statusLine.len + 2 ..], 128);
        return Response{
            .allocator = allocator,
            .headers = _headers,
            .version = httpVersion,
            .statusCode = statusCode,
            .raw_bytes = buffer,
        };
    }
};

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;


test "Parse - Succeed." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var response = try Response.parseFromStream(std.testing.allocator, reader, &read_buffer);
    defer response.headers.deinit();

    var _headers = response.headers.items();
    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);
    expect(response.headers.len() == 2);
    expectEqualStrings("Server", _headers[0].name.raw());
    expectEqualStrings("Apache", _headers[0].value);
    expectEqualStrings("Content-Length", _headers[1].name.raw());
    expectEqualStrings("0", _headers[1].value);
}

test "Parse - Succeed when the status line has no reason phrase." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 200\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var response = try Response.parseFromStream(std.testing.allocator, reader, &read_buffer);
    defer response.headers.deinit();

    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);
}

test "Parse - Fail when the response the status line does not ends with a CRLF." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 200 OK";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the HTTP version is not HTTP/1.1" {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.0 200 OK\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the status line is less than 12 characters." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 99\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the HTTP version and the status code are not separated by a whitespace." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1200 OK\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the status code is not an integer." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 2xx OK\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the status code is out of range." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 99\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}

test "Parse - Fail when the status code is more than 3 digits." {
    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 1871 OK\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var failure = Response.parseFromStream(std.testing.allocator, reader, &read_buffer);

    expectError(error.Invalid, failure);
}
