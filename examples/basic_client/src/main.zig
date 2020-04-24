const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;
const allocator = std.testing.allocator;

pub fn main() anyerror!void {
    var response = try HttpClient.get(allocator, "http://httpbin.org/json");
    defer response.deinit();

    response.print();
}
