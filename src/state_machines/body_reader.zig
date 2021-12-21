const ChunkedReader = @import("chunked_reader.zig").ChunkedReader;
const ContentLengthReader = @import("content_length_reader.zig").ContentLengthReader;
const Event = @import("events/main.zig").Event;
const Header = @import("http").Header;
const Method = @import("http").Method;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
pub const TransferEncoding = @import("encoding.zig").TransferEncoding;

pub const FramingContext = struct {
    method: Method = .Get,
    status_code: StatusCode = .Ok,
    transfert_encoding: TransferEncoding = .Unknown,
    content_length: usize = 0,

    pub const Error = error{ InvalidContentLength, UnknownTranfertEncoding };

    pub inline fn analyze(self: *FramingContext, header: Header) Error!void {
        if (header.name.type == .ContentLength) {
            self.content_length = std.fmt.parseInt(usize, header.value, 10) catch return error.InvalidContentLength;
            self.transfert_encoding = .ContentLength;
        } else if (header.name.type == .TransferEncoding) {
            if (std.mem.endsWith(u8, header.value, "chunked")) {
                self.transfert_encoding = .Chunked;
            } else {
                return error.UnknownTranfertEncoding;
            }
        }
    }
};

pub const BodyReaderType = enum {
    Chunked,
    ContentLength,
    NoContent,
};

pub const BodyReader = union(BodyReaderType) {
    Chunked: ChunkedReader,
    ContentLength: ContentLengthReader,
    NoContent: void,

    pub inline fn read(self: *BodyReader, reader: anytype, buffer: []u8) !Event {
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
    pub fn frame(context: FramingContext) !BodyReader {
        var status_code = @enumToInt(context.status_code);
        const has_no_content = (context.method == .Head or status_code < 200 or context.status_code == .NoContent or context.status_code == .NotModified);

        if (has_no_content) {
            return .NoContent;
        }

        const successful_connect = (status_code > 199 and status_code < 300 and context.method == .Connect);
        if (successful_connect) {
            return .NoContent;
        }

        if (context.transfert_encoding == .Chunked) {
            return BodyReader{ .Chunked = ChunkedReader{} };
        }

        return BodyReader{ .ContentLength = ContentLengthReader{ .expected_length = context.content_length } };
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Frame Body - A HEAD request has no content" {
    const context = FramingContext{ .method = .Head, .status_code = .Ok, .transfert_encoding = .Unknown, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .NoContent);
}

test "Frame Body - Informational responses (1XX status code) have no content" {
    const context = FramingContext{ .method = .Get, .status_code = .Continue, .transfert_encoding = .Unknown, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .NoContent);
}

test "Frame Body - Response with a 204 No Content status code has no content" {
    const context = FramingContext{ .method = .Get, .status_code = .NoContent, .transfert_encoding = .Unknown, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .NoContent);
}

test "Frame Body - Response with 304 Not Modified status code has no content" {
    const context = FramingContext{ .method = .Get, .status_code = .NotModified, .transfert_encoding = .Unknown, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .NoContent);
}

test "Frame Body - A successful response (2XX) to a CONNECT request has no content" {
    const context = FramingContext{ .method = .Connect, .status_code = .Ok, .transfert_encoding = .Unknown, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .NoContent);
}

test "Frame Body - Use a ChunkReader when chunked is the final encoding" {
    const context = FramingContext{ .method = .Get, .status_code = .Ok, .transfert_encoding = .Chunked, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .Chunked);
}

test "Frame Body - By default use a ContentLengthReader with a length of 0" {
    const context = FramingContext{ .method = .Get, .status_code = .Ok, .transfert_encoding = .ContentLength, .content_length = 0 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .ContentLength);
    try expect(body_reader.ContentLength.expected_length == 0);
}

test "Frame Body - Use a ContentLengthReader with the provided length" {
    const context = FramingContext{ .method = .Get, .status_code = .Ok, .transfert_encoding = .ContentLength, .content_length = 15 };
    const body_reader = try BodyReader.frame(context);

    try expect(body_reader == .ContentLength);
    try expect(body_reader.ContentLength.expected_length == 15);
}

test "NoContentReader - Returns EndOfMessage." {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var body_reader = BodyReader{ .NoContent = undefined };

    var buffer: [0]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);

    try expect(event == .EndOfMessage);
}
