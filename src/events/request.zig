const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocationError = @import("errors.zig").AllocationError;
const ArrayList = std.ArrayList;
const EventError = @import("errors.zig").EventError;
const Headers = @import("headers.zig").Headers;
const HeaderField = @import("headers.zig").HeaderField;
const Stream = @import("../stream.zig").Stream;


const RequestLine = struct {
    method: []const u8,
    target: []const u8,
    httpVersion: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []HeaderField,

    pub fn parse(stream: *Stream, allocator: *Allocator) EventError!Request {
        var requestLine = try Request.parseRequestLine(stream);
        var headers = try Headers.parse(allocator, stream);
        return Request{ .method = requestLine.method, .target = requestLine.target, .headers = headers };
    }

    fn parseRequestLine(stream: *Stream) EventError!RequestLine {
        var line = stream.readLine() catch return error.NeedData;

        var requestLine = Stream.init(line);

        var method = requestLine.readUntil(' ') catch |err| return error.RemoteProtocolError;
        var target = requestLine.readUntil(' ') catch |err| return error.RemoteProtocolError;
        var httpVersion = requestLine.read();

        return RequestLine{ .method = method, .target = target, .httpVersion = httpVersion };
    }

    pub fn serialize(self: Request, allocator: *Allocator) EventError![]const u8 {
        var buffer = ArrayList(u8).init(allocator);

        var requestLine = try self.serializeRequestLine(allocator);
        defer allocator.free(requestLine);
        try buffer.appendSlice(requestLine);

        var headers = try Headers.serialize(allocator, self.headers);
        defer allocator.free(headers);

        try buffer.appendSlice(headers);

        return buffer.toOwnedSlice();
    }

    fn serializeRequestLine(self: Request, allocator: *Allocator) AllocationError![]const u8 {
        var buffer = ArrayList(u8).init(allocator);
        try buffer.appendSlice(self.method);
        try buffer.append(' ');
        try buffer.appendSlice(self.target);
        try buffer.appendSlice(" HTTP/1.1\r\n");
        return buffer.toOwnedSlice();
    }
};


const testing = std.testing;

test "Serialize" {
    var headers = [_]HeaderField{
        HeaderField{ .name = "Host", .value = "httpbin.org" },
    };

    var request = Request{ .method = "GET", .target = "/xml", .headers = &headers };

    var result = try request.serialize(testing.allocator);
    defer testing.allocator.free(result);

    testing.expect(std.mem.eql(u8, result, "GET /xml HTTP/1.1\r\nHost: httpbin.org\r\n\r\n"));
}

test "ParseRequestLine - Success" {
    var content = "GET /hello.txt HTTP/1.1\r\n".*;
    var stream = Stream.init(&content);
    var requestLine = try Request.parseRequestLine(&stream);

    testing.expect(std.mem.eql(u8, requestLine.method, "GET"));
    testing.expect(std.mem.eql(u8, requestLine.target, "/hello.txt"));
    testing.expect(std.mem.eql(u8, requestLine.httpVersion, "HTTP/1.1"));
}

test "ParseRequestLine - When do not ends with a CRLF - Returns NeedData" {
    var content = "GET /hello.txt HTTP/1.1".*;
    var stream = Stream.init(&content);
    var requestLine = Request.parseRequestLine(&stream);
    testing.expectError(error.NeedData, requestLine);
}

test "ParseRequestLine - When http method is not followed by a whitespace - Returns RemoteProtocolError" {
    var content = "GET\r\n".*;
    var stream = Stream.init(&content);
    var requestLine = Request.parseRequestLine(&stream);
    testing.expectError(error.RemoteProtocolError, requestLine);
}

test "ParseRequestLine - When target is not followed by a whitespace - Returns RemoteProtocolError" {
    var content = "GET /hello.txt\r\n".*;
    var stream = Stream.init(&content);
    var requestLine = Request.parseRequestLine(&stream);
    testing.expectError(error.RemoteProtocolError, requestLine);
}

test "Parse - Success" {
    var content = "GET /hello.txt HTTP/1.1\r\nUser-Agent: h11/0.1.0\r\nHost: www.example.com\r\nAccept-Language: en, mi\r\n\r\n".*;
    var stream = Stream.init(&content);

    var request = try Request.parse(&stream, testing.allocator);
    defer testing.allocator.free(request.headers);

    testing.expect(std.mem.eql(u8, request.method, "GET"));
    testing.expect(std.mem.eql(u8, request.target, "/hello.txt"));
    testing.expect(std.mem.eql(u8, request.headers[0].name, "user-agent"));
    testing.expect(std.mem.eql(u8, request.headers[0].value, "h11/0.1.0"));
    testing.expect(std.mem.eql(u8, request.headers[1].name, "host"));
    testing.expect(std.mem.eql(u8, request.headers[1].value, "www.example.com"));
    testing.expect(std.mem.eql(u8, request.headers[2].name, "accept-language"));
    testing.expect(std.mem.eql(u8, request.headers[2].value, "en, mi"));
}
