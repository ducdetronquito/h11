const std = @import("std");
const Allocator = std.mem.Allocator;
const h11 = @import("h11");

pub const Response = struct {
    allocator: *Allocator,
    statusCode: i32,
    headers: []h11.HeaderField,
    body: []const u8,
    // `buffer` stores the bytes read from the socket.
    // This allow to keep `headers` and `body` fields accessible after
    // the client  connection is deinitialized.
    buffer: []const u8,

    pub fn init(allocator: *Allocator) Response {
        return Response{ .allocator = allocator, .statusCode = 0, .headers = &[_]h11.HeaderField{}, .body = &[_]u8{}, .buffer = &[_]u8{} };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.headers);
        self.allocator.free(self.buffer);
    }

    pub fn print(self: *Response) void {
        std.debug.warn("Status Code: {}\n", .{self.statusCode});
        std.debug.warn("----- Headers -----\n", .{});
        for (self.headers) |header| {
            std.debug.warn("{} = {}\n", .{ header.name, header.value });
        }
        std.debug.warn("----- Body ----- \n{}\n", .{self.body});
    }
};
