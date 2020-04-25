pub const AllocationError = @import("../errors.zig").AllocationError;

pub const EventError = error{
    LocalProtocolError,
    NeedData,
    RemoteProtocolError,
    OutOfMemory,
};
