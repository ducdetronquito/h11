const std = @import("std");
const ArrayList = std.ArrayList;
const HeaderField = @import("parsers/headers.zig").HeaderField;

pub const Data = struct {
    pub body: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []HeaderField,
};

pub const Response = struct {
    pub statusCode: i32,
    pub headers: ArrayList(HeaderField),

    pub fn deinit(self: *const Response) void {
        self.headers.deinit();
    }
};

pub const EventTag = enum {
    ConnectionClosed,
    Data,
    EndOfMessage,
    Request,
    Response,
};

pub const Event = union(EventTag) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    Request: Request,
    Response: Response,
};
