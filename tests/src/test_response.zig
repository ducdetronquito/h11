const std = @import("std");
const h11 = @import("h11");

const testing = std.testing;

test "Read server response" {
    var response = to_crlf_string(
        \\HTTP/1.1 200 OK
        \\Server: Apache
        \\Content-Length: 12
        \\Content-Type: text/plain
        \\
        \\Hello World!
    );
    try process_response_event(response);
}


test "Read server response - No Content-Length header defaults to 0" {
    var response = to_crlf_string(
        \\HTTP/1.1 200 OK
        \\
        \\
    );
    try process_response_event(response);
}


/// Process all events of a response buffer
/// It will fail if the connection fail returns the following errors: NeedData or RemoteProtocolError
fn process_response_event(content: []const u8) !void {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var connection = h11.Connection.init(allocator);
    defer connection.deinit();

    try connection.receiveData(content);

    while (true) {
        var event = try connection.nextEvent();
        switch(event) {
            h11.EventTag.Response => |response| response.deinit(),
            h11.EventTag.EndOfMessage => break,
            h11.EventTag.ConnectionClosed => break,
            else => continue,
        }
    }
}


/// Dirty hacks to use multi-line strings on Windows but with unix line breaks.
fn to_crlf_string(content: []const u8) []const u8 {
    var buffer = std.ArrayList(u8).init(std.debug.global_allocator);
    var cursor: usize = 0;

    while (cursor < content.len) {
        if (content[cursor] == '\n') {
            buffer.append('\r') catch unreachable;
        }
        buffer.append(content[cursor]) catch unreachable;
        cursor += 1;
    }

    return buffer.toSliceConst();
}
