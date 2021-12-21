pub const ContentLengthWriter = struct {
    expected_length: usize,
    written_bytes: usize = 0,

    pub const Error = error{
        BodyTooLarge,
    };

    pub inline fn is_done(self: *ContentLengthWriter) bool {
        return self.written_bytes == self.expected_length;
    }

    pub inline fn write(self: *ContentLengthWriter, writer: anytype, bytes: []const u8) !usize {
        if (self.written_bytes > self.expected_length) {
            return error.BodyTooLarge;
        }

        const count = try writer.write(bytes);
        self.written_bytes += count;
        return count;
    }
};
