const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;
const std = @import("std");

fn FixedBuffer(comptime T: usize) type {
    return struct {
        const Self = @This();
        bytes: [T]u8 = undefined,
        length: usize = 0,
        pos: usize = 0,

        pub fn refill(self: *Self, reader: anytype) !void {
            if ((self.length - self.pos) > 0) {
                return;
            }

            self.length = try reader.read(&self.bytes);
            self.pos = 0;

            if (self.length == 0) {
                return error.EndOfStream; // If I already read data in the user buffer, I should give it back and their return an error.EndOfStream.
            }
        }

        pub fn readLine(self: *Self) ?[]u8 {
            const line_end = std.mem.indexOfPosLinear(u8, &self.bytes, self.pos, "\r\n") orelse return null;
            var line = self.bytes[self.pos .. line_end];
            self.pos = line_end + 2;
            return line;
        }

        pub fn readBytes(self: *Self, size: usize) []u8 {
            // Read up to `size` bytes
            const end = std.math.min(self.pos + size, self.length);
            var result = self.bytes[self.pos .. end];
            self.pos += result.len;
            return result;
        }
    };
}

pub fn ChunkedReader(comptime T: usize) type {
    return struct {
        const Self = @This();
        inner_buffer: FixedBuffer(T) = FixedBuffer(T){},
        chunk_size: usize = 0,
        bytes_read: usize = 0,
        state: State = .ReadChunkSize,

        const State = enum {
            ReadChunkSize,
            ReadChunk,
            ReadChunkEnd,
            Done,
        };

        pub fn read(self: *Self, reader: anytype, buffer: []u8) !Event {
            while(true) {

                try self.inner_buffer.refill(reader);
                var event = try switch(self.state) {
                    .ReadChunkSize => self.readChunkSize(reader, buffer),
                    .ReadChunk => self.readChunk(reader, buffer),
                    .ReadChunkEnd => self.readChunkEnd(reader, buffer),
                    .Done => return .EndOfMessage,
                };
                if (event != null) {
                    return event.?;
                }
            }
        }

        fn readChunkSize(self: *Self, reader: anytype, buffer: []u8) !?Event {
            const line = self.inner_buffer.readLine() orelse return error.RemoteProtocolError;
            self.chunk_size = try parseChunkSize(line);

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
            const chunk = self.inner_buffer.readBytes(bytes_to_read);
            std.mem.copy(u8, buffer[self.bytes_read..], chunk);
            self.chunk_size -= chunk.len;
            self.bytes_read += chunk.len;

            if (self.chunk_size == 0) {
                self.state = .ReadChunkEnd;
            }

            if (self.bytes_read < buffer.len) {
                 return null;
            }

            self.bytes_read = 0;
            return Event{ .Data = Data{ .bytes = buffer } };
        }

        fn readChunkEnd(self: *Self, reader: anytype, buffer: []u8) !?Event {
            const chunk_end = self.inner_buffer.readBytes(2);
            if (std.mem.eql(u8, chunk_end, "\r\n")) {
                self.state = .ReadChunkSize;
                return null;
            }

            if (std.mem.eql(u8, chunk_end, "\r")) {
                try self.inner_buffer.refill(reader);
                if (std.mem.eql(u8, self.inner_buffer.readBytes(1), "\n")) {
                    self.state = .ReadChunkSize;
                    return null;
                }
            }
            return error.RemoteProtocolError;
        }

        fn parseChunkSize(hex_length: []const u8) !usize {
            var length: usize = 0;
            for (hex_length) |char| {
                const digit = std.fmt.charToDigit(char, 16) catch return error.RemoteProtocolError;
                length = (length << 4) | @as(usize, (digit & 0xF));
            }

            if (length > 16_777_215) {
                return error.ChunkTooLarge;
            }

            return length;
        }
    };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "ChunkedReader - Read a chunk" {
    const content = "E\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [32]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [14]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Ziguana"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - Read a chunk with a smaller buffer" {
    const content = "E\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [7]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta g"));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "o fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks with a smaller buffer" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [7]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta g"));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "o fast!"));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Ziguana"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - Read multiple chunks in the same user buffer" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZiguana\r\n6\r\nStonks\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [32]u8 = undefined;

    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!ZiguanaStonks"));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
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
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [200]u8 = undefined;
    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "a" ** 200));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "b" ** 200));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "c" ** 200));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "d" ** 200));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "e" ** 200));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - When we can't read the end of a chunk within the inner buffer" {
    const first_part = "5F\r\n" ++ "a" ** 95 ++ "\r";
    const second_part = "\n0\r\n\r\n";
    const content = first_part ++ second_part;
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [50]u8 = undefined;

    var event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "a" ** 50));

    event = try body_reader.read(reader, &buffer);
    expect(std.mem.eql(u8, event.Data.bytes, "a" ** 45));

    event = try body_reader.read(reader, &buffer);
    expect(event == .EndOfMessage);
}

test "ChunkedReader - Fail to read not hexadecimal chunk size" {
    const content = "XXX\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [32]u8 = undefined;

    var failure = body_reader.read(reader, &buffer);
    expectError(error.RemoteProtocolError, failure);
}

test "ChunkedReader - Fail to read too large chunk" {
    const content = "1000000\r\nGotta go fast!\r\n0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(100){};
    var buffer: [32]u8 = undefined;

    var failure = body_reader.read(reader, &buffer);
    expectError(error.ChunkTooLarge, failure);
}

test "ChunkedReader - Fail when not enough data can be read" {
    const content = "E\r\nGotta go fast!\r\n7\r\nZi";
    var reader = std.io.fixedBufferStream(content).reader();

    var body_reader = ChunkedReader(24){};
    var buffer: [50]u8 = undefined;

    var failure = body_reader.read(reader, &buffer);
    expectError(error.EndOfStream, failure);
}
