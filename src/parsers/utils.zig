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


test "readLine - No CRLF - Returns null" {
    const content = "Hello World!";

    const line = readLine(content);

    expect(line == null);
}

test "readLine - Success" {
    const content = "Hello\r\nWorld!";

    const line = readLine(content);

    expect(std.mem.eql(u8, line.?, "Hello"));
}

test "readVersion - Success" {
    const content = "HTTP/1.1";

    const version = try readVersion(content);

    expect(std.mem.eql(u8, version, "HTTP/1.1"));
}

test "readVersion - Anything different that HTTP 1.1 - Returns Invalid" {
    const content = "HTTP/4.2";

    const version = readVersion(content);

    expectError(error.Invalid, version);
}
