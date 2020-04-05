const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;


pub const BufferError = error {
    EndOfStream,
};


pub const Buffer = struct {
    allocator: *Allocator,
    data: ArrayList(u8),
    cursor: usize,

    pub fn init(allocator: *Allocator) Buffer {
        var data = ArrayList(u8).init(allocator);
        return Buffer{ .allocator = allocator, .data = data, .cursor = 0 };
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit();
    }

    /// Read one line from the stream.
    /// Returns an empty line if CRLF is not found.
    pub fn readLine(self: *Buffer) ![]const u8 {
        const data = self.data.toSliceConst();
        var start = self.cursor;
        var cursor = self.cursor;

        var lineFound = false;
        while (cursor < data.len) {
            if ((data[cursor] == '\n') and (data[cursor - 1] == '\r')) {
                cursor += 1;
                lineFound = true;
                break;
            }
            cursor += 1;
        }

        if (lineFound) {
            self.cursor = cursor;
            return data[start..cursor - 2];
        } else {
            return BufferError.EndOfStream;
        }
    }

    pub fn read(self: *Buffer, size: usize) []const u8 {
        const end = std.math.min(size, self.len());
        const result = self.data.toSliceConst()[self.cursor..self.cursor + end];
        self.cursor += size;
        return result;
    }

    pub fn len(self: *Buffer) usize {
        return self.data.len - self.cursor;
    }

    pub fn isEmpty(self: *Buffer) bool {
        return self.len() == 0;
    }

    pub fn append(self: *Buffer, slice: []const u8) !void {
        const old_len = self.data.len;
        try self.data.resize(old_len + slice.len);
        std.mem.copy(u8, self.data.toSlice()[old_len..], slice);
    }
};


const testing = std.testing;

test "Init and deinit" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
}


test "ReadLine - No CRLF - Returns EndOfStream" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("HTTP/1.1 200 OK");

    var line = buffer.readLine();
    testing.expectError(BufferError.EndOfStream, line);
}

test "ReadLine - Read line returns the entire buffer" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("HTTP/1.1 200 OK\r\n");

    var line = try buffer.readLine();
    testing.expect(std.mem.eql(u8, line, "HTTP/1.1 200 OK"));
}

test "ReadLine - Read line returns the remaining buffer" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("HTTP/1.1 200 OK\r\n");
    _ = buffer.read(9);

    var line = try buffer.readLine();
    testing.expect(std.mem.eql(u8, line, "200 OK"));
}

test "ReadLine - Read lines one by one " {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 51\r\n");

    var firstLine = try buffer.readLine();
    var secondLine = try buffer.readLine();
    var thirdLine = try buffer.readLine();

    testing.expect(std.mem.eql(u8, firstLine, "HTTP/1.1 200 OK"));
    testing.expect(std.mem.eql(u8, secondLine, "Server: Apache"));
    testing.expect(std.mem.eql(u8, thirdLine, "Content-Length: 51"));
}

test "Read - Success " {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("HTTP/1.1 200 OK");

    var httpVersion = buffer.read(8);
    testing.expect(std.mem.eql(u8, httpVersion, "HTTP/1.1"));
}
