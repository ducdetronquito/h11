const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const parseHeaders = @import("headers.zig").parse;
const ParsingError = @import("errors.zig").ParsingError;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

pub const Response = struct {
    allocator: Allocator,
    headers: Headers,
    statusCode: StatusCode,
    version: Version,
    raw_bytes: []const u8,

    pub fn deinit(self: Response) void {
        var headers = self.headers;
        headers.deinit();
        self.allocator.free(self.raw_bytes);
    }

    pub fn parse(allocator: Allocator, buffer: []const u8) !Response {
        const line_end = std.mem.indexOf(u8, buffer, "\r\n") orelse return error.Invalid;
        const status_line = buffer[0..line_end];
        if (status_line.len < 12) {
            return error.Invalid;
        }

        const http_version = Version.from_bytes(status_line[0..8]) orelse return error.Invalid;
        switch (http_version) {
            .Http11 => {},
            else => return error.Invalid,
        }

        if (status_line[8] != ' ') {
            return error.Invalid;
        }

        const raw_code = std.fmt.parseInt(u16, status_line[9..12], 10) catch return error.Invalid;
        const status_code = StatusCode.from_u16(raw_code) catch return error.Invalid;

        if (status_line.len > 12 and status_line[12] != ' ' and status_line[12] != '\r') {
            return error.Invalid;
        }

        var _headers = try parseHeaders(allocator, buffer[status_line.len + 2 ..], 128);
        return Response{
            .allocator = allocator,
            .headers = _headers,
            .version = http_version,
            .statusCode = status_code,
            .raw_bytes = buffer,
        };
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const dupe = std.testing.allocator.dupe;

test "Parse - Success" {
    const buffer = try dupe(u8, "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n");

    var response = try Response.parse(std.testing.allocator, buffer);
    defer response.deinit();

    try expect(response.statusCode == .Ok);
    try expect(response.version == .Http11);
    try expect(response.headers.len() == 2);
}

test "Parse - Missing reason phrase" {
    const buffer = try dupe(u8, "HTTP/1.1 200\r\n\r\n\r\n");

    var response = try Response.parse(std.testing.allocator, buffer);
    defer response.deinit();

    try expect(response.statusCode == .Ok);
    try expect(response.version == .Http11);
}

test "Parse - TooManyHeaders" {
    const buffer = "HTTP/1.1 200\r\n" ++ "Cookie: aaa\r\n" ** 129 ++ "\r\n";

    var failure = Response.parse(std.testing.allocator, buffer);

    try expectError(error.TooManyHeaders, failure);
}

test "Issue #28: Parse - Status code below 100 is invalid" {
    const content = "HTTP/1.1 99\r\n\r\n\r\n";

    var failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Issue #28: Parse - Status code above 599 is invalid" {
    const content = "HTTP/1.1 600\r\n\r\n\r\n";

    var failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - Response is invalid if the HTTP version is not HTTP/1.X" {
    const content = "HTTP/2.0 200 OK\r\n\r\n\r\n";

    const failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - Response is invalid if the status line is less than 12 characters" {
    const content = "HTTP/1.1 99\r\n\r\n\r\n";

    const failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the http version and the status code are not separated by a whitespace - Returns Invalid" {
    const content = "HTTP/1.1200 OK\r\n\r\n\r\n";

    const failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the status code is not an integer - Returns Invalid" {
    const content = "HTTP/1.1 2xx OK\r\n\r\n\r\n";

    const failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Issue #29: Parse - When the status code is more than 3 digits - Returns Invalid" {
    const content = "HTTP/1.1 1871 OK\r\n\r\n\r\n";

    const failure = Response.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}
