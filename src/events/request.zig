const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const parseHeaders = @import("headers.zig").parse;
const Method = @import("http").Method;
const ParsingError = @import("errors.zig").ParsingError;
const readUri = @import("utils.zig").readUri;
const std = @import("std");
const Version = @import("http").Version;

pub const Request = struct {
    method: Method,
    target: []const u8,
    version: Version,
    headers: Headers,

    pub const Error = error{
        MissingHost,
        TooManyHost,
    };

    pub fn init(method: Method, target: []const u8, version: Version, headers: Headers) Error!Request {
        // A single 'Host' header is mandatory for HTTP/1.1
        // Cf: https://tools.ietf.org/html/rfc7230#section-5.4
        var hostCount: u32 = 0;
        for (headers.items()) |header| {
            if (header.name.type == .Host) {
                hostCount += 1;
            }
        }
        if (hostCount == 0 and version == .Http11) {
            return error.MissingHost;
        }
        if (hostCount > 1) {
            return error.TooManyHost;
        }
        return Request{
            .method = method,
            .target = target,
            .version = version,
            .headers = headers,
        };
    }

    pub fn default(allocator: Allocator) Request {
        return Request{
            .method = .Get,
            .target = "/",
            .version = .Http11,
            .headers = Headers.init(allocator),
        };
    }

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }

    pub fn parse(allocator: Allocator, buffer: []const u8) ParsingError!Request {
        var line_end = std.mem.indexOfPosLinear(u8, buffer, 0, "\r\n") orelse return error.Incomplete;
        var requestLine = buffer[0..line_end];
        var cursor: usize = 0;

        var method = for (requestLine) |char, i| {
            if (char == ' ') {
                cursor += i + 1;
                var value = try Method.from_bytes(requestLine[0..i]);
                break value;
            }
        } else {
            return error.Invalid;
        };

        const target = try readUri(requestLine[cursor..]);
        cursor += target.len + 1;

        const version = Version.from_bytes(requestLine[cursor..]) orelse return error.Invalid;
        if (version != .Http11) {
            return error.Invalid;
        }

        var _headers = try parseHeaders(allocator, buffer[requestLine.len + 2 ..], 128);

        return Request{
            .headers = _headers,
            .version = version,
            .method = method,
            .target = target,
        };
    }

    pub fn serialize(self: Request, allocator: Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);

        // Serialize the request line
        try buffer.appendSlice(self.method.to_bytes());
        try buffer.append(' ');
        try buffer.appendSlice(self.target);
        try buffer.append(' ');
        try buffer.appendSlice(self.version.to_bytes());
        try buffer.appendSlice("\r\n");

        // Serialize the headers
        for (self.headers.items()) |header| {
            try buffer.appendSlice(header.name.raw());
            try buffer.appendSlice(": ");
            try buffer.appendSlice(header.value);
            try buffer.appendSlice("\r\n");
        }
        try buffer.appendSlice("\r\n");

        return buffer.toOwnedSlice();
    }
};

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Init - An HTTP/1.1 request must contain a 'Host' header" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();

    var request = Request.init(Method.Get, "/news/", Version.Http11, headers);
    try expectError(error.MissingHost, request);
}

test "Init - An HTTP/1.0 request may not contain a 'Host' header" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();

    _ = try Request.init(Method.Get, "/news/", Version.Http10, headers);
}

test "Init - A request must not contain multiple 'Host' header" {
    var headers = Headers.init(std.testing.allocator);
    _ = try headers.append("Host", "ziglang.org");
    _ = try headers.append("Host", "ziglang.org");
    defer headers.deinit();

    var request = Request.init(Method.Get, "/news/", Version.Http11, headers);
    try expectError(error.TooManyHost, request);
}

test "Serialize" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    _ = try headers.append("Host", "ziglang.org");
    _ = try headers.append("GOTTA-GO", "FAST!!");

    var request = try Request.init(Method.Get, "/news/", Version.Http11, headers);

    var result = try request.serialize(std.testing.allocator);
    defer std.testing.allocator.free(result);

    try expectEqualStrings(result, "GET /news/ HTTP/1.1\r\nHost: ziglang.org\r\nGOTTA-GO: FAST!!\r\n\r\n");
}

test "Parse - Success" {
    const content = "GET http://www.example.org/where?q=now HTTP/1.1\r\nUser-Agent: h11\r\nAccept-Language: en\r\n\r\n";

    var request = try Request.parse(std.testing.allocator, content);
    defer request.deinit();

    try expect(request.method == .Get);
    try expectEqualStrings(request.target, "http://www.example.org/where?q=now");
    try expect(request.version == .Http11);

    try expect(request.headers.len() == 2);
}

test "Parse - When the request line does not ends with a CRLF - Returns Incomplete" {
    const content = "GET http://www.example.org/where?q=now HTTP/1.1";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Incomplete, failure);
}

test "Parse - When the method contains an invalid character - Returns Invalid" {
    const content = "G\tET http://www.example.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the method and the target are not separated by a whitespace - Returns Invalid" {
    const content = "GEThttp://www.example.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the target contains an invalid character - Returns Invalid" {
    const content = "GET http://www.\texample.org/where?q=now HTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the target and the http version are not separated by a whitespace - Returns Invalid" {
    const content = "GET http://www.example.org/where?q=nowHTTP/1.1\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}

test "Parse - When the http version is not HTTP 1.1 - Returns Invalid" {
    const content = "GET http://www.example.org/where?q=now HTTP/4.2\r\n\r\n\r\n";

    const failure = Request.parse(std.testing.allocator, content);

    try expectError(error.Invalid, failure);
}
