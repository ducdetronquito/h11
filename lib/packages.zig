const std = @import("std");

pub const http = std.build.Pkg {
    .name = "http",
    .path = "lib/http/src/main.zig",
    .dependencies = null,
};
