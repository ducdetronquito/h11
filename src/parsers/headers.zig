const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const Buffer = @import("../buffer.zig").Buffer;
const ParserError = @import("errors.zig").ParserError;


pub const HeadersError = error {
    NotFoud,
};


pub const Headers = struct {
    pub fields: StringHashMap([]const u8),

    pub fn deinit(self: *Headers) void {
        self.fields.deinit();
    }

    // TODO: Implement header field name and value
    // https://tools.ietf.org/html/rfc7230#section-3.2.6
    pub fn parse(allocator: *Allocator, buffer: *Buffer) !Headers {
        var fields = StringHashMap([]const u8).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = buffer.readLine() catch return ParserError.NeedData;
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

        return Headers{ .fields = fields };
    }

    pub fn get(self: *Headers, key: []const u8) ![]const u8 {
        const kv = self.fields.get(key) orelse {
            return HeadersError.NotFoud;
        };
        return kv.value;
    }

    pub fn put(self: *Headers, key: []const u8, value: []const u8) !void {
        _ = try self.fields.put(key, value);
    }
};


const testing = std.testing;

test "Parse - When the headers does not end with an empty line - Returns error NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server: Apache\r\nContent-Length: 51\r\n");
    var headers = Headers.parse(allocator, &buffer);

    testing.expectError(ParserError.NeedData, headers);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server: Apache\r\nContent-Length: 51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = try headers.get("Server");
    var contentLength = try headers.get("Content-Length");

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}

test "Parse - When space between field name and value is omited - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("Server:Apache\r\nContent-Length:51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = try headers.get("Server");
    var contentLength = try headers.get("Content-Length");

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}
