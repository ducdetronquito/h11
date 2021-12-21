const std = @import("std");


pub const Header = struct {
    name: []const u8,
    value: []const u8,

    pub fn parse(reader: anytype, buffer: []u8) !?Header {
        var line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return error.EndOfStream;
        if (line[line.len - 1] != '\r') {
            return error.Invalid;
        }
        line = line[0..line.len - 1];

        if (line.len == 0) {
            return null;
        }

        var name: []u8 = "";
        for (line) |char, i| {
            if (INVALID_HEADER_NAME_MAP[char]) {
                if (char == ':') {
                    name = line[0..i];
                    break;
                }
                return error.InvalidHeader;
            }
        } else {
            return error.InvalidHeader;
        }

        var value = line[name.len + 1..];
        if (value.len == 0) {
            return Header { .name = name, .value = value };
        }

        if (std.ascii.isBlank(value[0])) {
            value = value[1..];
        }

        for (value) |char| {
            if (INVALID_HEADER_VALUE_MAP[char]) {
                return error.InvalidHeader;
            }
        }

        return Header {.name = name, .value = value };
    }
};

// ASCII codes rejected for an header's name
const INVALID_HEADER_NAME_MAP = [_]bool{
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, false, true, false, false, false, false, false, true, true, false, false, true, false, false, true,
    false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, true,
    true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, true, false, true, false, true,
    // ====== Extended ASCII ======
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
};

// ASCII codes rejected for an header's value
const INVALID_HEADER_VALUE_MAP = [_]bool{
    true, true, true, true, true, true, true, true, true, false,  true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true,
    // ====== Extended ASCII ======
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
};


const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Parse - Single header - Success" {
    const content = "Content-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try Header.parse(reader, &buffer);

    try expectEqualStrings(header.?.name, "Content-Length");
    try expectEqualStrings(header.?.value, "10");
}

test "Parse - No header - Success" {
    const content = "\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try Header.parse(reader, &buffer);

    try expect(header == null);
}

test "Parse - Ignore a missing whitespace between the semicolon and the header value - Success" {
    const content = "Content-Length:10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try Header.parse(reader, &buffer);

    try expectEqualStrings(header.?.name, "Content-Length");
    try expectEqualStrings(header.?.value, "10");
}

test "Parse - When a header's value is a whitespace - Success" {
    const content = "Content-Length: \r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try Header.parse(reader, &buffer);

    try expectEqualStrings(header.?.name, "Content-Length");
    try expectEqualStrings(header.?.value, "");
}

test "Parse - When a header's value is empty - Success" {
    const content = "Content-Length:\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const header = try Header.parse(reader, &buffer);

    try expectEqualStrings(header.?.name, "Content-Length");
    try expectEqualStrings(header.?.value, "");
}

test "Parse - Empty string - Returns EndOfStream" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Header.parse(reader, &buffer);

    try expectError(error.EndOfStream, failure);
}

test "Parse - When a header's name does not end with a semicolon - Returns InvalidHeader" {
    const content = "Content-Length\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Header.parse(reader, &buffer);

    try expectError(error.InvalidHeader, failure);
}

test "Parse - Invalid character in the header's name - Returns InvalidHeaderName" {
    const content = "Cont(ent-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Header.parse(reader, &buffer);

    try expectError(error.InvalidHeader, failure);
}

test "Parse - Invalid character in the header's value - Returns InvalidHeaderValue" {
    const content = "My-Header: I\rvalid\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var buffer: [100]u8 = undefined;

    const failure = Header.parse(reader, &buffer);

    try expectError(error.InvalidHeader, failure);
}
