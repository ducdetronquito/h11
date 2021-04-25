const ChunkedReader = @import("chunked_reader.zig").ChunkedReader;
const ContentLengthReader = @import("content_length_reader.zig").ContentLengthReader;
const Event = @import("../events/events.zig").Event;
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const StatusCode = @import("http").StatusCode;
const std = @import("std");

pub const BodyReaderType = enum {
    Chunked,
    ContentLength,
    NoContent,
};

pub const BodyReader = union(BodyReaderType) {
    Chunked: ChunkedReader(8192),
    ContentLength: ContentLengthReader,
    NoContent: void,

    pub fn default() BodyReader {
        return BodyReader{ .NoContent = undefined };
    }

    pub fn read(self: *BodyReader, reader: anytype, buffer: []u8) !Event {
        return switch (self.*) {
            .Chunked => |*chunked_reader| try chunked_reader.read(reader, buffer),
            .ContentLength => |*body_reader| try body_reader.read(reader, buffer),
            .NoContent => .EndOfMessage,
        };
    }

    // Determines the appropriate response body length.
    // Cf: RFC 7230 section 3.3.3, https://tools.ietf.org/html/rfc7230#section-3.3.3
    // TODO:
    // - Handle transfert encoding (compress, deflate, gzip)
    // - Should we deal with chunked not being the final encoding ?
    //   Currently it is considered to be an error (UnknownTranfertEncoding).
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

        var transfert_encoding = headers.get("Transfer-Encoding");
        if (transfert_encoding != null) {
            if (!std.mem.endsWith(u8, transfert_encoding.?.value, "chunked")) {
                return error.UnknownTranfertEncoding;
            }
            return BodyReader{.Chunked = ChunkedReader(8192){} };
        }

        var contentLength: usize = 0;
        var contentLengthHeader = headers.get("Content-Length");

        if (contentLengthHeader != null) {
            contentLength = std.fmt.parseInt(usize, contentLengthHeader.?.value, 10) catch return error.RemoteProtocolError;
        }

        return BodyReader{.ContentLength = ContentLengthReader{.expected_length = contentLength}};
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

test "Frame Body - Use a ChunkReader when chunked is the final encoding" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Transfer-Encoding", "gzip, chunked");

    var body_reader = try BodyReader.frame(.Get, .Ok, headers);

    expect(body_reader == .Chunked);
}

test "Frame Body - Fail when chunked is not the final encoding" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Transfer-Encoding", "chunked, gzip");

    const failure = BodyReader.frame(.Get, .Ok, headers);

    expectError(error.UnknownTranfertEncoding, failure);
}

test "Frame Body - By default use a ContentLengthReader with a length of 0" {
    var headers = Headers.init(std.testing.allocator);

    var body_reader = try BodyReader.frame(.Get, .Ok, headers);

    expect(body_reader == .ContentLength);
    expect(body_reader.ContentLength.expected_length == 0);
}

test "Frame Body - Use a ContentLengthReader with the provided length" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Content-Length", "15");

    var body_reader = try BodyReader.frame(.Get, .Ok, headers);

    expect(body_reader == .ContentLength);
    expect(body_reader.ContentLength.expected_length == 15);
}

test "Frame Body - Fail when the provided content length is invalid" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Content-Length", "XXX");

    const failure = BodyReader.frame(.Get, .Ok, headers);

    expectError(error.RemoteProtocolError, failure);
}

test "NoContentReader - Returns EndOfMessage." {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var body_reader = BodyReader{ .NoContent = undefined };

    var buffer: [0]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);

    expect(event == .EndOfMessage);
}
