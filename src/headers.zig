const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const std = @import("std");

pub const Header = struct {
    name: []const u8,
    value: []const u8,

    pub fn parse(buffer: []const u8, headers: []Header) ParsingError![]Header {
        var cursor: usize = 0;
        var header_cursor: usize = 0;

        while (true) {
            var remaining_bytes = buffer[cursor..];
            if (remaining_bytes.len < 2) {
                return error.Incomplete;
            }
            if (remaining_bytes[0] == '\r' and remaining_bytes[1] == '\n') {
                return headers[0..header_cursor];
            }

            if (header_cursor >= headers.len) {
                return error.TooManyHeaders;
            }

            var header_name = for (remaining_bytes) |char, i| {
                if (char == ':') {
                    var name = remaining_bytes[0..i];
                    cursor += i + 1;
                    break name;
                } else if (!is_header_name_token(char)) {
                    return error.Invalid;
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
                    break;
                } else if (is_header_value_token(char)) {
                    break;
                }
                else {
                    return error.Invalid;
                }
            } else {
                return error.Incomplete;
            }

            remaining_bytes = buffer[cursor..];
            var header_value = for (remaining_bytes) |char, i| {
                if (!is_header_value_token(char)) {
                    var value = remaining_bytes[0..i];
                    cursor += i;
                    break value;
                }
            } else {
                return error.Incomplete;
            };

            remaining_bytes = buffer[cursor..]; 
            if (remaining_bytes.len < 2) {
                return error.Incomplete;
            }
            if (remaining_bytes[0] == '\r' and remaining_bytes[1] == '\n') {
                headers[header_cursor] = Header {.name = header_name, .value = header_value};
                header_cursor += 1;
                cursor += 2;
                continue;
            }
            else {
                return error.Invalid;
            }
        }
    }
};

// ASCII codes accepted for an header's name
// Cf: Borrowed from Seamonstar's httparse library
// https://github.com/seanmonstar/httparse/blob/01e68542605d8a24a707536561c27a336d4090dc/src/lib.rs#L96
const HEADER_NAME_MAP = [_]bool {
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
//   \0                                                             \t     \n                   \r
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
//   commands
    false, true, false, true, true, true, true, true, false, false, true, true, false, true, true, false,
//   \s     !     "      #     $     %     &     '     (      )      *     +     ,      -     .     /
    true, true, true, true, true, true, true, true, true, true, false, false, false, false, false, false,
//   0     1     2     3     4     5     6     7     8     9     :      ;      <      =      >      ?
    false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   @      A     B     C     D     E     F     G     H     I     J     K     L     M     N     O
    true, true, true, true, true, true, true, true, true, true, true, false, false, false, true, true,
//   P     Q     R     S     T     U     V     W     X     Y     Z     [      \      ]      ^     _
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   `     a     b     c     d     e     f     g     h     i     j     k     l     m     n     o
    true, true, true, true, true, true, true, true, true, true, true, false, true, false, true, false,
//   p     q     r     s     t     u     v     w     x     y     z     {      |     }      ~     del
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

// ASCII codes accepted for an header's value
// Cf: Borrowed from Seamonstar's httparse library
// https://github.com/seanmonstar/httparse/blob/01e68542605d8a24a707536561c27a336d4090dc/src/lib.rs#L120
const HEADER_VALUE_MAP = [_]bool {
    false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false,
//   \0                                                             \t    \n                   \r
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
//   commands
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   \s    !     "     #     $     %     &     '     (     )     *     +     ,     -     .     /
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   0     1     2     3     4     5     6     7     8     9     :     ;     <     =     >     ?
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   @     A     B     C     D     E     F     G     H     I     J     K     L     M     N     O
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   P     Q     R     S     T     U     V     W     X     Y     Z     [     \     ]     ^     _
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
//   `     a     b     c     d     e     f     g     h     i     j     k     l     m     n     o
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
//   p     q     r     s     t     u     v     w     x     y     z     {     |     }     ~     del
//   ====== Extended ASCII (aka. obs-text) ======
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
};

