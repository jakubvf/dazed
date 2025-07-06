const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    getBackBuffer: *const fn (ptr: *anyopaque) []u8,
    pageFlip: *const fn (ptr: *anyopaque) anyerror!void,
    getTemperature: *const fn (ptr: *anyopaque) anyerror!i32,
    waitForExit: *const fn (ptr: *anyopaque) void,
    deinit: *const fn (ptr: *anyopaque) void,
};


pub fn getBackBuffer(self: Self) []u8 {
    return self.vtable.getBackBuffer(self.ptr);
}

pub fn pageFlip(self: Self) anyerror!void {
    return self.vtable.pageFlip(self.ptr);

}
pub fn getTemperature(self: Self) anyerror!i32 {
    return self.vtable.getTemperature(self.ptr);
}
pub fn waitForExit(self: Self) void {
    return self.vtable.waitForExit(self.ptr);
}
pub fn deinit(self: Self) void {
    return self.vtable.deinit(self.ptr);
}
