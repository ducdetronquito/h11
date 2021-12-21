const Data = @import("events/main.zig").Data;
const Event = @import("events/main.zig").Event;
const FramingContext = @import("body_writer.zig").FramingContext;
const BodyWriter = @import("body_writer.zig").BodyWriter;
const Header = @import("http").Header;
const Method = @import("http").Method;
const Request = @import("events/main.zig").Request;
const State = @import("states.zig").State;
const std = @import("std");
const Version = @import("http").Version;

pub fn ClientSM(comptime Writer: type) type {
    return struct {
        const Self = @This();
        body_writer: BodyWriter = undefined,
        state: State = .Idle,
        writer: Writer,
        request_info: struct {
            framing_context: FramingContext,
            host_header_count: usize,
            version: Version,
        } = .{ .framing_context = FramingContext{}, .host_header_count = 0, .version = .Http11 },

        const Error = error{ LocalProtocolError, MissingHostHeader, TooManyHostHeaders } || FramingContext.Error || Writer.Error || BodyWriter.Error;

        pub fn init(writer: Writer) Self {
            return .{ .writer = writer };
        }

        pub fn deinit(self: *Self) void {
            self.body_writer = undefined;
            self.request_info = .{
                .framing_context = FramingContext{},
                .host_header_count = 0,
                .version = .Http11,
            };
            self.state = State.Idle;
        }

        pub inline fn write(self: *Self, event: Event) Error!void {
            return switch (self.state) {
                .Idle => self.writeRequest(event),
                .SendHeader => self.writeHeader(event),
                .SendBody => self.writeData(event),
                else => return error.LocalProtocolError,
            } catch |err| {
                self.state = .Error;
                return err;
            };
        }

        inline fn writeRequest(self: *Self, event: Event) Error!void {
            switch (event) {
                .Request => |request| {
                    try request.write(self.writer);
                    self.request_info.framing_context.method = request.method;
                    self.request_info.version = request.version;
                    self.state = .SendHeader;
                },
                else => return error.LocalProtocolError,
            }
        }

        inline fn writeHeader(self: *Self, event: Event) Error!void {
            switch (event) {
                .Header => |header| {
                    try self.request_info.framing_context.analyze(header);
                    if (header.name.type == .Host) {
                        self.request_info.host_header_count += 1;
                    }
                    if (self.request_info.host_header_count > 1) {
                        return error.TooManyHostHeaders;
                    }
                    _ = try self.writer.write(header.name.as_http1());
                    _ = try self.writer.write(": ");
                    _ = try self.writer.write(header.value);
                    _ = try self.writer.write("\r\n");
                },
                .EndOfHeader => {
                    // A single 'Host' header is mandatory for HTTP/1.1
                    // Cf: https://tools.ietf.org/html/rfc7230#section-5.4
                    if (self.request_info.version == .Http11 and self.request_info.host_header_count == 0) {
                        return error.MissingHostHeader;
                    }
                    _ = try self.writer.write("\r\n");
                    self.body_writer = try BodyWriter.frame(self.request_info.framing_context);
                    switch (self.body_writer) {
                        .NoContent => self.state = .Done,
                        else => self.state = .SendBody,
                    }
                },
                else => return error.LocalProtocolError,
            }
        }

        fn writeData(self: *Self, event: Event) Error!void {
            switch (event) {
                .Data => |data| {
                    _ = try self.body_writer.write(self.writer, data.bytes);
                    if (self.body_writer.is_done()) {
                        self.state = .Done;
                    }
                },
                else => return error.LocalProtocolError,
            }
        }
    };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

const TestClientSM = ClientSM(std.io.FixedBufferStream([]u8).Writer);

test "Write - Success" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(fixed_buffer.writer());

    try client.write(.{ .Request = .{ .target = "/" } });
    try client.write(.{ .Header = try Header.init("Host", "www.ziglang.org") });
    try client.write(.EndOfHeader);

    var expected = "GET / HTTP/1.1\r\nHost: www.ziglang.org\r\n\r\n";
    try expect(std.mem.startsWith(u8, &buffer, expected));
    try expect(client.state == .Done);
}

test "Write - Fail when the host header is missing in an HTTP/1.1 request" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(fixed_buffer.writer());

    try client.write(.{ .Request = .{ .target = "/" } });
    const failure = client.write(.EndOfHeader);

    try expectError(error.MissingHostHeader, failure);
    try expect(client.state == .Error);
}

test "Write - HTTP/1.0 request may not contain a host header" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(fixed_buffer.writer());

    try client.write(.{ .Request = .{ .target = "/", .version = .Http10 } });
    try client.write(.EndOfHeader);

    var expected = "GET / HTTP/1.0\r\n\r\n";
    try expect(std.mem.startsWith(u8, &buffer, expected));
    try expect(client.state == .Done);
}

test "Write - Fail to send multiple host headers" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(fixed_buffer.writer());

    try client.write(.{ .Request = .{ .target = "/" } });
    try client.write(.{ .Header = try Header.init("Host", "www.ziglang.org") });
    const failure = client.write(.{ .Header = try Header.init("Host", "www.ziglang.org") });

    try expectError(error.TooManyHostHeaders, failure);
    try expect(client.state == .Error);
}

test "Write - Content-length framed request" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(fixed_buffer.writer());

    try client.write(.{ .Request = .{ .method = .Post, .target = "/" } });
    try client.write(.{ .Header = try Header.init("Host", "www.ziglang.org") });
    try client.write(.{ .Header = try Header.init("Content-Length", "14") });
    try client.write(.EndOfHeader);
    try client.write(.{ .Data = .{ .bytes = "GOTTA GO FAST!" } });

    var expected = "POST / HTTP/1.1\r\nHost: www.ziglang.org\r\nContent-Length: 14\r\n\r\nGOTTA GO FAST!";
    try expect(std.mem.startsWith(u8, &buffer, expected));
    try expect(client.state == .Done);
}
