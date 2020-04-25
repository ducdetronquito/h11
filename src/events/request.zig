const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocationError = @import("errors.zig").AllocationError;
const ArrayList = std.ArrayList;
const EventError = @import("errors.zig").EventError;
const Headers = @import("headers.zig").Headers;
const HeaderField = @import("headers.zig").HeaderField;


pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []HeaderField,

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
    var headers = [_]HeaderField{HeaderField{ .name = "Host", .value = "httpbin.org" }};
    var request = Request{ .method = "GET", .target = "/xml", .headers = headers[0..] };

    var result = try request.serialize(testing.allocator);
    defer testing.allocator.free(result);

    testing.expect(std.mem.eql(u8, result, "GET /xml HTTP/1.1\r\nHost: httpbin.org\r\n\r\n"));
}
