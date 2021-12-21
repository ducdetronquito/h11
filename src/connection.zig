const ClientSM = @import("state_machines/client.zig").ClientSM;
const Event = @import("state_machines/events/main.zig").Event;
const ServerSM = @import("state_machines/server.zig").ServerSM;
const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");

pub fn Client(comptime Reader: type, comptime Writer: type) type {
    return struct {
        const Self = @This();
        localState: ClientSM(Writer),
        remoteState: ServerSM(Reader),

        pub fn init(reader: Reader, writer: Writer) Self {
            var localState = ClientSM(Writer).init(writer);
            var remoteState = ServerSM(Reader).init(reader);

            return Self{
                .localState = localState,
                .remoteState = remoteState,
            };
        }

        pub fn deinit(self: *Self) void {
            self.localState.deinit();
            self.remoteState.deinit();
        }

        pub fn write(self: *Self, event: Event) !void {
            try self.localState.write(event);
            switch (event) {
                .Request => |request| self.remoteState.framing_context.method = request.method,
                else => {},
            }
        }

        pub inline fn read(self: *Self, buffer: []u8) !Event {
            return self.remoteState.read(buffer);
        }
    };
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const Request = @import("state_machines/events/main.zig").Request;
const TestClient = Client(std.io.FixedBufferStream([]const u8).Reader, std.io.FixedBufferStream([]u8).Writer);

test "Send - Remember the request method when sending a request event" {
    var read_buffer = "";
    var fixed_read_buffer = std.io.fixedBufferStream(read_buffer);
    var write_buffer: [100]u8 = undefined;
    var fixed_write_buffer = std.io.fixedBufferStream(&write_buffer);
    var client = TestClient.init(fixed_read_buffer.reader(), fixed_write_buffer.writer());

    try client.write(.{ .Request = .{ .method = .Post, .target = "/" } });

    try expect(client.remoteState.framing_context.method == .Post);
}

test "Read - A Response event with a content length must be followed by a Data event and an EndOfMessage event." {
    var content = "HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.";
    var fixed_read_buffer = std.io.fixedBufferStream(content);
    var write_buffer: [100]u8 = undefined;
    var fixed_write_buffer = std.io.fixedBufferStream(&write_buffer);
    var client = TestClient.init(fixed_read_buffer.reader(), fixed_write_buffer.writer());

    try client.write(.{ .Request = .{ .target = "/" } });

    var buffer: [100]u8 = undefined;
    var event = try client.read(&buffer);
    try expect(event.Response.status_code == .Ok);
    try expect(event.Response.version == .Http11);

    event = try client.read(&buffer);
    try expectEqualStrings(event.Header.name.raw(), "Content-Length");
    try expectEqualStrings(event.Header.value, "34");

    event = try client.read(&buffer);
    try expect(event == .EndOfHeader);

    event = try client.read(&buffer);
    try expectEqualStrings(event.Data.bytes, "Ain't no sunshine when she's gone.");

    event = try client.read(&buffer);
    try expect(event == .EndOfMessage);
}
