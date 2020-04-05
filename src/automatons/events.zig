const std = @import("std");
const StringHashMap = std.StringHashMap;


pub const Response = struct {
    pub statusCode: i32,
    pub reason: []const u8,
    pub headers: StringHashMap([]const u8)
};


pub const Data = struct {
    pub body: []const u8
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