fn is_header_name_token(char: u8) bool {
    return HEADER_NAME_MAP[char];
}

fn is_header_value_token(char: u8) bool {
    return HEADER_VALUE_MAP[char];
}

fn is_linear_whitespace(char: u8) bool {
    return char == ' ' or char == '\t';
}


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Parse - Single header - Success" {
    var content = "Content-Length: 10\r\n\r\n".*;
    var headers: [1]Header = undefined;

    var result = try Header.parse(&content, &headers);

    expect(std.mem.eql(u8, result[0].name, "Content-Length"));
    expect(std.mem.eql(u8, result[0].value, "10"));
}

test "Parse - Multiple headers - Success" {
    var content = "Content-Length: 10\r\nServer: Apache\r\n\r\n".*;
    var headers: [2]Header = undefined;

    var result = try Header.parse(&content, &headers);

    expect(std.mem.eql(u8, result[0].name, "Content-Length"));
    expect(std.mem.eql(u8, result[0].value, "10"));

    expect(std.mem.eql(u8, result[1].name, "Server"));
    expect(std.mem.eql(u8, result[1].value, "Apache"));
}

test "Parse - Resize header slice - Success" {
    var content = "Content-Length: 10\r\n\r\n".*;
    var headers: [2]Header = undefined;

    var result = try Header.parse(&content, &headers);

    expect(result.len == 1);
}

test "Parse - Ignore a missing whitespace between the semicolon and the header value - Success" {
    var content = "Content-Length:10\r\n\r\n".*;
    var headers: [1]Header = undefined;

    var result = try Header.parse(&content, &headers);

    expect(std.mem.eql(u8, result[0].name, "Content-Length"));
    expect(std.mem.eql(u8, result[0].value, "10"));
}

test "Parse - When the last CRLF after the headers is missing - Returns Incomplete" {
    var content = "Content-Length: 10\r\n".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);
    expectError(error.Incomplete, fail);
}

test "Parse - When a header's name does not end with a semicolon - Returns Incomplete" {
    var content = "Content-Length: 10\r\nSe".*;
    var headers: [2]Header = undefined;

    var fail = Header.parse(&content, &headers);
    expectError(error.Incomplete, fail);
}

test "Parse - When a header's value does not exist - Returns Incomplete" {
    var content = "Content-Length:".*;
    var headers: [2]Header = undefined;

    var fail = Header.parse(&content, &headers);
    expectError(error.Incomplete, fail);
}

test "Parse - When a header's value does not exist (but the whitespace after the semicolon is here) - Returns Incomplete" {
    var content = "Content-Length: ".*;
    var headers: [2]Header = undefined;

    var fail = Header.parse(&content, &headers);
    expectError(error.Incomplete, fail);
}

test "Parse - When LF is mising after a header's value - Returns Incomplete" {
    var content = "Content-Length: 10\r".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);

    expectError(error.Incomplete, fail);
}

test "Parse - When parsing more headers than expected - Returns TooManyHeaders" {
    var content = "Content-Length: 10\r\nServer: Apache\r\n\r\n".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);
    expectError(error.TooManyHeaders, fail);
}

test "Parse - Invalid character in the header's name - Returns Invalid" {
    var content = "Cont(ent-Length: 10\r\n\r\n".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);

    expectError(error.Invalid, fail);
}

test "Parse - Invalid character in the header's value after the semicolon - Returns Invalid" {
    var content = "Content-Length:\r\n".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);

    expectError(error.Invalid, fail);
}

test "Parse - Invalid character in the header's value - Returns Invalid" {
    var content = "Content-Length: 1\r0\r\n".*;
    var headers: [1]Header = undefined;

    var fail = Header.parse(&content, &headers);

    expectError(error.Invalid, fail);
}
