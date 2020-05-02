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
const AllocationError = @import("errors.zig").AllocationError;
const ArrayList = std.ArrayList;
const EventError = @import("errors.zig").EventError;
const Stream = @import("../stream.zig").Stream;

pub const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

pub const Headers = struct {

    pub fn parse(allocator: *Allocator, stream: *Stream) EventError![]HeaderField{
        var fields = ArrayList(HeaderField).init(allocator);
        errdefer fields.deinit();

        while (true) {
            const line = stream.readLine() catch return error.NeedData;

            if (line.len == 0) {
                break;
            }

            const field = try Headers.parseHeaderField(line);
            try fields.append(field);
        }

        return fields.toOwnedSlice();
    }

    fn parseHeaderField(data: []u8) EventError!HeaderField {
        var cursor: usize = 0;
        while (cursor < data.len) {
            if (data[cursor] == ':') {
                const name = try Headers.parseFieldName(data[0..cursor]);
                const value = Headers.parseFieldValue(data[cursor + 1 ..]);
                return HeaderField{ .name = name, .value = value };
            }
            cursor += 1;
        }
        return error.RemoteProtocolError;
    }

    fn parseFieldName(data: []u8) EventError![]u8 {
        // No whitespace is allowed between the header field-name and colon.
        // Cf: https://tools.ietf.org/html/rfc7230#section-3.2.4
        if (data[data.len - 1] == ' ') {
            return error.RemoteProtocolError;
        }

        for (data) |item, i| {
            data[i] = std.ascii.toLower(item);
        }
        return data;
    }

    fn parseFieldValue(data: []const u8) []const u8 {
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

    pub fn serialize(allocator: *Allocator, headers: []HeaderField) AllocationError![]const u8 {
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

    var headers = Headers.parseFieldName(name);
    testing.expectError(error.RemoteProtocolError, headers);
}

test "Parse field name - Name is lowercased" {
    var name = try allocate(testing.allocator, "SeRvEr");
    defer testing.allocator.free(name);

    var value = try Headers.parseFieldName(name);

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

test "Parse header field - When colon is missing - Returns RemoteProtocolError" {
    var field = try allocate(testing.allocator, "ServerApache");
    defer testing.allocator.free(field);

    var headerField = Headers.parseHeaderField(field);

    testing.expectError(error.RemoteProtocolError, headerField);
}

test "Parse - When the headers does not end with an empty line - Returns NeedData" {
    var bytes = try allocate(testing.allocator, "ServerApache");
    defer testing.allocator.free(bytes);
    var stream = Stream.init(bytes);

    var headers = Headers.parse(testing.allocator, &stream);

    testing.expectError(error.NeedData, headers);
}

test "Parse" {
    var bytes = try allocate(testing.allocator, "server: Apache\r\ncontent-length: 51\r\n\r\n");
    defer testing.allocator.free(bytes);
    var stream = Stream.init(bytes);

    var headers = try Headers.parse(testing.allocator, &stream);
    defer testing.allocator.free(headers);

    testing.expect(std.mem.eql(u8, headers[0].name, "server"));
    testing.expect(std.mem.eql(u8, headers[0].value, "Apache"));
    testing.expect(std.mem.eql(u8, headers[1].name, "content-length"));
    testing.expect(std.mem.eql(u8, headers[1].value, "51"));
}

test "Serialize" {
    var headers = [_]HeaderField{
        HeaderField{ .name = "Host", .value = "httpbin.org" },
        HeaderField{ .name = "Server", .value = "Apache" },
    };

    var result = try Headers.serialize(testing.allocator, &headers);
    defer testing.allocator.free(result);

    testing.expect(std.mem.eql(u8, result, "Host: httpbin.org\r\nServer: Apache\r\n\r\n"));
}
