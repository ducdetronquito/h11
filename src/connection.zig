const Allocator = std.mem.Allocator;
pub const ClientSM = @import("state_machines/client.zig").ClientSM;
const Event = @import("events.zig").Event;
pub const ServerSM = @import("state_machines/server.zig").ServerSM;
pub const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");


fn Connection(comptime LocalState: type, comptime RemoteState: type) type {
    return struct {
        allocator: *Allocator,
        localState: LocalState,
        remoteState: RemoteState,

        pub fn init(allocator: *Allocator) Connection(LocalState, RemoteState) {
            var localState = LocalState.init(allocator);
            var remoteState = RemoteState.init(allocator);
            return Connection(LocalState, RemoteState){
                .allocator = allocator,
                .localState = localState,
                .remoteState = remoteState
            };
        }

        pub fn deinit(self: *Connection(LocalState, RemoteState)) void {
        }

        pub fn send(self: *Connection(LocalState, RemoteState), event: Event) SMError![]const u8 {
            return self.localState.send(event);
        }
    };
}

pub const Client = Connection(ClientSM, ServerSM);


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Send - Client can send an event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    client.localState.state = .SendBody;

    var result = try client.send(.EndOfMessage);
}
