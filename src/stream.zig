const std = @import("std");


pub const StreamError = error {
    EndOfStream,
};

pub const Stream = struct {
    cursor: usize,
    data: []u8,

    pub fn init(data: []u8) Stream {
        return Stream{ .cursor = 0, .data = data };
    }

    pub fn fromSliceConst(data: []const u8) Stream {
        return Stream.init(data);
    }

    pub fn readLine(self: *Stream) StreamError![]u8 {
        const data = self.data;
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
            return error.EndOfStream;
        }
    }

    pub fn read(self: *Stream, size: usize) []u8 {
        const end = std.math.min(size, self.len());
        const result = self.data[self.cursor..self.cursor + end];
        self.cursor += size;
        return result;
    }

    pub fn len(self: *Stream) usize {
        return self.data.len - self.cursor;
    }

    pub fn isEmpty(self: *Stream) bool {
        return self.len() == 0;
    }
};

const testing = std.testing;

test "ReadLine - No CRLF - Returns EndOfStream" {
    var content = "HTTP/1.1 200 OK".*;
    var stream = Stream.init(&content);

    var line = stream.readLine();

    testing.expectError(error.EndOfStream, line);
}

test "ReadLine - Read line returns the entire stream" {
    var content = "HTTP/1.1 200 OK\r\n".*;
    var stream = Stream.init(&content);

    var line = try stream.readLine();

    testing.expect(std.mem.eql(u8, line, "HTTP/1.1 200 OK"));
}

test "ReadLine - Read line returns the remaining stream" {
    var content = "HTTP/1.1 200 OK\r\n".*;
    var stream = Stream.init(&content);
    _ = stream.read(9);

    var line = try stream.readLine();

    testing.expect(std.mem.eql(u8, line, "200 OK"));
}

test "ReadLine - Read lines one by one " {
    var content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 51\r\n".*;
    var stream = Stream.init(&content);

    var firstLine = try stream.readLine();
    var secondLine = try stream.readLine();
    var thirdLine = try stream.readLine();

    testing.expect(std.mem.eql(u8, firstLine, "HTTP/1.1 200 OK"));
    testing.expect(std.mem.eql(u8, secondLine, "Server: Apache"));
    testing.expect(std.mem.eql(u8, thirdLine, "Content-Length: 51"));
}

test "Read - Success " {
    var content = "HTTP/1.1 200 OK".*;
    var stream = Stream.init(&content);

    var httpVersion = stream.read(8);

    testing.expect(std.mem.eql(u8, httpVersion, "HTTP/1.1"));
}
