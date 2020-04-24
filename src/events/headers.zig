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
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const EventError = @import("errors.zig").EventError;

pub const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

pub const Headers = struct {
    allocator: *Allocator,
    fields: []HeaderField,

    pub fn init(allocator: *Allocator) Headers {
        return Headers{ .allocator = allocator, .fields = &[_]HeaderField{} };
    }

    /// Headers takes ownership of the passed in slice. The slice must have been
    /// allocated with `allocator`.
    pub fn fromOwnedSlice(allocator: *Allocator, fields: []HeaderField) Headers {
        return Headers{ .allocator = allocator, .fields = fields };
    }

    pub fn deinit(self: *Headers) void {
        self.allocator.free(self.fields);
    }

    /// The caller owns the returned memory. Headers becomes empty.
    pub fn toOwnedSlice(self: *Headers) []HeaderField {
        const result = self.allocator.shrink(self.fields, self.fields.len);
        self.* = init(self.allocator);
        return result;
    }

    pub fn parse(allocator: *Allocator, buffer: *Buffer) !Headers{
        var fields = ArrayList(HeaderField).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = buffer.readLine() catch return EventError.NeedData;

            if (line.len == 0) {
                break;
            }

            const field = try Headers.parseHeaderField(allocator, line);
            try fields.append(field);
        }

        return Headers.fromOwnedSlice(allocator, fields.toOwnedSlice());
    }

    pub fn parseHeaderField(allocator: *Allocator, data: []u8) !HeaderField {
        var cursor: usize = 0;
        while (cursor < data.len) {
            if (data[cursor] == ':') {
                const name = try Headers.parseFieldName(allocator, data[0..cursor]);
                const value = Headers.parseFieldValue(allocator, data[cursor + 1 ..]);
                return HeaderField{ .name = name, .value = value };
            }
            cursor += 1;
        }
        return EventError.RemoteProtocolError;
    }

    pub fn parseFieldName(allocator: *Allocator, data: []u8) ![]u8 {
        // No whitespace is allowed between the header field-name and colon.
        // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.4
        if (data[data.len - 1] == ' ') {
            return EventError.RemoteProtocolError;
        }

        for (data) |item, i| {
            data[i] = std.ascii.toLower(item);
        }
        return data;
    }

    pub fn parseFieldValue(allocator: *Allocator, data: []const u8) []const u8 {
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
        return data[start .. cursor + 1];
    }

    // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.3
    fn isLinearWhitespace(char: u8) bool {
        return char == ' ' or char == '\t';
    }

    pub fn serialize(allocator: *Allocator, headers: []HeaderField) ![]const u8 {
        var buffer = ArrayList(u8).init(allocator);

        for (headers) |header| {
            try buffer.appendSlice(header.name);
            try buffer.appendSlice(": ");
            try buffer.appendSlice(header.value);
            try buffer.appendSlice("\r\n");
        }
        try buffer.appendSlice("\r\n");

        return buffer.toOwnedSlice();
    }
};

const testing = std.testing;

fn allocate(allocator: *Allocator, content: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, content.len);
    std.mem.copy(u8, result, content);
    return result;
}

test "Parse field name - When ends with a whitespace - Returns RemoteProtocolError" {
    var name = try allocate(testing.allocator, "Server ");
    defer testing.allocator.free(name);

    var headers = Headers.parseFieldName(testing.allocator, name);
    testing.expectError(EventError.RemoteProtocolError, headers);
}

test "Parse field name - Name is lowercased" {
    var name = try allocate(testing.allocator, "SeRvEr");
    defer testing.allocator.free(name);

    var value = try Headers.parseFieldName(testing.allocator, name);

    testing.expect(std.mem.eql(u8, value, "server"));
}

test "Parse field value" {
    var value = Headers.parseFieldValue(testing.allocator, "Apache");

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading and trailing whitespace" {
    var value = Headers.parseFieldValue(testing.allocator, " \t  Apache   \t ");

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading htab character" {
    var value = Headers.parseFieldValue(testing.allocator, "\tApache");

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse header field - When colon is missing - Returns RemoteProtocolError" {
    var field = try allocate(testing.allocator, "ServerApache");
    defer testing.allocator.free(field);

    var headerField = Headers.parseHeaderField(testing.allocator, field);

    testing.expectError(EventError.RemoteProtocolError, headerField);
}

test "Parse - When the headers does not end with an empty line - Returns NeedData" {
    var bytes = try allocate(testing.allocator, "ServerApache");
    defer testing.allocator.free(bytes);

    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append(bytes);

    var headers = Headers.parse(testing.allocator, &buffer);

    testing.expectError(EventError.NeedData, headers);
}

test "Parse" {
    var bytes = try allocate(testing.allocator, "server: Apache\r\ncontent-length: 51\r\n\r\n");
    defer testing.allocator.free(bytes);

    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append(bytes);

    var headers = try Headers.parse(testing.allocator, &buffer);
    defer headers.deinit();

    testing.expect(std.mem.eql(u8, headers.fields[0].name, "server"));
    testing.expect(std.mem.eql(u8, headers.fields[0].value, "Apache"));
    testing.expect(std.mem.eql(u8, headers.fields[1].name, "content-length"));
    testing.expect(std.mem.eql(u8, headers.fields[1].value, "51"));
}

test "Serialize" {
    var headers = [_]HeaderField{
        HeaderField{ .name = "Host", .value = "httpbin.org" },
        HeaderField{ .name = "Server", .value = "Apache" },
    };

    var result = try Headers.serialize(testing.allocator, headers[0..]);
    defer testing.allocator.free(result);

    testing.expect(std.mem.eql(u8, result, "Host: httpbin.org\r\nServer: Apache\r\n\r\n"));
}
