const std = @import("std");
const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;

pub const Error = error{
    BodyTooshort,
    BodyTooLarge,
};

pub const ContentLengthReader = struct {
    expected_length: usize,
    read_bytes: usize = 0,

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

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "ContentLengthReader - Fail when the body is shorter than expected." {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader{.expected_length = 14 };
    var buffer: [32]u8 = undefined;
    const failure = body_reader.read(reader, &buffer);

    expectError(error.BodyTooshort, failure);
}

test "ContentLengthReader - Read" {
    const content = "Gotta go fast!";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader{.expected_length = 14 };
    var buffer: [32]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);

    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ContentLengthReader - Read in several call" {
    const content = "a" ** 32 ++ "b" ** 32 ++ "c" ** 32;
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ContentLengthReader{.expected_length = 96 };

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
