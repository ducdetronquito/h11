const std = @import("std");

pub const Url = struct {
    protocol: []const u8,
    host: []const u8,
    target: []const u8,

    pub fn init(url: []const u8) Url {
        var url_without_prefix: []const u8 = url;
        if (std.mem.eql(u8, url[0..7], "http://")) {
            url_without_prefix = url[7..];
        }

        var host: []const u8 = url_without_prefix;
        var target: []const u8 = "/";

        for (url_without_prefix) |char, i| {
            if (char == '/') {
                host = url_without_prefix[0..i];
                target = url_without_prefix[i..];
            }
        }

        return Url{ .protocol = "http", .host = host, .target = target };
    }
};
