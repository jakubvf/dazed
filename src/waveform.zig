const std = @import("std");

const WbfHeader = packed struct {
    checksum: u32,          // CRC32 checksum
    filesize: u32,          // Total file length
    serial: u32,            // Unique serial number for the waveform file
    run_type: u8,
    fpl_platform: u8,
    fpl_lot: u16,
    adhesive_run: u8,
    waveform_version: u8,
    waveform_subversion: u8,
    waveform_type: u8,
    fpl_size: u8,
    mfg_code: u8,
    waveform_revision: u8,
    old_frame_rate: u8,     // Old field used for frame rate specification,
                            // (only supported value: 0x85 for 85 Hz)
    frame_rate: u8,         // New frame rate field (in Hz)
    vcom_offset: u8,
    _reserved1: u16,
    extra_info_addr: u24,
    checksum1: u8,          // Checksum for bytes 0-30 with 8 first bytes to 0
    wmta: u24,
    fvsn: u8,
    luts: u8,
    mode_count: u8,         // Index of the last mode
    temp_range_count: u8,   // Index of the last temperature range
    advanced_wfm_flags: u8,
    eb: u8,
    sb: u8,
    _reserved2: u8,
    _reserved3: u8,
    _reserved4: u8,
    _reserved5: u8,
    _reserved6: u8,
    checksum2: u8,
};

fn barcode_symbol_to_int(symbol: u8) ?i16 {
    if (symbol >= '0' and symbol <= '9') {
        // 0 - 9 get mapped to 0 - 9
        return @as(i16, @intCast(symbol - '0'));
    } else if (symbol >= 'A' and symbol <= 'H') {
        // A - H get mapped to 10 - 17
        return @as(i16, @intCast(symbol - 'A' + 10));
    } else if (symbol >= 'J' and symbol <= 'N') {
        // J - N get mapped to 18 - 22
        return @as(i16, @intCast(symbol - 'J' + 18));
    } else if (symbol >= 'Q' and symbol <= 'Z') {
        // Q - Z get mapped to 23 - 32
        return @as(i16, @intCast(symbol - 'Q' + 23));
    } else {
        return null;
    }
}

fn parse_header(header_bytes: []u8) !WbfHeader {
    std.debug.assert(header_bytes.len == @sizeOf(WbfHeader));

    var header = @as(WbfHeader, @bitCast(header_bytes.ptr.*));
    header.checksum = std.mem.readIntLittle(u32, header.checksum);
    header.filesize = std.mem.readIntLittle(u32, header.filesize);
    header.serial = std.mem.readIntLittle(u32, header.serial);
    header.fpl_lot = std.mem.readIntLittle(u16, header.fpl_lot);
    header._reserved1 = std.mem.readIntLittle(u16, header._reserved1);
    header.extra_info_addr = std.mem.readIntLittle(u32, header.extra_info_addr);
    header.wmta = std.mem.readIntLittle(u32, header.wmta);

}


pub fn discover_wbf_file(allocator: std.mem.Allocator) !?[]const u8 {
    // discover metadata
    var metadata_device = try std.fs.cwd().createFile("/dev/mmcblk2boot1", .{ .read = true });
    defer metadata_device.close();
    const reader = metadata_device.reader();

    var metadata = std.ArrayList([]const u8).init(allocator);
    while (true) {
        var length: u32 = try reader.readIntBig(u32);

        if (length == 0) {
            break;
        }

        var buffer = try allocator.alloc(u8, length);
        const length_read = try reader.read(buffer);
        std.debug.assert(length == length_read);
        try metadata.append(buffer);
    }

    if (metadata.items.len < 4) {
        return null;
    }

    // decode_fpl_number
    const fpl_lot = decode_fpl_number: {
        const barcode = metadata.items[3];
        if (barcode.len < 8) {
            return null;
        }

        const d6 = barcode_symbol_to_int(barcode[6]) orelse return null;
        const d7 = barcode_symbol_to_int(barcode[7]) orelse return null;

        if (d7 < 10) {
            // Values from 0 to 329
            break :decode_fpl_number d7 + d6 * 10;
        }

        // Values from 330 to 858
        break :decode_fpl_number d7 + 320 + (d6 - 10) * 23;
    };
    _ = fpl_lot;

    const dir = try std.fs.cwd().openIterableDir("/usr/share/remarkable", .{});
    var dir_iterator = dir.iterate();

    while (try dir_iterator.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".wbf")) {
            continue;
        }

        var opened_file = try dir.dir.openFile(entry.name, .{});
        defer opened_file.close();

        var wbf_header: [@sizeOf(WbfHeader)]u8 = undefined;
        const bytes_read = try opened_file.reader().readAll(wbf_header);
        std.debug.assert(bytes_read == wbf_header.len);


    }

    return "bruh";
}
