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
    ownsFields: bool,

    pub fn init(allocator: *Allocator, fields: []HeaderField, ownsFields: bool) Headers {
        return Headers{ .allocator = allocator, .fields = fields, .ownsFields = ownsFields };
    }

    pub fn fromOwnedFields(allocator: *Allocator, fields: []HeaderField) Headers {
        return Headers.init(allocator, fields, false);
    }

    pub fn parse(allocator: *Allocator, buffer: *Buffer) !Headers{
        var fields = ArrayList(HeaderField).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = buffer.readLine() catch {
                Headers.deinitFields(allocator, fields.items);
                return EventError.NeedData;
            };

            if (line.len == 0) {
                break;
            }

            const field = try Headers.parseHeaderField(allocator, line);
            try fields.append(field);
        }

        return Headers.init(allocator, fields.toOwnedSlice(), true);
    }

    pub fn deinit(self: *Headers) void {
        if (!self.ownsFields) {
            return;
        }

        Headers.deinitFields(self.allocator, self.fields);
        self.allocator.free(self.fields);
    }

    fn deinitFields(allocator: *Allocator, fields: []HeaderField) void {
        for (fields) |*field| {
            allocator.free(field.name);
            allocator.free(field.value);
        }
    }

    pub fn parseHeaderField(allocator: *Allocator, data: []const u8) !HeaderField {
        var cursor: usize = 0;
        while (cursor < data.len) {
            if (data[cursor] == ':') {
                const name = try Headers.parseFieldName(allocator, data[0..cursor]);
                const value = try Headers.parseFieldValue(allocator, data[cursor + 1 ..]);
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

    pub fn parseFieldValue(allocator: *Allocator, data: []const u8) ![]const u8 {
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
        var result = try allocator.alloc(u8, cursor - start + 1);
        std.mem.copy(u8, result, data[start .. cursor + 1]);
        return result;
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

test "Parse field name - When ends with a whitespace - Returns RemoteProtocolError" {
    var headers = Headers.parseFieldName(testing.allocator, "Server ");
    testing.expectError(EventError.RemoteProtocolError, headers);
}

test "Parse field name - Name is lowercased" {
    var value = try Headers.parseFieldName(testing.allocator, "SeRvEr");
    defer testing.allocator.free(value);
    testing.expect(std.mem.eql(u8, value, "server"));
}

test "Parse field value" {
    var value = try Headers.parseFieldValue(testing.allocator, "Apache");
    defer testing.allocator.free(value);

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading and trailing whitespace" {
    var value = try Headers.parseFieldValue(testing.allocator, " \t  Apache   \t ");
    defer testing.allocator.free(value);

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse field value - Ignore leading htab character" {
    var value = try Headers.parseFieldValue(testing.allocator, "\tApache");
    defer testing.allocator.free(value);

    testing.expect(std.mem.eql(u8, value, "Apache"));
}

test "Parse header field - When colon is missing - Returns RemoteProtocolError" {
    var headerField = Headers.parseHeaderField(testing.allocator, "ServerApache");
    testing.expectError(EventError.RemoteProtocolError, headerField);
}

test "Parse - When the headers does not end with an empty line - Returns NeedData" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append("server: Apache\r\ncontent-length: 51\r\n");
    var headers = Headers.parse(testing.allocator, &buffer);

    testing.expectError(EventError.NeedData, headers);
}

test "Parse" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();
    try buffer.append("server: Apache\r\ncontent-length: 51\r\n\r\n");
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
