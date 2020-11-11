pub const Data = @import("data.zig").Data;
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;

pub const EventType = enum {
    ConnectionClosed,
    Data,
    EndOfMessage,
    Request,
    Response,
};

pub const Event = union(EventType) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    Request: Request,
    Response: Response,

    pub fn deinit(self: Event) void {
        switch(self) {
            .Response => |response| {
                response.deinit();
            },
            .Data => |data| {
                data.deinit();
            },
            else => {},
        }
    }

    pub fn isResponse(self: Event) bool {
        return switch(self) {
            .Response => true,
            else => false,
        };
    }

    pub fn isData(self: Event) bool {
        return switch(self) {
            .Data => true,
            else => false,
        };
    }

    pub fn isEndOfMessage(self: Event) bool {
        return switch(self) {
            .EndOfMessage => true,
            else => false,
        };
    }

    pub fn isConnectionClosed(self: Event) bool {
        return switch(self) {
            .ConnectionClosed => true,
            else => false,
        };
    }
};
