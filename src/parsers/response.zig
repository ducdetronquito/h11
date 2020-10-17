const Header = @import("headers.zig").Header;
const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const readVersion = @import("utils.zig").readVersion;
const StatusCode = @import("http").StatusCode;
const std = @import("std");


pub const Response = struct {
    statusCode: StatusCode,
    httpVersion: []const u8,
    headers: []?Header,

    pub fn parse(buffer: []const u8, headers: []?Header) ParsingError!Response {
        const statusLine = readLine(buffer) orelse return error.Incomplete;
        if (statusLine.len < 12) {
            return error.Invalid;
        }

        const httpVersion = try readVersion(statusLine[0..8]);

        if (statusLine[8] != ' ') {
            return error.Invalid;
        }

        const rawStatusCode = std.fmt.parseInt(u16, statusLine[9..12], 10) catch return error.Invalid;
        const statusCode = StatusCode.from_u16(rawStatusCode) catch return error.Invalid;

        if (statusLine.len > 12 and statusLine[12] != ' ' and statusLine[12] != '\r') {
            return error.Invalid;
        }

        const _headers = try Header.parse(buffer[statusLine.len + 2..], headers);

        return Response{
            .headers = _headers,
            .httpVersion = httpVersion,
            .statusCode = statusCode,
        };
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Parse - Success" {
    var headers: [2]?Header = undefined;
    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";

    const response = try Response.parse(content, &headers);

    expect(response.statusCode == .Ok);
    expect(std.mem.eql(u8, response.httpVersion, "HTTP/1.1"));

    expect(response.headers.len == 2);
    expect(std.mem.eql(u8, response.headers[0].?.name, "Server"));
    expect(std.mem.eql(u8, response.headers[0].?.value, "Apache"));
    expect(std.mem.eql(u8, response.headers[1].?.name, "Content-Length"));
    expect(std.mem.eql(u8, response.headers[1].?.value, "0"));
}

test "Parse - Missing reason phrase" {
    var headers: [0]?Header = undefined;

    const response = try Response.parse("HTTP/1.1 200\r\n\r\n\r\n", &headers);

    expect(response.statusCode == .Ok);
    expect(std.mem.eql(u8, response.httpVersion, "HTTP/1.1"));
}

test "Issue #28: Parse - Status code below 100 and above 599 are invalid" {
    var headers: [0]?Header = undefined;

    var response = Response.parse("HTTP/1.1 99\r\n\r\n\r\n", &headers);
    expectError(error.Invalid, response);

    response = Response.parse("HTTP/1.1 600\r\n\r\n\r\n", &headers);
    expectError(error.Invalid, response);
}

test "Parse - When the response line does not ends with a CRLF - Returns Incomplete" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/1.1 200 OK", &headers);

    expectError(error.Incomplete, response);
}

test "Parse - Response is invalid if the status line is less than 12 characters" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/1.1 99\r\n\r\n\r\n", &headers);

    expectError(error.Invalid, response);
}

test "Parse - When the http version and the status code are not separated by a whitespace - Returns Invalid" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/1.1200 OK\r\n\r\n\r\n", &headers);

    expectError(error.Invalid, response);
}

test "Parse - When the http version is not HTTP 1.1 - Returns Invalid" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/4.2 200\r\n\r\n\r\n", &headers);

    expectError(error.Invalid, response);
}

test "Parse - When the status code is not an integer - Returns Invalid" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/1.1 2xx OK\r\n\r\n\r\n", &headers);

    expectError(error.Invalid, response);
}

test "Issue #29: Parse - When the status code is more than 3 digits - Returns Invalid" {
    var headers: [0]?Header = undefined;

    const response = Response.parse("HTTP/1.1 1871 OK\r\n\r\n\r\n", &headers);

    expectError(error.Invalid, response);
}
