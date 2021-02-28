const ParsingError = @import("errors.zig").ParsingError;
const std = @import("std");

// Read a buffer until a CRLF (\r\n) is found.
// NB: The CRLF is not returned.
pub fn readLine(buffer: []const u8) ?[]const u8 {
    var cursor = for (buffer) |char, i| {
        if (char == '\r') {
            break i;
        }
    } else {
        return null;
    };

    for (buffer[cursor..]) |char, i| {
        if (char == '\n') {
            return buffer[0 .. cursor + i - 1];
        }
    } else {
        return null;
    }
}

// ASCII codes accepted for an URI
// Cf: Borrowed from Seamonstar's httparse library.
// https://github.com/seanmonstar/httparse/blob/01e68542605d8a24a707536561c27a336d4090dc/src/lib.rs#L63
const URI_MAP = [_]bool{
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    //   \0                                                             \t     \n                   \r
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    //   commands
    false, true,  false, true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,
    //   \s     !     "      #     $     %     &     '     (     )     *     +     ,     -     .     /
    true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  false, true,  false, true,
    //   0     1     2     3     4     5     6     7     8     9     :     ;     <      =     >      ?
    true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,
    //   @     A     B     C     D     E     F     G     H     I     J     K     L     M     N     O
    true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,
    //   P     Q     R     S     T     U     V     W     X     Y     Z     [     \     ]     ^     _
    true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,
    //   `     a     b     c     d     e     f     g     h     i     j     k     l     m     n     o
    true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  false,
    //   p     q     r     s     t     u     v     w     x     y     z     {     |     }     ~     del
    //   ====== Extended ASCII (aka. obs-text) ======
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
};

fn is_uri_token(char: u8) bool {
    return URI_MAP[char];
}

pub fn readUri(buffer: []const u8) ParsingError![]const u8 {
    for (buffer) |char, i| {
        if (char == ' ') {
            return buffer[0..i];
        }
        if (!is_uri_token(char)) {
            return error.Invalid;
        }
    }
    return error.Invalid;
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "ReadLine - No CRLF - Returns null" {
    const content = "Hello World!";

    const line = readLine(content);

    expect(line == null);
}

test "ReadLine - Success" {
    const content = "Hello\r\nWorld!";

    const line = readLine(content);

    expect(std.mem.eql(u8, line.?, "Hello"));
}

test "ReadLine - Carriage-return only returns null" {
    const content = "\r";

    const line = readLine(content);

    expect(line == null);
}
