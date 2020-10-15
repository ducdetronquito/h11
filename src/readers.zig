const Buffer = @import("buffer.zig").Buffer;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;


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
};


pub const BodyReader = union(BodyReaderType) {
    ContentLength: ContentLengthReader,

    pub fn expectedLength(self: BodyReader) usize {
        return switch(self) {
            .ContentLength => |reader| reader.expectedLength,
            else => unreachable,
        };
    }

    pub fn read(self: *BodyReader, buffer: *Buffer) Error!Event {
        return switch(self.*) {
            .ContentLength => |*reader| reader.read(buffer),
            else => unreachable,
        };
    }
};
