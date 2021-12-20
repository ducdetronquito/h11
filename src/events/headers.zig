const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const ParsingError = @import("errors.zig").ParsingError;
const std = @import("std");

pub fn parse(allocator: Allocator, buffer: []const u8, max_headers: usize) ParsingError!Headers {
    var remaining_bytes = buffer[0..];
    var headers = Headers.init(allocator);
    errdefer headers.deinit();

    while (true) {
        if (remaining_bytes.len < 2) {
            return error.Invalid;
        }

        if (remaining_bytes[0] == '\r' and remaining_bytes[1] == '\n') {
            break;
        }

        if (headers.len() >= max_headers) {
            return error.TooManyHeaders;
        }

        var name_end = std.mem.indexOfScalar(u8, remaining_bytes, ':') orelse return error.Invalid;
        var name = remaining_bytes[0..name_end];
        remaining_bytes = remaining_bytes[name_end + 1 ..];

        var value_end = std.mem.indexOf(u8, remaining_bytes, "\r\n") orelse return error.Invalid;
        var value = remaining_bytes[0..value_end];
        if (std.ascii.isBlank(value[0])) {
            value = value[1..];
        }

        try headers.append(name, value);
        remaining_bytes = remaining_bytes[value_end + 2 ..];
    }

    return headers;
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Parse - Single header - Success" {
    const content = "Content-Length: 10\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    try expectEqualStrings(header.name.raw(), "Content-Length");
    try expectEqualStrings(header.value, "10");
}

test "Parse - No header - Success" {
    const content = "\r\n";

    var headers = try parse(std.testing.allocator, content, 1);
    defer headers.deinit();

    try expect(headers.len() == 0);
}

test "Parse - Multiple headers - Success" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 2);
    defer headers.deinit();

    const content_length = headers.items()[0];
    try expectEqualStrings(content_length.name.raw(), "Content-Length");
    try expectEqualStrings(content_length.value, "10");

    const server = headers.items()[1];
    try expectEqualStrings(server.name.raw(), "Server");
    try expectEqualStrings(server.value, "Apache");
}

test "Parse - Ignore a missing whitespace between the semicolon and the header value - Success" {
    const content = "Content-Length:10\r\n\r\n";

    var headers = try parse(std.testing.allocator, content, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    try expectEqualStrings(header.name.raw(), "Content-Length");
    try expectEqualStrings(header.value, "10");
}

test "Parse - When the last CRLF after the headers is missing - Returns Invalid" {
    const content = "Content-Length: 10\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.Invalid, fail);
}

test "Parse - When a header's name does not end with a semicolon - Returns Invalid" {
    const content = "Content-Length";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.Invalid, fail);
}

test "Parse - When a header's value does not exist - Returns Invalid" {
    const content = "Content-Length:";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.Invalid, fail);
}

test "Parse - When parsing more headers than expected - Returns TooManyHeaders" {
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.TooManyHeaders, fail);
}

test "Parse - Invalid character in the header's name - Returns InvalidHeaderName" {
    const content = "Cont(ent-Length: 10\r\n\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.InvalidHeaderName, fail);
}

test "Parse - Invalid character in the header's value - Returns InvalidHeaderValue" {
    const content = "My-Header: I\nvalid\r\n";

    const fail = parse(std.testing.allocator, content, 1);

    try expectError(error.InvalidHeaderValue, fail);
}
