const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocationError = @import("errors.zig").AllocationError;
const ArrayList = std.ArrayList;
const EventError = @import("errors.zig").EventError;
const Headers = @import("headers.zig").Headers;
const HeaderField = @import("headers.zig").HeaderField;
const Stream = @import("../stream.zig").Stream;

pub const Response = struct {
    statusCode: StatusCode,
    headers: []HeaderField,

    pub fn parse(stream: *Stream, allocator: *Allocator) EventError!Response {
        var statusLine = try Response.parseStatusLine(stream);

        var headers = try Headers.parse(allocator, stream);

        return Response{ .statusCode = statusLine.statusCode, .headers = headers };
    }

    pub fn parseStatusLine(stream: *Stream) EventError!StatusLine {
        var line = stream.readLine() catch return error.NeedData;

        if (line.len < 12) {
            return error.NeedData;
        }

        const httpVersion = line[0..9];
        if (!std.mem.eql(u8, httpVersion, "HTTP/1.1 ")) {
            return error.RemoteProtocolError;
        }

        const statusCode = std.fmt.parseInt(i32, line[9..12], 10) catch return error.RemoteProtocolError;


        return StatusLine{ .statusCode = @intToEnum(StatusCode, statusCode) };
    }
};

pub const StatusLine = struct {
    statusCode: StatusCode,
};

pub const StatusCode = enum(i32) {
    Continue = 100,
    SwitchingProtocol = 101,
    Ok = 200,
    Created = 201,
    Accepted = 202,
    NonAuthoritativeInformation = 203,
    NoContent = 204,
    ResetContent = 205,
    PartialContent = 206,
    MultipleChoice = 300,
    MovedPermanently = 301,
    Found = 302,
    SeeOther = 303,
    NotModified = 304,
    TemporaryRedirect = 307,
    PermanentRedirect = 308,
    BadRequest = 400,
    Unauthorized = 401,
    Forbidden = 403,
    NotFound = 404,
    MethodNotAllowed = 405,
    NotAcceptable = 406,
    ProxyAuthenticationRequired = 407,
    RequestTimeout = 408,
    Conflict = 409,
    Gone = 410,
    LengthRequired = 411,
    PreconditionFailed = 412,
    PayloadTooLarge = 413,
    UriTooLong = 414,
    UnsupportedMediaType = 415,
    RequestedRangeNotSatisfiable = 416,
    ExpectationFailed = 417,
    ImATeapot = 418,
    UpgradeRequired = 426,
    PreconditionRequired = 428,
    TooManyRequests = 429,
    RequestHeaderFieldsTooLarge = 431,
    UnavailableForLegalReasons = 451,
    InternalServerError = 500,
    NotImplemented = 501,
    BadGateway = 502,
    ServiceUnavailable = 503,
    GatewayTimeout = 504,
    HttpVersionNotSupported = 505,
    NetworkAuthenticationRequired = 511,

    pub fn reasonPhrase(self: StatusCode) []const u8 {
        return switch(self) {
            .Continue => "Continue",
            .SwitchingProtocol => "Switching Protocol",
            .Ok => "OK",
            .Created => "Created",
            .Accepted => "Accepted",
            .NonAuthoritativeInformation => "Non-Authoritative Information",
            .NoContent => "No Content",
            .ResetContent => "Reset Content",
            .PartialContent => "Partial Content",
            .MultipleChoice => "Multiple Choice",
            .MovedPermanently => "Moved Permanently",
            .Found => "Found",
            .SeeOther => "See Other",
            .NotModified => "Not Modified",
            .TemporaryRedirect => "Temporary Redirect",
            .PermanentRedirect => "Permanent Redirect",
            .BadRequest => "Bad Request",
            .Unauthorized => "Unauthorized",
            .Forbidden => "Forbidden",
            .NotFound => "Not Found",
            .MethodNotAllowed => "Method Not Allowed",
            .NotAcceptable => "Not Acceptable",
            .ProxyAuthenticationRequired => "Proxy Authentication Required",
            .RequestTimeout => "Request Timeout",
            .Conflict => "Conflict",
            .Gone => "Gone",
            .LengthRequired => "Length Required",
            .PreconditionFailed => "Precondition Failed",
            .PayloadTooLarge => "Payload Too Large",
            .UriTooLong => "URI Too Long",
            .UnsupportedMediaType => "Unsupported Media Type",
            .RequestedRangeNotSatisfiable => "Requested Range Not Satisfiable",
            .ExpectationFailed => "Expectation Failed",
            .ImATeapot => "I'm a teapot",
            .UpgradeRequired => "Upgrade Required",
            .PreconditionRequired => "Precondition Required",
            .TooManyRequests => "Too Many Requests",
            .RequestHeaderFieldsTooLarge => "Request Header Fields Too Large",
            .UnavailableForLegalReasons => "Unavailable For Legal Reasons",
            .InternalServerError => "Internal Server Error",
            .NotImplemented => "Not Implemented",
            .BadGateway => "Bad Gateway",
            .ServiceUnavailable => "Service Unavailable",
            .GatewayTimeout => "Gateway Timeout",
            .HttpVersionNotSupported => "HTTP Version Not Supported",
            .NetworkAuthenticationRequired => "Network Authentication Required",
        };
    }


    pub fn toBytes(self: StatusCode) []const u8 {
        return switch(self) {
            .Continue => "100",
            .SwitchingProtocol => "101",
            .Ok => "200",
            .Created => "201",
            .Accepted => "202",
            .NonAuthoritativeInformation => "203",
            .NoContent => "204",
            .ResetContent => "205",
            .PartialContent => "206",
            .MultipleChoice => "300",
            .MovedPermanently => "301",
            .Found => "302",
            .SeeOther => "303",
            .NotModified => "304",
            .TemporaryRedirect => "307",
            .PermanentRedirect => "308",
            .BadRequest => "400",
            .Unauthorized => "401",
            .Forbidden => "403",
            .NotFound => "404",
            .MethodNotAllowed => "405",
            .NotAcceptable => "406",
            .ProxyAuthenticationRequired => "407",
            .RequestTimeout => "408",
            .Conflict => "409",
            .Gone => "410",
            .LengthRequired => "411",
            .PreconditionFailed => "412",
            .PayloadTooLarge => "413",
            .UriTooLong => "414",
            .UnsupportedMediaType => "415",
            .RequestedRangeNotSatisfiable => "416",
            .ExpectationFailed => "417",
            .ImATeapot => "418",
            .UpgradeRequired => "426",
            .PreconditionRequired => "428",
            .TooManyRequests => "429",
            .RequestHeaderFieldsTooLarge => "431",
            .UnavailableForLegalReasons => "451",
            .InternalServerError => "500",
            .NotImplemented => "501",
            .BadGateway => "502",
            .ServiceUnavailable => "503",
            .GatewayTimeout => "504",
            .HttpVersionNotSupported => "505",
            .NetworkAuthenticationRequired => "511",
        };
    }
};

