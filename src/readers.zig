const Buffer = @import("buffer.zig").Buffer;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const Method = @import("http").Method;
const Response = @import("events.zig").Response;
const fmt = @import("std").fmt;

pub const Error = error {
    NeedData,
    RemoteProtocolError,
};


pub const ContentLengthReader  = struct {
    expectedLength: usize,
    remaining_bytes: usize,

    pub fn init(expectedLength: usize) ContentLengthReader {
        return ContentLengthReader { .expectedLength = expectedLength, .remaining_bytes = expectedLength };
    }

    pub fn read(self: *ContentLengthReader, buffer: *Buffer) Error!Event {
        if (self.remaining_bytes == 0) {
            return .EndOfMessage;
        }

        if (buffer.len() > self.expectedLength) {
            return error.RemoteProtocolError;
        }

        if (self.expectedLength == 0) {
            return .EndOfMessage;
        }

        var content = buffer.read(self.expectedLength) catch return error.NeedData;
        self.remaining_bytes = 0;
        return Event { .Data = Data {.content = content } };
    }
};


pub const BodyReaderType = enum {
    ContentLength,
    NoContent,
};


pub const BodyReader = union(BodyReaderType) {
    ContentLength: ContentLengthReader,
    NoContent: void,

    pub fn expectedLength(self: BodyReader) usize {
        return switch(self) {
            .ContentLength => |reader| reader.expectedLength,
            else => unreachable,
        };
    }

    pub fn read(self: *BodyReader, buffer: *Buffer) Error!Event {
        return switch(self.*) {
            .ContentLength => |*reader| reader.read(buffer),
            .NoContent => .EndOfMessage,
            else => unreachable,
        };
    }

    // Determines the appropriate response body length.
    // Cf: RFC 7230 section 3.3.3, https://tools.ietf.org/html/rfc7230#section-3.3.3
    // TODO: Handle transfert encoding (chunked, compress, deflate, gzip)
    pub fn frame(requestMethod: Method, response: Response) !BodyReader {
        var statusCode = response.statusCode;
        var rawStatusCode = @enumToInt(statusCode);
        const hasNoContent = (
            requestMethod == .Head
            or rawStatusCode < 200
            or statusCode == .NoContent
            or statusCode == .NotModified
        );

        if (hasNoContent) {
            return .NoContent;
        }

        const isSuccessfulConnectRequest = (
            rawStatusCode < 300
            and rawStatusCode > 199
            and requestMethod == .Connect
        );
        if (isSuccessfulConnectRequest) {
            return .NoContent;
        }


        var contentLength: usize = 0;
        var contentLengthHeader = response.headers.get("Content-Length");

        if (contentLengthHeader != null) {
            contentLength = fmt.parseInt(usize, contentLengthHeader.?.value, 10) catch return Error.RemoteProtocolError;
        }

        return BodyReader { .ContentLength = ContentLengthReader.init(contentLength) };
    }
};


const expect = std.testing.expect;
const Headers = @import("http").Headers;
const std = @import("std");
const StatusCode = @import("http").StatusCode;


test "Frame Body - A HEAD request has no content" {
    var headers = Headers.init(std.testing.allocator);
    var response = Response.init(headers, .Ok, .Http11);

    var reader = try BodyReader.frame(.Head, response);

    expect(reader == .NoContent);
}

test "Frame Body - Informational responses (1XX status code) have no content" {
    var headers = Headers.init(std.testing.allocator);
    var response = Response.init(headers, .Continue, .Http11);

    var reader = try BodyReader.frame(.Get, response);

    expect(reader == .NoContent);
}

test "Frame Body - Response with a 204 No Content status code has no content" {
    var headers = Headers.init(std.testing.allocator);
    var response = Response.init(headers, .NoContent, .Http11);

    var reader = try BodyReader.frame(.Get, response);

    expect(reader == .NoContent);
}

test "Frame Body - Response with 304 Not Modified status code has no content" {
    var headers = Headers.init(std.testing.allocator);
    var response = Response.init(headers, .NotModified, .Http11);

    var reader = try BodyReader.frame(.Get, response);

    expect(reader == .NoContent);
}

test "Frame Body - A successful response (2XX) to a CONNECT request has no content" {
    var headers = Headers.init(std.testing.allocator);
    var response = Response.init(headers, .Ok, .Http11);

    var reader = try BodyReader.frame(.Connect, response);

    expect(reader == .NoContent);
}

