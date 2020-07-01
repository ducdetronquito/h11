const ParsingError = @import("errors.zig").ParsingError;

// Read a buffer until a CRLF (\r\n) is found.
// NB: The CRLF is not returned.
pub fn readLine(buffer: []const u8) ?[]const u8 {
    var cursor: u32 = 0;

    for (buffer) |item, i| {
        if (item == '\n' and buffer[i - 1] == '\r') {
            return buffer[0..i - 1];
        }
    }
    return null;
}


pub fn readVersion(buffer: []const u8) ParsingError![]const u8 {
    if (std.mem.eql(u8, buffer, "HTTP/1.1")) {
        return buffer;
    }

    return error.Invalid;
}


const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "readLine - No CRLF - Returns null" {
    var content = "Hello World!".*;

    var line = readLine(&content);

    expect(line == null);
}

test "readLine - Success" {
    var content = "Hello\r\nWorld!".*;

    var line = readLine(&content);

    expect(std.mem.eql(u8, line.?, "Hello"));
}

test "readVersion - Success" {
    var content = "HTTP/1.1".*;

    var version = try readVersion(&content);

    expect(std.mem.eql(u8, version, "HTTP/1.1"));
}

test "readVersion - Anything different that HTTP 1.1 - Returns Invalid" {
    var content = "HTTP/4.2".*;

    var version = readVersion(&content);

    expectError(error.Invalid, version);
}
