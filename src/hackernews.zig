const std = @import("std");

const FramebufferDimensions = @import("display/framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();
const DrawingContext = @import("display/DrawingContext.zig");
const profiler = @import("profiler.zig");

pub fn run(allocator: std.mem.Allocator, display: *DrawingContext) !void {
    var prof_scope = profiler.profile("hackernews.run");
    defer prof_scope.deinit();

    const items = try fetchTopStories(allocator);
    defer items.deinit();

    const story_count = @min(20, items.value.len);

    for (items.value[0..story_count], 0..) |item_id, index| {
        const url = try std.fmt.allocPrint(allocator, base_url ++ "/item/{d}.json", .{item_id});
        defer allocator.free(url);

        const body = try fetch(allocator, url);
        defer allocator.free(body);

        const item = try std.json.parseFromSlice(Item, allocator, body, .{});
        defer item.deinit();

        try drawItem(display, item.value, index);
    }
}

fn drawItem(display: *DrawingContext, item: Item, index: usize) !void {
    var prof_scope = profiler.profile("hackernews.drawItem");
    defer prof_scope.deinit();

    const font_size = 32;
    const line_height = font_size + 8;
    const top = dims.upper_margin + @as(u32, @intCast(index)) * line_height;
    const left = dims.left_margin;

    if (item.title) |title| {
        try display.text(left, top, title);
    }
}

const base_url = "https://hacker-news.firebaseio.com/v0";
const headers_max_size = 1024;

fn fetch(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var prof_scope = profiler.profile("hackernews.fetch");
    defer prof_scope.deinit();

    std.debug.print("fetching {s}:\n", .{url});
    const uri = try std.Uri.parse(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var hbuffer: [headers_max_size]u8 = undefined;
    const options = std.http.Client.RequestOptions{ .server_header_buffer = &hbuffer };

    // Call the API endpoint
    var request = try client.open(std.http.Method.GET, uri, options);
    defer request.deinit();
    _ = try request.send();
    _ = try request.finish();
    _ = try request.wait();

    if (request.response.status != std.http.Status.ok) {
        return error.WrongStatusResponse;
    }

    const header_length = request.response.parser.header_bytes_len;
    std.debug.print("\t> {d} header bytes\n", .{header_length});

    const body_length = request.response.content_length orelse return error.NoBodyLength;
    std.debug.print("\t> {d} body bytes\n", .{body_length});

    const body_buffer = try allocator.alloc(u8, @truncate(body_length));
    _ = try request.readAll(body_buffer);

    return body_buffer;
}

fn fetchTopStories(allocator: std.mem.Allocator) !std.json.Parsed([]ItemId) {
    var prof_scope = profiler.profile("hackernews.fetchTopStories");
    defer prof_scope.deinit();

    const body = try fetch(allocator, base_url ++ "/topstories.json");
    defer allocator.free(body);

    return try std.json.parseFromSlice([]ItemId, allocator, body, .{});
}

const ItemId = usize;
const Item = struct {
    id: ItemId,
    type: []const u8,
    by: []const u8,
    time: usize,
    deleted: ?bool = null,
    text: ?[]const u8 = null,
    dead: ?bool = null,
    parent: ?ItemId = null,
    poll: ?ItemId = null,
    kids: ?[]ItemId = null,
    url: ?[]const u8 = null,
    score: ?usize = null,
    title: ?[]const u8 = null,
    parts: ?[]usize = null,
    descendants: ?usize = null,
};
