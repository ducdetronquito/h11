const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const parse_headers = @import("utils.zig").parse_headers;
const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;


pub const Response = struct {
    headers: Headers,
    statusCode: StatusCode,
    version: Version,

    pub fn init(headers: Headers, statusCode: StatusCode, version: Version) Response {
        return Response {
            .headers = headers,
            .statusCode = statusCode,
            .version = version,
        };
    }

    pub fn deinit(self: Response) void {
        var headers = self.headers;
        headers.deinit();
    }

    pub fn parse(allocator: *Allocator, buffer: []const u8) ParsingError!Response {
        const statusLine = readLine(buffer) orelse return error.Incomplete;
        if (statusLine.len < 12) {
            return error.Invalid;
        }

        const httpVersion = Version.from_bytes(statusLine[0..8]) orelse return error.Invalid;
        switch(httpVersion) {
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

        var _headers = try parse_headers(allocator, buffer[statusLine.len + 2..], 128);
        return Response{
            .headers = _headers,
            .version = httpVersion,
            .statusCode = statusCode,
        };
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Parse - Success" {
    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";

    var response = try Response.parse(std.testing.allocator, content);
    defer response.deinit();

    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);

    expect(response.headers.len() == 2);
}

test "Parse - Missing reason phrase" {
    var response = try Response.parse(std.testing.allocator, "HTTP/1.1 200\r\n\r\n\r\n");
    defer response.deinit();

    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);
}

test "Issue #28: Parse - Status code below 100 and above 599 are invalid" {
    var failure = Response.parse(std.testing.allocator, "HTTP/1.1 99\r\n\r\n\r\n");
    expectError(error.Invalid, failure);

    failure = Response.parse(std.testing.allocator, "HTTP/1.1 600\r\n\r\n\r\n");
    expectError(error.Invalid, failure);
}

test "Parse - When the response line does not ends with a CRLF - Returns Incomplete" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.1 200 OK");

    expectError(error.Incomplete, failure);
}

test "Parse - Response is invalid if the HTTP version is not HTTP/1.1" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.0 200 OK\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}

test "Parse - Response is invalid if the status line is less than 12 characters" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.1 99\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}

test "Parse - When the http version and the status code are not separated by a whitespace - Returns Invalid" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.1200 OK\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}

test "Parse - When the http version is not HTTP 1.1 - Returns Invalid" {
    const failure = Response.parse(std.testing.allocator, "HTTP/4.2 200\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}

test "Parse - When the status code is not an integer - Returns Invalid" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.1 2xx OK\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}

test "Issue #29: Parse - When the status code is more than 3 digits - Returns Invalid" {
    const failure = Response.parse(std.testing.allocator, "HTTP/1.1 1871 OK\r\n\r\n\r\n");

    expectError(error.Invalid, failure);
}
