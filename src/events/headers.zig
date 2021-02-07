const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const Headers = @import("http").Headers;
const std = @import("std");


pub fn parse(allocator: *Allocator, reader: anytype, buffer: []u8, max_headers: usize) !Headers {
    var cursor: usize = 0;
    var headers = Headers.init(allocator);
    errdefer headers.deinit();

    while (true) {
        var line = (try reader.readUntilDelimiterOrEof(buffer[cursor..], '\n')) orelse return error.Invalid;
        cursor += line.len;

        if (line[line.len - 1] != '\r') {
            return error.Invalid;
        }

        line = line[0..line.len - 1];

        if (line.len == 0) {
            break;
        }

        if (headers.len() >= max_headers) {
            return error.TooManyHeaders;
        }

        const delimiter = std.mem.indexOf(u8, line, ":") orelse return error.Invalid;

        const name = line[0..delimiter];
        var value = line[delimiter + 1..];
        if (ascii.isBlank(value[0])) {
            value = value[1..];
        }

        try headers.append(name, value);
    }

    return headers;
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Parse - Single header - Success" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    
    var headers = try parse(std.testing.allocator, reader, &read_buffer, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    var name = header.name.raw();
    var value = header.value;

    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "Parse - Multiple headers - Success" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var headers = try parse(std.testing.allocator, reader, &read_buffer, 2);
    defer headers.deinit();

    const content_length = headers.items()[0];
    expect(std.mem.eql(u8, content_length.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, content_length.value, "10"));

    const server = headers.items()[1];
    expect(std.mem.eql(u8, server.name.raw(), "Server"));
    expect(std.mem.eql(u8, server.value, "Apache"));
}

test "Parse - Ignore a missing whitespace between the semicolon and the header value - Success" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length:10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var headers = try parse(std.testing.allocator, reader, &read_buffer, 1);
    defer headers.deinit();

    const header = headers.items()[0];
    expect(std.mem.eql(u8, header.name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, header.value, "10"));
}

test "Parse - When the last CRLF after the headers is missing - Invalid" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: 10\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.Invalid, fail);
}

test "Parse - When a header's name does not end with a semicolon - Invalid" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.Invalid, fail);
}

test "Parse - When a header's value does not exist - Invalid" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length:";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.Invalid, fail);
}

test "Parse - When a header's value does not exist (but the whitespace after the semicolon is here) - Invalid" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: ";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.Invalid, fail);
}

test "Parse - When LF is mising after a header's value - Invalid" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: 10\r";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);


    expectError(error.Invalid, fail);
}

test "Parse - When parsing more headers than expected - Returns TooManyHeaders" {
    var read_buffer: [100]u8 = undefined;
    const content = "Content-Length: 10\r\nServer: Apache\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.TooManyHeaders, fail);
}

test "Parse - Invalid character in the header's name - Returns InvalidHeaderName" {
    var read_buffer: [100]u8 = undefined;
    const content = "Cont(ent-Length: 10\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.InvalidHeaderName, fail);
}

test "Parse - Invalid character in the header's value - Returns InvalidHeaderValue" {
    var read_buffer: [100]u8 = undefined;
    const content = "My-Header: I\rvalid\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    const fail = parse(std.testing.allocator, reader, &read_buffer, 1);

    expectError(error.InvalidHeaderValue, fail);
}
