const std = @import("std");

const FramebufferDimensions = @import("display/framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();

pub fn run(allocator: std.mem.Allocator, display: anytype) !void {
    const items = try fetchTopStories(allocator);
    defer items.deinit();

    const first_item_id = items.value[0];

    const url = try std.fmt.allocPrint(allocator, base_url ++ "/item/{d}.json", .{first_item_id});
    defer allocator.free(url);

    const body = try fetch(allocator, url);
    defer allocator.free(body);

    const first_item = try std.json.parseFromSlice(Item, allocator, body, .{});
    defer first_item.deinit();

}

fn drawItem(display: anytype, item: Item) !void {
    const font_size = 64;
    const top = dims.real_height - dims.upper_margin - font_size;
    const left = dims.left_margin + font_size;
    try display.text(left, top, item.value.title.?);

}

const base_url = "https://hacker-news.firebaseio.com/v0";
const headers_max_size = 1024;

fn fetch(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
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
    std.debug.print("\t> {d} header bytes\n", .{ header_length });

    const body_length = request.response.content_length orelse return error.NoBodyLength;
    std.debug.print("\t> {d} body bytes\n", .{ body_length });

    const body_buffer = try allocator.alloc(u8, body_length);
    _ = try request.readAll(body_buffer);

    return body_buffer;
}

fn fetchTopStories(allocator: std.mem.Allocator) !std.json.Parsed([]ItemId) {
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
