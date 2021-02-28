const Buffer = std.ArrayList(u8);
const Data = @import("events/events.zig").Data;
const Event = @import("events/events.zig").Event;
const std = @import("std");
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const Response = @import("events/events.zig").Response;
const StatusCode = @import("http").StatusCode;

pub const Error = error{
    BodyTooshort,
    BodyTooLarge,
};

pub const ContentLengthReader = struct {
    expected_length: usize,
    read_bytes: usize,

    pub fn init(expected_length: usize) BodyReader {
        return BodyReader {
            .ContentLength = ContentLengthReader{ .expected_length = expected_length, .read_bytes = 0 },
        };
    }

    pub fn read(self: *ContentLengthReader, reader: anytype, buffer: []u8) !Event {
        if (self.read_bytes == self.expected_length) {
            return .EndOfMessage;
        }

        var count = try reader.read(buffer);
        if (count == 0) {
            return Error.BodyTooshort;
        }

        self.read_bytes += count;
        if (self.read_bytes > self.expected_length) {
            return Error.BodyTooLarge;
        }
        return Event{ .Data = Data{ .bytes = buffer[0..count] } };
    }
};

pub const BodyReaderType = enum {
    ContentLength,
    NoContent,
};

pub const BodyReader = union(BodyReaderType) {
    ContentLength: ContentLengthReader,
    NoContent: void,

    pub fn default() BodyReader {
        return BodyReader{ .NoContent = undefined };
    }

    pub fn read(self: *BodyReader, reader: anytype, buffer: []u8) !Event {
        return switch (self.*) {
            .ContentLength => |*body_reader| try body_reader.read(reader, buffer),
            .NoContent => .EndOfMessage,
        };
    }

    // Determines the appropriate response body length.
    // Cf: RFC 7230 section 3.3.3, https://tools.ietf.org/html/rfc7230#section-3.3.3
    // TODO:
    // - Handle transfert encoding (chunked, compress, deflate, gzip)
    pub fn frame(requestMethod: Method, status_code: StatusCode, headers: Headers) !BodyReader {
        var rawStatusCode = @enumToInt(status_code);
        const hasNoContent = (requestMethod == .Head or rawStatusCode < 200 or status_code == .NoContent or status_code == .NotModified);

        if (hasNoContent) {
            return .NoContent;
        }

        const isSuccessfulConnectRequest = (rawStatusCode < 300 and rawStatusCode > 199 and requestMethod == .Connect);
        if (isSuccessfulConnectRequest) {
            return .NoContent;
        }

        var contentLength: usize = 0;
        var contentLengthHeader = headers.get("Content-Length");

        if (contentLengthHeader != null) {
            contentLength = std.fmt.parseInt(usize, contentLengthHeader.?.value, 10) catch return error.RemoteProtocolError;
        }

        return ContentLengthReader.init(contentLength);
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Frame Body - A HEAD request has no content" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Head, .Ok, headers);

    expect(body_reader == .NoContent);
}

test "Frame Body - Informational responses (1XX status code) have no content" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Get, .Continue, headers);

    expect(body_reader == .NoContent);
}

test "Frame Body - Response with a 204 No Content status code has no content" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Get, .NoContent, headers);

    expect(body_reader == .NoContent);
}

test "Frame Body - Response with 304 Not Modified status code has no content" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Get, .NotModified, headers);

    expect(body_reader == .NoContent);
}

test "Frame Body - A successful response (2XX) to a CONNECT request has no content" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Connect, .Ok, headers);

    expect(body_reader == .NoContent);
}

test "NoContentReader - Returns EndOfMessage." {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var body_reader = BodyReader{ .NoContent = undefined };

    var buffer: [0]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);

    expect(event == .EndOfMessage);
}

test "ContentLengthReader - Fail when the body is shorter than expected." {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader.init(14);
    var buffer: [32]u8 = undefined;
    const failure = body_reader.read(reader, &buffer);

    expectError(error.BodyTooshort, failure);
}

test "ContentLengthReader - Read" {
    const content = "Gotta go fast!";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader.init(14);
    var buffer: [32]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);

    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ContentLengthReader - Read in several call" {
    const content = "a" ** 32 ++ "b" ** 32 ++ "c" ** 32;
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader.init(96);


    var buffer: [32]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "a" ** 32));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "b" ** 32));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "c" ** 32));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}
