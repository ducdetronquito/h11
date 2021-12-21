const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

pub const Response = struct {
    status_code: StatusCode,
    version: Version,

    pub fn parse(reader: anytype, buffer: []u8) !Response {
        var status_line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return error.EndOfStream;
        if (status_line[status_line.len - 1] != '\r') {
            return error.Invalid;
        }
        status_line = buffer[0..status_line.len - 1];

        var it = std.mem.split(u8, status_line, " ");
        var bytes = it.next() orelse return error.Invalid;
        const http_version = Version.from_bytes(bytes) orelse return error.Invalid;
        if (http_version != .Http11) {
            return error.Invalid;
        }

        bytes = it.next() orelse return error.Invalid;
        const raw_code = std.fmt.parseInt(u16, bytes, 10) catch return error.Invalid;
        const status_code = StatusCode.from_u16(raw_code) catch return error.Invalid;

        return Response { .version = http_version, .status_code = status_code };
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const dupe = std.testing.allocator.dupe;

test "Parse - Success" {
    const content = "HTTP/1.1 200 OK\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const response = try Response.parse(reader, &buffer);

    try expect(response.status_code == .Ok);
    try expect(response.version == .Http11);
}

test "Parse - Missing reason phrase" {
    const content = "HTTP/1.1 200\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const response = try Response.parse(reader, &buffer);

    try expect(response.status_code == .Ok);
    try expect(response.version == .Http11);
}

test "Issue #28: Parse - Status code below 100 is invalid" {
    const content = "HTTP/1.1 99\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

test "Issue #28: Parse - Status code above 599 is invalid" {
    const content = "HTTP/1.1 600\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

test "Parse - Response is invalid if the HTTP version is not HTTP/1.X" {
    const content = "HTTP/2.0 200 OK\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

test "Parse - When the http version and the status code are not separated by a whitespace - Returns Invalid" {
    const content = "HTTP/1.1200 OK\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

test "Parse - When the status code is not an integer - Returns Invalid" {
    const content = "HTTP/1.1 2xx OK\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

test "Issue #29: Parse - When the status code is more than 3 digits - Returns Invalid" {
    const content = "HTTP/1.1 1871 OK\r\n\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Response.parse(reader, &buffer);

    try expectError(error.Invalid, failure);
}

// test "Parse - TooManyHeaders" {
//     const buffer = "HTTP/1.1 200\r\n" ++ "Cookie: aaa\r\n" ** 129 ++ "\r\n";

//     var failure = Response.parse(std.testing.allocator, buffer);

//     try expectError(error.TooManyHeaders, failure);
// }
