
pub const EventTag = enum {
    Response,
    Data,
    EndOfMessage,
    ConnectionClosed,
};


pub const Event = union(EventTag) {
    Response: struct { statusCode: i32, reason: []const u8 },
    Data: struct {body: []const u8},
    EndOfMessage: void,
    ConnectionClosed: void,
};
