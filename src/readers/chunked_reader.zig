const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;
const std = @import("std");

pub const ChunkedReader = struct {
    const Self = @This();
    chunk_size: usize = 0,
    bytes_read: usize = 0,
    state: State = .ReadChunkSize,

    // An 8 bytes chunk size allows a chunk to be at most 16 777 215 bytes long.
    const MaxChunkSizeLength = 8;

    const State = enum {
        ReadChunkSize,
        ReadChunk,
        ReadChunkEnd,
        Done,
    };

    pub fn read(self: *Self, reader: anytype, buffer: []u8) !Event {
        while(true) {
            var event = try switch(self.state) {
                .ReadChunkSize => self.readChunkSize(reader, buffer),
                .ReadChunk => self.readChunk(reader, buffer),
                .ReadChunkEnd => self.readChunkEnd(reader),
                .Done => return .EndOfMessage,
            };
            if (event != null) {
                return event.?;
            }
        }
    }

    fn readChunkSize(self: *Self, reader: anytype, buffer: []u8) !?Event {
        var line: [MaxChunkSizeLength]u8 = undefined;
        _ = try reader.read(&line);
        const line_end = std.mem.indexOfPosLinear(u8, &line, 0, "\r\n") orelse return error.RemoteProtocolError;
        try reader.putBack(line[line_end + 2..]);
        self.chunk_size = try parseChunkSize(line[0.. line_end]);

        if (self.chunk_size > 0) {
            self.state = .ReadChunk;
            return null;
        }

        self.state = .Done;
        if (self.bytes_read == 0) {
            return null;
        }
        return Event{ .Data = Data{ .bytes = buffer[0 .. self.bytes_read] } };
    }

    fn readChunk(self: *Self, reader: anytype, buffer: []u8) !?Event {
        const remaining_space_left = buffer.len - self.bytes_read;
        const bytes_to_read = std.math.min(self.chunk_size, remaining_space_left);
        const count = try reader.read(buffer[self.bytes_read..self.bytes_read + bytes_to_read]);
        if (count == 0) {
            return error.EndOfStream;
        }

        self.chunk_size -= count;
        self.bytes_read += count;

        if (self.chunk_size == 0) {
            self.state = .ReadChunkEnd;
        }

        if (self.bytes_read < buffer.len) {
                return null;
        }

        self.bytes_read = 0;
        return Event{ .Data = Data{ .bytes = buffer } };
    }

    fn readChunkEnd(self: *Self, reader: anytype) !?Event {
        var chunk_end: [2]u8 = undefined;
        _ = try reader.read(&chunk_end);

        if (!std.mem.eql(u8, &chunk_end, "\r\n")) {
            return error.RemoteProtocolError;
        }

        self.state = .ReadChunkSize;
        return null;
    }

    fn parseChunkSize(hex_length: []const u8) !usize {
        var length: usize = 0;
        for (hex_length) |char| {
            const digit = std.fmt.charToDigit(char, 16) catch return error.RemoteProtocolError;
            length = (length << 4) | @as(usize, (digit & 0xF));
        }
        return length;
    }
};

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "ChunkedReader - Read a chunk" {
    const content = "E\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [32]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta go fast!");

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [14]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta go fast!");

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Ziguana");

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - Read a chunk with a smaller buffer" {
    const content = "E\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [7]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta g");

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "o fast!");

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks with a smaller buffer" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [7]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta g");

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "o fast!");

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Ziguana");

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks in the same user buffer" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n6\r\nStonks\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [32]u8 = undefined;

    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta go fast!ZiguanaStonks");

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - When the inner buffer is smaller than the user buffer" {
    const content = (
        "3E8\r\n"
        ++ "a" ** 200
        ++ "b" ** 200
        ++ "c" ** 200
        ++ "d" ** 200
        ++ "e" ** 200
        ++ "\r\n0\r\n\r\n"
    );
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [200]u8 = undefined;
    var event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "a" ** 200);

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "b" ** 200);

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "c" ** 200);

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "d" ** 200);

    event = try body_reader.read(&reader, &buffer);
    try expectEqualStrings(event.Data.bytes, "e" ** 200);

    event = try body_reader.read(&reader, &buffer);
    try expect(event == .EndOfMessage);
}

test "ChunkedReader - Fail to read a chunk size which is not hexadecimal" {
    const content = "XXX\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [32]u8 = undefined;

    var failure = body_reader.read(&reader, &buffer);
    try expectError(error.RemoteProtocolError, failure);
}

test "ChunkedReader - Fail to read too large chunk" {
    const content = "1000000\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [32]u8 = undefined;

    var failure = body_reader.read(&reader, &buffer);
    try expectError(error.RemoteProtocolError, failure);
}

test "ChunkedReader - Fail when not enough data can be read" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZi";
    var reader = std.io.peekStream(1024, std.io.fixedBufferStream(content).reader());

    var body_reader = ChunkedReader{};
    var buffer: [50]u8 = undefined;

    var failure = body_reader.read(&reader, &buffer);
    try expectError(error.EndOfStream, failure);
}
