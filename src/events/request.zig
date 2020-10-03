const Allocator = std.mem.Allocator;
const HeaderMap = @import("http").HeaderMap;
const Method = @import("http").Method;
const std = @import("std");
const Version = @import("http").Version;


pub const Request = struct {
    method: Method,
    target: []const u8,
    version: Version,
    headers: HeaderMap,

    pub const Error = error {
        MissingHost,
    };

    pub fn init(method: Method, target: []const u8, version: Version, headers: HeaderMap) Error!Request {
        if (version == .Http11) {
            // A single 'Host' header is mandatory for HTTP/1.1
            // Cf: https://tools.ietf.org/html/rfc7230#section-5.4
            if (!headers.contains("Host")) {
                return error.MissingHost;
            }
            //TODO:
            // When 'HeaderMap' will be a proper multimap
            // return an error when the request contains multiple 'Host' headers.
        }

        return Request {
            .method = method,
            .target = target,
            .version = version,
            .headers = headers,
        };
    }

    pub fn serialize(self: Request, allocator: *Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);

        // Serialize the request line
        try buffer.appendSlice(self.method.to_bytes());
        try buffer.append(' ');
        try buffer.appendSlice(self.target);
        try buffer.append(' ');
        try buffer.appendSlice(self.version.to_bytes());
        try buffer.appendSlice("\r\n");

        // Serialize the headers
        var iterator = self.headers.iterator();
        while (iterator.next()) |header| {
            try buffer.appendSlice(header.key);
            try buffer.appendSlice(": ");
            try buffer.appendSlice(header.value);
            try buffer.appendSlice("\r\n");
        }
        try buffer.appendSlice("\r\n");

        return buffer.toOwnedSlice();
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Init - A HTTP/1.1 request must contain a 'Host' header" {
    var headers = HeaderMap.init(std.testing.allocator);
    defer headers.deinit();

    var request = Request.init(Method.Get, "/news/", Version.Http11, headers);
    expectError(error.MissingHost, request);
}

test "Init - A HTTP/1.0 request may not contain a 'Host' header" {
    var headers = HeaderMap.init(std.testing.allocator);
    defer headers.deinit();

    var request = try Request.init(Method.Get, "/news/", Version.Http10, headers);
}


test "Serialize" {
    var headers = HeaderMap.init(std.testing.allocator);
    defer headers.deinit();
    _ = try headers.put("Host", "ziglang.org");
    _ = try headers.put("GOTTA-GO", "FAST!!");

    var request = try Request.init(Method.Get, "/news/", Version.Http11, headers);

    var result = try request.serialize(std.testing.allocator);
    defer std.testing.allocator.free(result);

    expect(std.mem.eql(u8, result, "GET /news/ HTTP/1.1\r\nHost: ziglang.org\r\nGOTTA-GO: FAST!!\r\n\r\n"));
}
