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

const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "readLine - No CRLF - Returns null" {
    var content = "Hello World!".*;

    var line = readLine(&content);

    expect(line == null);
}

test "readLine - Read line returns the entire stream" {
    var content = "Hello\r\nWorld!".*;

    var line = readLine(&content);

    expect(std.mem.eql(u8, line.?, "Hello"));
}