const testing = std.testing;

test "Parse Status Line- When the status line does not end with a CRLF - Returns NeedData" {
    var content = "HTTP/1.1 200 OK".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.NeedData, statusLine);
}

test "Parse Status Line - When the http version is not HTTP/1.1 - Returns RemoteProtocolError" {
    var content = "HTTP/2.0 200 OK\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.RemoteProtocolError, statusLine);
}

test "Parse Status Line - When the status code is not made of 3 digits - Returns RemoteProtocolError" {
    var content = "HTTP/1.1 20x OK\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = Response.parseStatusLine(&stream);

    testing.expectError(error.RemoteProtocolError, statusLine);
}

test "Parse Status Line" {
    var content = "HTTP/1.1 405 Method Not Allowed\r\n".*;
    var stream = Stream.init(&content);

    var statusLine = try Response.parseStatusLine(&stream);

    testing.expect(statusLine.statusCode == .MethodNotAllowed);
    testing.expect(stream.isEmpty());
}

test "Parse" {
    var content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 12\r\n\r\n".*;
    var stream = Stream.init(&content);

    var response = try Response.parse(&stream, testing.allocator);
    defer testing.allocator.free(response.headers);

    testing.expect(response.statusCode == .Ok);
    testing.expect(std.mem.eql(u8, response.headers[0].name, "server"));
    testing.expect(std.mem.eql(u8, response.headers[0].value, "Apache"));
    testing.expect(std.mem.eql(u8, response.headers[1].name, "content-length"));
    testing.expect(std.mem.eql(u8, response.headers[1].value, "12"));
}
