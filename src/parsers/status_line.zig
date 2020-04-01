const std = @import("std");
const Buffer = std.Buffer;
const ParserError = @import("errors.zig").ParserError;
const ByteStream = @import("../streams.zig").ByteStream;


pub const StatusLine = struct {
    statusCode: i32,
    reason: []const u8,

    pub fn parse(stream: *ByteStream) !StatusLine {
        // Does not have a enough data to read the HTTP version and the status code.
        var line = stream.readLine() catch return ParserError.NeedData;

        if (line.len < 12) {
            return ParserError.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return ParserError.BadFormat;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return ParserError.BadFormat;
        const reason = line[13..];

        return StatusLine { .statusCode = statusCode, .reason = reason };
    }
};


const testing = std.testing;

test "Parse - When the status line does not end with a CRLF - Returns error NeedData" {
    var stream = ByteStream.init("HTTP/1.1 200 OK");
    var statusLine = StatusLine.parse(&stream);

    testing.expectError(ParserError.NeedData, statusLine);
}

test "Parse - When the http version is not HTTP/1.1 - Returns error BadFormat" {
    var stream = ByteStream.init("HTTP/2.0 200 OK\r\n");
    var statusLine = StatusLine.parse(&stream);

    testing.expectError(ParserError.BadFormat, statusLine);
}

test "Parse - When the status code is not made of 3 digits - Returns error BadFormat" {
    var stream = ByteStream.init("HTTP/1.1 20x OK\r\n");
    var statusLine = StatusLine.parse(&stream);

    testing.expectError(ParserError.BadFormat, statusLine);
}

test "Parse - Success" {
    var stream = ByteStream.init("HTTP/1.1 405 Method Not Allowed\r\n");
    const statusLine = try StatusLine.parse(&stream);

    testing.expect(statusLine.statusCode == 405);
    testing.expect(std.mem.eql(u8, statusLine.reason, "Method Not Allowed"));
}
