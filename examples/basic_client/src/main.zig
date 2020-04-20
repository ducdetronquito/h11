const std = @import("std");
const h11 = @import("h11");

pub fn main() anyerror!void {
    var client = h11.Client.init(std.testing.allocator);
    defer client.deinit();
    
    std.debug.warn("About to tcp connect\n", .{});
    var socket = try std.net.tcpConnectToHost(std.testing.allocator, "httpbin.org", 80);
    defer socket.close();

    var requestBytes = "GET /json HTTP/1.1\r\nHost: httpbin.org\r\nUser-Agent: curl/7.55.1\r\nAccept: */*\r\n\r\n";

    var nBytes = try socket.write(requestBytes);
    std.debug.warn("I have written {} bytes to the socket.\n", .{nBytes});

    var responseBytes = try std.testing.allocator.alloc(u8, 4096);
    defer std.testing.allocator.free(responseBytes);

    nBytes = try socket.read(responseBytes);
    std.debug.warn("I have read {} bytes from the socket.\n", .{nBytes});

    std.debug.warn("HERE IS THE RESPONSE:\n{}\n\n", .{responseBytes[0..nBytes]});
}
