const std = @import("std");
const ArrayList = std.ArrayList;
const HeaderField = @import("parsers/headers.zig").HeaderField;

pub const Response = struct {
    pub statusCode: i32,
    pub headers: ArrayList(HeaderField),

    pub fn deinit(self: *const Response) void {
        self.headers.deinit();
    }
};

pub const Data = struct {
    pub body: []const u8,
};

pub const EventTag = enum {
    Response,
    Data,
    EndOfMessage,
    ConnectionClosed,
};

pub const Event = union(EventTag) {
    Response: Response,
    Data: Data,
    EndOfMessage: void,
    ConnectionClosed: void,
};
