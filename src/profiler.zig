const std = @import("std");
const build_config = @import("build_config");

pub const Profiler = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    call_stack: std.ArrayList(usize),
    
    const Entry = struct {
        name: []const u8,
        start_time: i128,
        end_time: i128,
        parent: ?usize,
        depth: u32,
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(Entry).init(allocator),
            .call_stack = std.ArrayList(usize).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.entries.deinit();
        self.call_stack.deinit();
    }
    
    pub fn beginFunction(self: *Self, name: []const u8) void {
        if (!build_config.profiling) return;
        
        const entry = Entry{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
            .end_time = 0,
            .parent = if (self.call_stack.items.len > 0) self.call_stack.items[self.call_stack.items.len - 1] else null,
            .depth = @intCast(self.call_stack.items.len),
        };
        
        self.entries.append(entry) catch return;
        const entry_index = self.entries.items.len - 1;
        self.call_stack.append(entry_index) catch return;
    }
    
    pub fn endFunction(self: *Self) void {
        if (!build_config.profiling) return;
        
        if (self.call_stack.items.len == 0) return;
        
        const entry_index = self.call_stack.items[self.call_stack.items.len - 1];
        _ = self.call_stack.pop();
        self.entries.items[entry_index].end_time = std.time.nanoTimestamp();
    }
    
    pub fn printReport(self: *Self) void {
        if (!build_config.profiling) return;
        
        std.debug.print("{{\"traceEvents\":[", .{});
        
        var first = true;
        for (self.entries.items) |entry| {
            if (entry.end_time == 0) continue;
            
            const start_us = @as(f64, @floatFromInt(entry.start_time)) / 1000.0;
            const end_us = @as(f64, @floatFromInt(entry.end_time)) / 1000.0;
            const duration_us = end_us - start_us;
            
            if (!first) std.debug.print(",", .{});
            first = false;
            
            std.debug.print("{{\"name\":\"{s}\",\"cat\":\"function\",\"ph\":\"X\",\"ts\":{d:.3},\"dur\":{d:.3},\"pid\":1,\"tid\":1}}", .{
                entry.name, start_us, duration_us
            });
        }
        
        std.debug.print("]}}\n", .{});
    }
};

pub var global_profiler: ?*Profiler = null;

pub fn initGlobal(allocator: std.mem.Allocator) !void {
    if (!build_config.profiling) return;
    
    const profiler = try allocator.create(Profiler);
    profiler.* = Profiler.init(allocator);
    global_profiler = profiler;
}

pub fn deinitGlobal(allocator: std.mem.Allocator) void {
    if (!build_config.profiling) return;
    
    if (global_profiler) |profiler| {
        profiler.printReport();
        profiler.deinit();
        allocator.destroy(profiler);
        global_profiler = null;
    }
}

pub fn profile(name: []const u8) ProfileScope {
    return ProfileScope.init(name);
}

pub const ProfileScope = struct {
    const Self = @This();
    
    pub fn init(name: []const u8) Self {
        if (build_config.profiling) {
            if (global_profiler) |profiler| {
                profiler.beginFunction(name);
            }
        }
        return Self{};
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
        if (build_config.profiling) {
            if (global_profiler) |profiler| {
                profiler.endFunction();
            }
        }
    }
};
