const std = @import("std");

pub fn readUntilBlankLine(data: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] != '\r') {
            i += 1;
            continue;
        }

        if (data.len - i < 4) {
            return null;
        }

        i += 4;
        if (std.mem.eql(u8, data[i - 3 .. i], "\n\r\n")) {
            return data[0..i];
        }
    }

    return null;
}

const expect = std.testing.expect;

test "ReadUntilBlankLine - Success" {
    var result = readUntilBlankLine("HTTP/1.1 200 OK\r\n\r\n");

    expect(std.mem.eql(u8, result.?, "HTTP/1.1 200 OK\r\n\r\n"));
}

test "ReadUntilBlankLine - Not Found" {
    var result = readUntilBlankLine("");
    expect(result == null);

    result = readUntilBlankLine("HTTP/1.1 200 OK");
    expect(result == null);

    result = readUntilBlankLine("HTTP/1.1 200 OK\r");
    expect(result == null);

    result = readUntilBlankLine("HTTP/1.1 200 OK\r\n");
    expect(result == null);

    result = readUntilBlankLine("HTTP/1.1 200 OK\r\n\r");
    expect(result == null);
}
