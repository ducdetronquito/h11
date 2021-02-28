const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const ParsingError = @import("errors.zig").ParsingError;
const std = @import("std");

pub fn parse(allocator: *Allocator, buffer: []const u8, max_headers: usize) ParsingError!Headers {
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
            if (std.ascii.isBlank(char)) {
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
        } else {
            return error.Invalid;
        }
    }

    return headers;
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Parse - Single header - Success" {
    const content = "Content-Length: 10\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "Parse - Multiple headers - Success" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 2);
    defer headers.deinit();

    const content_length = headers.items()[0];
    expect(std.mem.eql(u8, content_length.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, content_length.value, "10"));

    const server = headers.items()[1];
    expect(std.mem.eql(u8, server.name.raw(), "Server"));
    expect(std.mem.eql(u8, server.value, "Apache"));
}

test "Parse - Ignore a missing whitespace between the semicolon and the header value - Success" {
    const content = "Content-Length:10\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "Parse - When the last CRLF after the headers is missing - Returns Incomplete" {
    const content = "Content-Length: 10\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "Parse - When a header's name does not end with a semicolon - Returns Incomplete" {
    const content = "Content-Length";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "Parse - When a header's value does not exist - Returns Incomplete" {
    const content = "Content-Length:";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "Parse - When a header's value does not exist (but the whitespace after the semicolon is here) - Returns Incomplete" {
    const content = "Content-Length: ";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "Parse - When LF is mising after a header's value - Returns Incomplete" {
    const content = "Content-Length: 10\r";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.Incomplete, fail);
}

test "Parse - When parsing more headers than expected - Returns TooManyHeaders" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.TooManyHeaders, fail);
}

test "Parse - Invalid character in the header's name - Returns InvalidHeaderName" {
    const content = "Cont(ent-Length: 10\r\n\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.InvalidHeaderName, fail);
}

test "Parse - Invalid character in the header's value - Returns InvalidHeaderValue" {
    const content = "My-Header: I\nvalid\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    expectError(error.InvalidHeaderValue, fail);
}