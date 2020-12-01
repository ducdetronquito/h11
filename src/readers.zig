const Buffer = std.ArrayList(u8);
const Data = @import("events/events.zig").Data;
const Event = @import("events/events.zig").Event;
const std = @import("std");
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const Response = @import("events/events.zig").Response;
const StatusCode = @import("http").StatusCode;

pub const Error = error{
    NeedData,
    RemoteProtocolError,
};

pub const ContentLengthReader = struct {
    expectedLength: usize,
    remaining_bytes: usize,

    pub fn init(expectedLength: usize) BodyReader {
        return BodyReader{
            .ContentLength = ContentLengthReader{ .expectedLength = expectedLength, .remaining_bytes = expectedLength },
        };
    }

    pub fn read(self: *ContentLengthReader, buffer: *Buffer) Error!Event {
        if (self.remaining_bytes == 0) {
            return .EndOfMessage;
        }

        if (buffer.items.len > self.remaining_bytes) {
            return error.RemoteProtocolError;
        }

        var data = buffer.toOwnedSlice();
        self.remaining_bytes -= data.len;
        return Data.to_event(buffer.allocator, data);
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

    pub fn expectedLength(self: BodyReader) usize {
        return switch (self) {
            .ContentLength => |reader| reader.expectedLength,
            else => unreachable,
        };
    }

    pub fn read(self: *BodyReader, buffer: *Buffer) Error!Event {
        return switch (self.*) {
            .ContentLength => |*reader| reader.read(buffer),
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
            contentLength = std.fmt.parseInt(usize, contentLengthHeader.?.value, 10) catch return Error.RemoteProtocolError;
        }

        return ContentLengthReader.init(contentLength);
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Frame Body - A HEAD request has no content" {
    var headers = Headers.init(std.testing.allocator);

    var reader = try BodyReader.frame(.Head, .Ok, headers);

    expect(reader == .NoContent);
}

test "Frame Body - Informational responses (1XX status code) have no content" {
    var headers = Headers.init(std.testing.allocator);

    var reader = try BodyReader.frame(.Get, .Continue, headers);

    expect(reader == .NoContent);
}

test "Frame Body - Response with a 204 No Content status code has no content" {
    var headers = Headers.init(std.testing.allocator);

    var reader = try BodyReader.frame(.Get, .NoContent, headers);

    expect(reader == .NoContent);
}

test "Frame Body - Response with 304 Not Modified status code has no content" {
    var headers = Headers.init(std.testing.allocator);

    var reader = try BodyReader.frame(.Get, .NotModified, headers);

    expect(reader == .NoContent);
}

test "Frame Body - A successful response (2XX) to a CONNECT request has no content" {
    var headers = Headers.init(std.testing.allocator);

    var reader = try BodyReader.frame(.Connect, .Ok, headers);

    expect(reader == .NoContent);
}

test "ContentLengthReader - Read" {
    var buffer = Buffer.init(std.testing.allocator);
    try buffer.appendSlice("Gotta go fast!");

    var reader = ContentLengthReader.init(14);
    var event = try reader.read(&buffer);

    switch(event) {
        .Data => |data| {
            expect(std.mem.eql(u8, data.content, "Gotta go fast!"));
            event.deinit();
        },
        else => unreachable,
    }

    event = try reader.read(&buffer);
    expect(event == .EndOfMessage);
}

test "ContentLengthReader - Read multiple chunk" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("Gotta go");

    var reader = ContentLengthReader.init(14);
    var event = try reader.read(&buffer);
    switch(event) {
        .Data => |data| {
            expect(std.mem.eql(u8, data.content, "Gotta go"));
            event.deinit();
        },
        else => unreachable,
    }

    try buffer.appendSlice(" fast!");

    event = try reader.read(&buffer);
    switch(event) {
        .Data => |data| {
            expect(std.mem.eql(u8, data.content, " fast!"));
            event.deinit();
        },
        else => unreachable,
    }

    event = try reader.read(&buffer);
    expect(event == .EndOfMessage);
}
