const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const EventError = @import("errors.zig").EventError;

pub const Data = struct {
    body: []const u8,

    pub fn deinit(self: *Data) void {
        // TODO: Data needs to own its payload
    }

    pub fn parse(buffer: *Buffer, contentLength: usize) !Data {
        var bufferSize = buffer.len();
        if (bufferSize < contentLength) {
            return EventError.NeedData;
        }
        if (bufferSize > contentLength) {
            return EventError.RemoteProtocolError;
        }

        return Data{ .body = buffer.read(contentLength) };
    }
};

const testing = std.testing;

test "Parse - When the payload is not completely received - Returns NeedData" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append("Hello World!");

    var data = Data.parse(&buffer, 666);

    testing.expectError(EventError.NeedData, data);
}

test "Parse - Larger payload than expected - Returns RemoteProtocolError" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append("Hello World!");
    var data = Data.parse(&buffer, 10);

    testing.expectError(EventError.RemoteProtocolError, data);
}

test "Parse - Success" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append("Hello World!");
    var data = try Data.parse(&buffer, 12);

    testing.expect(std.mem.eql(u8, data.body, "Hello World!"));
}
