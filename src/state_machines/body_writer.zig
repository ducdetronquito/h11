const ContentLengthWriter = @import("content_length_writer.zig").ContentLengthWriter;
const Event = @import("events/main.zig").Event;
const Header = @import("http").Header;
const Method = @import("http").Method;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
pub const TransferEncoding = @import("encoding.zig").TransferEncoding;

pub const FramingContext = struct {
    method: Method = .Get,
    transfert_encoding: TransferEncoding = .Unknown,
    content_length: usize = 0,

    pub const Error = error{
        InvalidContentLength,
        UnknownTranfertEncoding,
    };

    pub inline fn analyze(self: *FramingContext, header: Header) Error!void {
        if (header.name.type == .ContentLength) {
            self.content_length = std.fmt.parseInt(usize, header.value, 10) catch return error.InvalidContentLength;
            self.transfert_encoding = .ContentLength;
        } else if (header.name.type == .TransferEncoding) {
            if (std.mem.endsWith(u8, header.value, "chunked")) {
                self.transfert_encoding = .Chunked;
            } else {
                return error.UnknownTranfertEncoding;
            }
        }
    }
};

pub const BodyWriterType = enum {
    ContentLength,
    NoContent,
};

pub const BodyWriter = union(BodyWriterType) {
    ContentLength: ContentLengthWriter,
    NoContent: void,

    pub const Error = ContentLengthWriter.Error;

    pub inline fn write(self: *BodyWriter, writer: anytype, bytes: []const u8) !usize {
        return switch (self.*) {
            .ContentLength => |*content_length_writer| try content_length_writer.write(writer, bytes),
            .NoContent => 0,
        };
    }

    pub inline fn is_done(self: *BodyWriter) bool {
        return switch (self.*) {
            .ContentLength => |*content_length_writer| content_length_writer.is_done(),
            .NoContent => unreachable,
        };
    }

    pub fn frame(context: FramingContext) !BodyWriter {
        if (context.method == .Head or context.method == .Connect or context.content_length == 0) {
            return .NoContent;
        }

        return BodyWriter{ .ContentLength = ContentLengthWriter{ .expected_length = context.content_length } };
    }
};
