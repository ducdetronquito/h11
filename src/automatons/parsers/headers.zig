const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const Buffer = @import("../../buffer.zig").Buffer;
const EventError = @import("../errors.zig").EventError;


pub const HeadersError = error {
    NotFoud,
};


pub const Headers = struct {
    // TODO: Implement header field name and value
    // https://tools.ietf.org/html/rfc7230#section-3.2.6
    pub fn parse(allocator: *Allocator, buffer: *Buffer) !StringHashMap([]const u8) {
        var fields = StringHashMap([]const u8).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = buffer.readLine() catch return EventError.NeedData;
            if (line.len == 0) {
                break;
            }

            var cursor: usize = 0;
            while (cursor < line.len) {
                if (line[cursor] == ':') {
                    const name = line[0..cursor];
                    var value: []const u8 = undefined;
                    if (line[cursor + 1] == ' ') {
                        value = line[cursor + 2..];
                    } else {
                        value = line[cursor + 1..];
                    }
                    _ = try fields.put(name, value);
                    break;
                }
                cursor += 1;
            }
        }

        return fields;
    }

    pub fn getContentLength(headers: StringHashMap([]const u8)) !usize {
        const rawContentLength = headers.get("Content-Length") orelse {
            return 0;
        };

        const contentLength = std.fmt.parseInt(usize, rawContentLength.value, 10) catch {
            return EventError.RemoteProtocolError;
        };

        return contentLength;
    }
};


const testing = std.testing;

test "Parse - When the headers does not end with an empty line - Returns error NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server: Apache\r\nContent-Length: 51\r\n");
    var headers = Headers.parse(allocator, &buffer);

    testing.expectError(EventError.NeedData, headers);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server: Apache\r\nContent-Length: 51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = headers.get("Server").?.value;
    var contentLength = headers.get("Content-Length").?.value;

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}

test "Parse - When space between field name and value is omited - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server:Apache\r\nContent-Length:51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = headers.get("Server").?.value;
    var contentLength = headers.get("Content-Length").?.value;

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}
