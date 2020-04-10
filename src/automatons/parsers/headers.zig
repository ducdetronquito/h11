// Header fields parsing
//
// Each header field consists of a case-insensitive field name followed
// by a colon (":"), optional leading whitespace, the field value, and
// optional trailing whitespace.
// Cf: https://tools.ietf.org/html/rfc7230#section-3.2
//
// NB: As of yet, no character validation is made on the field's value.
// https://tools.ietf.org/html/rfc7230#section-3.2.6

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const Buffer = @import("../../buffer.zig").Buffer;
const EventError = @import("../errors.zig").EventError;

const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

pub const Headers = struct {
    pub fn parse(allocator: *Allocator, buffer: *Buffer) !StringHashMap([]const u8) {
        var fields = StringHashMap([]const u8).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = buffer.readLine() catch return EventError.NeedData;
            if (line.len == 0) {
                break;
            }

            const field = try Headers.parseHeaderField(allocator, line);
            _ = try fields.put(field.name, field.value);
        }

        return fields;
    }

    pub fn parseHeaderField(allocator: *Allocator, data: []const u8) !HeaderField {
        var cursor: usize = 0;
        while (cursor < data.len) {
            if (data[cursor] == ':') {
                const name = try Headers.parseFieldName(allocator, data[0..cursor]);
                const value = Headers.parseFieldValue(data[cursor + 1 ..]);
                return HeaderField{ .name = name, .value = value };
            }
            cursor += 1;
        }
        return EventError.RemoteProtocolError;
    }

    pub fn parseFieldName(allocator: *Allocator, data: []const u8) ![]const u8 {
        // No whitespace is allowed between the header field-name and colon.
        // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.4
        if (data[data.len - 1] == ' ') {
            return EventError.RemoteProtocolError;
        }
        return try Headers.toLower(allocator, data);
    }

    fn toLower(allocator: *Allocator, content: []const u8) ![]const u8 {
        var result = try allocator.alloc(u8, content.len);
        for (content) |item, i| {
            result[i] = std.ascii.toLower(item);
        }
        return result;
    }

    pub fn parseFieldValue(data: []const u8) []const u8 {
        // Leading and trailing whitespace are removed.
        // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.4
        var cursor: usize = 0;
        while (cursor < data.len) {
            if (!Headers.isLinearWhitespace(data[cursor])) {
                break;
            }
            cursor += 1;
        }

        var start = cursor;

        cursor = data.len - 1;
        while (cursor > start) {
            if (!Headers.isLinearWhitespace(data[cursor])) {
                break;
            }
            cursor -= 1;
        }

        return data[start..cursor + 1];
    }

    // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.3
    fn isLinearWhitespace(char: u8) bool {
        return char == ' ' or char == '\t';
    }

    pub fn getContentLength(headers: StringHashMap([]const u8)) !usize {
        const rawContentLength = headers.get("content-length") orelse {
            return 0;
        };

        const contentLength = std.fmt.parseInt(usize, rawContentLength.value, 10) catch {
            return EventError.RemoteProtocolError;
        };

        return contentLength;
    }
};

const testing = std.testing;

test "Parse field name - When ends with a whitespace - Returns error RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headers = Headers.parseFieldName(allocator, "Server ");
    testing.expectError(EventError.RemoteProtocolError, headers);
}

test "Parse field name - Name is lowercased" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var value = try Headers.parseFieldName(allocator, "SeRvEr");
    testing.expect(std.mem.eql(u8, value, "server"));
}

test "Parse field value" {
    var value = Headers.parseFieldValue("Apache");
    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading and trailing whitespace" {
    var value = Headers.parseFieldValue(" \t  Apache   \t ");
    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading htab character" {
    var value = Headers.parseFieldValue("\tApache");
    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse header field - When colon is missing - Returns error RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headerField = Headers.parseHeaderField(allocator, "ServerApache");
    testing.expectError(EventError.RemoteProtocolError, headerField);
}

test "Parse - When the headers does not end with an empty line - Returns error NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("server: Apache\r\ncontent-length: 51\r\n");
    var headers = Headers.parse(allocator, &buffer);

    testing.expectError(EventError.NeedData, headers);
}

test "Parse" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("server: Apache\r\ncontent-length: 51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = headers.get("server").?.value;
    var contentLength = headers.get("content-length").?.value;

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}

test "Parse" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = Buffer.init(allocator);
    try buffer.append("server: Apache\r\ncontent-length: 51\r\n\r\n");
    var headers = try Headers.parse(allocator, &buffer);

    var server = headers.get("server").?.value;
    var contentLength = headers.get("content-length").?.value;

    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLength, "51"));
}
