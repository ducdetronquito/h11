const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const parse_headers = @import("headers.zig").parse;
const ParsingError = @import("errors.zig").ParsingError;
const readLine = @import("utils.zig").readLine;
const readVersion = @import("utils.zig").readVersion;
const std = @import("std");

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    httpVersion: []const u8,
    headers: Headers,

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }

    pub fn parse(allocator: *Allocator, buffer: []const u8) ParsingError!Request {
        const requestLine = readLine(buffer) orelse return error.Incomplete;

        const method = try readToken(requestLine);

        const target = try readUri(requestLine[method.len + 1..]);

        const httpVersion = try readVersion(requestLine[method.len + target.len + 2..]);

        var _headers = try parse_headers(allocator, buffer[requestLine.len + 2..], 128);

        return Request{
            .headers = _headers,
            .httpVersion = httpVersion,
            .method = method,
            .target = target,
        };
    }
};

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
fn readToken(buffer: []const u8) ParsingError![]const u8 {
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

fn readUri(buffer: []const u8) ParsingError![]const u8 {
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

test "Parse - Success" {
    const content = "GET http://www.example.org/where?q=now HTTP/1.1\r\nUser-Agent: h11\r\nAccept-Language: en\r\n\r\n";

    var request = try Request.parse(std.testing.allocator, content);
    defer request.deinit();

    expect(std.mem.eql(u8, request.method, "GET"));
    expect(std.mem.eql(u8, request.target, "http://www.example.org/where?q=now"));
    expect(std.mem.eql(u8, request.httpVersion, "HTTP/1.1"));

    expect(request.headers.len() == 2);
}

test "Parse - When the request line does not ends with a CRLF - Returns Incomplete" {
    const content = "GET http://www.example.org/where?q=now HTTP/1.1";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Incomplete, failure);
}

test "Parse - When the method contains an invalid character - Returns Invalid" {
    const content = "G\tET http://www.example.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Invalid, failure);
}

test "Parse - When the method and the target are not separated by a whitespace - Returns Invalid" {
    const content = "GEThttp://www.example.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Invalid, failure);
}

test "Parse - When the target contains an invalid character - Returns Invalid" {
    const content = "GET http://www.\texample.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Invalid, failure);
}

test "Parse - When the target and the http version are not separated by a whitespace - Returns Invalid" {
    const content = "GET http://www.example.org/where?q=nowHTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Invalid, failure);
}

test "Parse - When the http version is not HTTP 1.1 - Returns Invalid" {
    const content = "GET http://www.example.org/where?q=now HTTP/4.2\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    expectError(error.Invalid, failure);
}
