const Header = @import("headers.zig").Header;
const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const readVersion = @import("utils.zig").readVersion;
const std = @import("std");

pub const Response = struct {
    statusCode: u8,
    httpVersion: []const u8,
    headers: []Header,

    pub fn parse(buffer: []const u8, headers: []Header) ParsingError!Response {
        const statusLine = readLine(buffer) orelse return error.Incomplete;

        const httpVersion = try readVersion(statusLine[0..8]);

        if (statusLine[8] != ' ') {
            return error.Invalid;
        }

        const statusCode = std.fmt.parseInt(u8, statusLine[9..12], 10) catch return error.Invalid;

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
    var headers: [2]Header = undefined;
    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";

    const response = try Response.parse(content, &headers);

    expect(response.statusCode == 200);
    expect(std.mem.eql(u8, response.httpVersion, "HTTP/1.1"));

    expect(response.headers.len == 2);
    expect(std.mem.eql(u8, response.headers[0].name, "Server"));
    expect(std.mem.eql(u8, response.headers[0].value, "Apache"));
    expect(std.mem.eql(u8, response.headers[1].name, "Content-Length"));
    expect(std.mem.eql(u8, response.headers[1].value, "0"));
}

test "Parse - With missing reason phrase - Success" {
    var headers: [0]Header = undefined;
    const content = "HTTP/1.1 200\r\n\r\n\r\n";

    const response = try Response.parse(content, &headers);

    expect(response.statusCode == 200);
    expect(std.mem.eql(u8, response.httpVersion, "HTTP/1.1"));
}

test "Parse - When the response line does not ends with a CRLF - Returns Incomplete" {
    var headers: [0]Header = undefined;
    const content = "HTTP/1.1 200 OK";

    const response = Response.parse(content, &headers);

    expectError(error.Incomplete, response);
}

test "Parse - When the http version and the status code are not separated by a whitespace - Returns Invalid" {
    var headers: [0]Header = undefined;
    const content = "HTTP/1.1200 OK\r\n\r\n\r\n";

    const response = Response.parse(content, &headers);

    expectError(error.Invalid, response);
}

test "Parse - When the http version is not HTTP 1.1 - Returns Invalid" {
    var headers: [0]Header = undefined;
    const content = "HTTP/4.2 200\r\n\r\n\r\n";

    const response = Response.parse(content, &headers);

    expectError(error.Invalid, response);
}

test "Parse - When the status code is not an integer - Returns Invalid" {
    var headers: [0]Header = undefined;
    const content = "HTTP/1.1 2xx OK\r\n\r\n\r\n";

    const response = Response.parse(content, &headers);

    expectError(error.Invalid, response);
}
