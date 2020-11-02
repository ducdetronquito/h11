const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const ParsingError = @import("errors.zig").ParsingError;
const std = @import("std");


pub fn parse_headers(allocator: *Allocator, buffer: []const u8, max_headers: usize) ParsingError!Headers {
    var cursor: usize = 0;
    var headers = Headers.init(allocator);
    errdefer headers.deinit();

    while (true) {
        var remaining_bytes = buffer[cursor..];
        if (remaining_bytes.len < 2) {
            return error.Incomplete;
        }

        if (remaining_bytes[0] == '\r' and remaining_bytes[1] == '\n') {
            break;
        }

        if (headers.len() >= max_headers) {
            return error.TooManyHeaders;
        }

        const header_name = for (remaining_bytes) |char, i| {
            if (char == ':') {
                const name = remaining_bytes[0..i];
                cursor += i + 1;
                break name;
            }
        } else {
            return error.Incomplete;
        };

        // Consume the optional whitespace between the semicolon and the header value
        // Cf: https://tools.ietf.org/html/rfc7230#section-3.2
        remaining_bytes = buffer[cursor..];
        for (remaining_bytes) |char, i| {
            if (is_linear_whitespace(char)) {
                cursor += 1;
            }
            break;
        } else {
            return error.Incomplete;
        }

        remaining_bytes = buffer[cursor..];
        const header_value = for (remaining_bytes) |char, i| {
            if (char == '\r') {
                cursor += i;
                break remaining_bytes[0..i];
            }
        } else {
            return error.Incomplete;
        };

        remaining_bytes = buffer[cursor..];
        if (remaining_bytes.len < 2) {
            return error.Incomplete;
        }
        if (remaining_bytes[0] == '\r' and remaining_bytes[1] == '\n') {
            try headers.append(header_name, header_value);
            cursor += 2;
        }
        else {
            return error.Invalid;
        }
    }

    return headers;
}


inline fn is_linear_whitespace(char: u8) bool {
    return char == ' ' or char == '\t';
}


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
            return buffer[0..cursor + i - 1];
        }
    } else {
        return null;
    }
}


// Determines if a character is a token character.
//
// Cf: https://tools.ietf.org/html/rfc7230#section-3.2.6
// > token          = 1*tchar
// >
// > tchar          = "!" / "#" / "$" / "%" / "&" / "'" / "*"
// >                / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
// >                / DIGIT / ALPHA
// >                ; any VCHAR, except delimiters
fn is_token(char: u8) bool {
    return char > 0x1f and char < 0x7f;
}

// Returns a token
// Cf: https://tools.ietf.org/html/rfc7230#section-3.2.6
pub fn readToken(buffer: []const u8) ParsingError![]const u8 {
    for (buffer) |char, i| {
        if (char == ' ') {
            return buffer[0..i];
        }
        if (!is_token(char)) {
            return error.Invalid;
        }
    }
    return error.Invalid;
}

// ASCII codes accepted for an URI
// Cf: Borrowed from Seamonstar's httparse library.
// https://github.com/seanmonstar/httparse/blob/01e68542605d8a24a707536561c27a336d4090dc/src/lib.rs#L63
const URI_MAP = [_]bool {
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
//   \0                                                             \t     \n                   \r
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
//   commands
    false, true, false, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   \s     !     "      #     $     %     &     '     (     )     *     +     ,     -     .     /
    true, true, true, true, true, true, true, true, true, true, true, true, false, true, false, true,
//   0     1     2     3     4     5     6     7     8     9     :     ;     <      =     >      ?
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   @     A     B     C     D     E     F     G     H     I     J     K     L     M     N     O
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   P     Q     R     S     T     U     V     W     X     Y     Z     [     \     ]     ^     _
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   `     a     b     c     d     e     f     g     h     i     j     k     l     m     n     o
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
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

test "ParseHeaders - Single header - Success" {
    const content = "Content-Length: 10\r\n\r\n";

    var headers = try parse_headers(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "ParseHeaders - Multiple headers - Success" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    var headers = try parse_headers(std.testing.allocator, content, 2);
    defer headers.deinit();

    const content_length = headers.items()[0];
    expect(std.mem.eql(u8, content_length.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, content_length.value, "10"));

    const server = headers.items()[1];
    expect(std.mem.eql(u8, server.name.raw(), "Server"));
    expect(std.mem.eql(u8, server.value, "Apache"));
}

test "ParseHeaders - Ignore a missing whitespace between the semicolon and the header value - Success" {
    const content = "Content-Length:10\r\n\r\n";

    var headers = try parse_headers(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "ParseHeaders - When the last CRLF after the headers is missing - Returns Incomplete" {
    const content = "Content-Length: 10\r\n";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "ParseHeaders - When a header's name does not end with a semicolon - Returns Incomplete" {
    const content = "Content-Length";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "ParseHeaders - When a header's value does not exist - Returns Incomplete" {
    const content = "Content-Length:";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "ParseHeaders - When a header's value does not exist (but the whitespace after the semicolon is here) - Returns Incomplete" {
    const content = "Content-Length: ";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "ParseHeaders - When LF is mising after a header's value - Returns Incomplete" {
    const content = "Content-Length: 10\r";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "ParseHeaders - When parsing more headers than expected - Returns TooManyHeaders" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.TooManyHeaders, fail);
}

test "ParseHeaders - Invalid character in the header's name - Returns Invalid" {
    const content = "Cont(ent-Length: 10\r\n\r\n";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Invalid, fail);
}

test "ParseHeaders - Invalid character in the header's value - Returns Invalid" {
    const content = "Content-Length: 1\r0\r\n";

    const fail = parse_headers(std.testing.allocator, content, 1);

    expectError(error.Invalid, fail);
}


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
