const Header = @import("http").Header;
const std = @import("std");

pub inline fn readLine(reader: anytype, buffer: []u8) ![]u8 {
    var line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return error.EndOfStream;
    if (line[line.len - 1] != '\r') {
        return error.Invalid;
    }
    return line[0 .. line.len - 1];
}

pub inline fn parseHeader(reader: anytype, buffer: []u8) !?Header {
    const line = try readLine(reader, buffer);
    if (line.len == 0) {
        return null;
    }

    var it = std.mem.split(u8, line, ":");
    const name = it.next() orelse return error.InvalidHeaderName;
    var value = it.next() orelse return error.InvalidHeaderName;
    value = trimBlank(value);

    return try Header.init(name, value);
}

inline fn trimBlank(value: []const u8) []const u8 {
    var i: usize = 0;
    while (i < value.len) {
        if (!std.ascii.isBlank(value[i])) {
            break;
        }
        i += 1;
    }
    return value[i..];
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "parseHeader - Success" {
    const content = "Content-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try parseHeader(reader, &buffer);

    try expectEqualStrings(header.?.name.raw(), "Content-Length");
    try expectEqualStrings(header.?.value, "10");
}

test "parseHeader - Empty header line - Return null" {
    const content = "\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try parseHeader(reader, &buffer);

    try expect(header == null);
}

test "parseHeader - Ignore a missing whitespace between the semicolon and the header value" {
    const content = "Content-Length:10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try parseHeader(reader, &buffer);

    try expectEqualStrings(header.?.name.raw(), "Content-Length");
    try expectEqualStrings(header.?.value, "10");
}

test "parseHeader - Fail when the header value only contains blanks" {
    const content = "Content-Length:   \t \r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.InvalidHeaderValue, failure);
}

test "parseHeader - Fail when the header value is empty" {
    const content = "Content-Length:\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.InvalidHeaderValue, failure);
}

test "parseHeader - Fail when line is empty" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.EndOfStream, failure);
}

test "parseHeader - Fail when a header's name does not end with a semicolon" {
    const content = "Content-Length\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.InvalidHeaderName, failure);
}

test "parseHeader - Invalid character in the header's name - Returns InvalidHeaderName" {
    const content = "Cont(ent-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.InvalidHeaderName, failure);
}

test "parseHeader - Invalid character in the header's value - Returns InvalidHeaderValue" {
    const content = "My-Header: I\rvalid\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = parseHeader(reader, &buffer);

    try expectError(error.InvalidHeaderValue, failure);
}
