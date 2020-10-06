const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const std = @import("std");


pub const Buffer = struct {
    cursor: usize,
    data: Bytes,

    pub fn init(allocator: *Allocator) Buffer {
        return Buffer {
            .cursor = 0,
            .data = Bytes.init(allocator),
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit();
    }

    pub const Error = error {
        EndOfStream,
    };

    pub inline fn appendSlice(self: *Buffer, data: []const u8) !void {
        try self.data.appendSlice(data);
    }

    pub inline fn toSlice(self: *Buffer) []const u8 {
        return self.data.items[self.cursor..];
    }

    pub fn read(self: *Buffer, bytes_count: usize) Error![]const u8 {
        if (bytes_count > self.len()) {
            return error.EndOfStream;
        }

        var slice = self.data.items[self.cursor..self.cursor + bytes_count];
        self.cursor += bytes_count;
        return slice;
    }

    pub fn findBlankLine(self: *Buffer) ?usize {
        var data = self.toSlice();
        var i = self.cursor;

        while(i < data.len) {
            if (data[i] != '\r') {
                i += 1;
                continue;
            }

            if (data.len - i < 4) {
                return null;
            }

            if (data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') {
                return i - self.cursor;
            }
            i += 1;
        }

        return null;
    }

    pub inline fn len(self: *Buffer) usize {
        return self.data.items.len - self.cursor;
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "FindBlankLine - Success" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendSlice("HTTP/1.1 200 OK\r\n\r\n");
    expect(buffer.findBlankLine().? == 15);
}

test "FindBlankLine - Not Found" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendSlice("HTTP/1.1 200 OK\r\n\r");
    expect(buffer.findBlankLine() == null);
}

test "Read - Asks for too much bytes" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendSlice("HTTP/1.1 200 OK\r\n\r\n");
    var slice = buffer.read(20);
    expectError(Buffer.Error.EndOfStream, slice);
}

test "Read - Success" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendSlice("HTTP/1.1 200 OK\r\n\r\n");
    var slice = try buffer.read(15);
    expect(std.mem.eql(u8, slice, "HTTP/1.1 200 OK"));
}
