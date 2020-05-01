const std = @import("std");
const EventError = @import("errors.zig").EventError;
const Stream = @import("../stream.zig").Stream;

pub const Data = struct {
    body: []const u8,

    pub fn parse(stream: *Stream, contentLength: usize) EventError!Data {
        var streamSize = stream.len();
        if (streamSize < contentLength) {
            return error.NeedData;
        }
        if (streamSize > contentLength) {
            return error.RemoteProtocolError;
        }

        return Data{ .body = stream.read(contentLength) };
    }
};

const testing = std.testing;

test "Parse - When the payload is not completely received - Returns NeedData" {
    var content = "Hello World!".*;
    var stream = Stream.init(&content);

    var data = Data.parse(&stream, 666);

    testing.expectError(EventError.NeedData, data);
}

test "Parse - Larger payload than expected - Returns RemoteProtocolError" {
    var content = "Hello World!".*;
    var stream = Stream.init(&content);

    var data = Data.parse(&stream, 10);

    testing.expectError(error.RemoteProtocolError, data);
}

test "Parse - Success" {
    var content = "Hello World!".*;
    var stream = Stream.init(&content);

    var data = try Data.parse(&stream, 12);

    testing.expect(std.mem.eql(u8, data.body, "Hello World!"));
}
