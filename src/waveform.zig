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


pub fn basic_checksum(range: []const u8) u8 {
    var result: u8 = 0;

    for (range) |v| {
        result = @addWithOverflow(result, v)[0];
    }

    return result;
}

// Set of values that we do not expect to change. To be on the safe side (since
// we’re not sure what those values mean precisely), operation will not proceed
// if those differ from the values in the WBF file
const expected_run_type = 17;
const expected_fpl_platform = 0;
const expected_adhesive_run = 25;
const expected_waveform_type = 81;
const expected_waveform_revision = 0;
const expected_vcom_offset = 0;
const expected_fvsn = 1;
const expected_luts = 4;
const expected_advanced_wfm_flags = 3;

/// Parse the header of a WBF file and check its integrity.
fn parse_header(header_bytes: []u8) !WbfHeader {
    std.debug.assert(header_bytes.len == @sizeOf(WbfHeader));

    var header = @as(*WbfHeader, @alignCast(@ptrCast(header_bytes.ptr)));
    // NOTE: The original waved library converts WbfHeader fields to little-endian.
    // On Remarkable2, this doesn't actually need to happen.

    const checksum1 = basic_checksum(header_bytes[8..31]);
    if (header.checksum1 != checksum1) {
        std.debug.print("Corrupted WBF header: expected checksum1 {d}, actual {d}\n", .{header.checksum1, checksum1});
        return error.InvalidWbfHeader;
    }

    const checksum2 = basic_checksum(header_bytes[32..47]);
    if (header.checksum2 != checksum2) {
        std.debug.print("Corrupted WBF header: expected checksum2 {d}, actual {d}\n", .{header.checksum2, checksum2});
        return error.InvalidWbfHeader;
    }

    if (header.run_type != expected_run_type) {
        std.debug.print("Invalid run type in WBF header: expected {d}, actual {d}", .{expected_run_type, header.run_type});
        return error.InvalidWbfHeader;
    }

    if (header.fpl_platform != expected_fpl_platform) {
        const message = "Invalid FPL platform in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_fpl_platform, header.fpl_platform});
        return error.InvalidWbfHeader;
    }

    if (header.adhesive_run != expected_adhesive_run) {
        const message = "Invalid adhesive run in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_adhesive_run, header.adhesive_run});
        return error.InvalidWbfHeader;
    }

    if (header.waveform_type != expected_waveform_type) {
        const message = "Invalid waveform type in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_waveform_type, header.waveform_type});
        return error.InvalidWbfHeader;
    }

    if (header.waveform_revision != expected_waveform_revision) {
        const message = "Invalid waveform revision in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_waveform_revision, header.waveform_revision});
        return error.InvalidWbfHeader;
    }

    if (header.vcom_offset != expected_vcom_offset) {
        const message = "Invalid VCOM offset in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_vcom_offset, header.vcom_offset});
        return error.InvalidWbfHeader;
    }

    if (header.fvsn != expected_fvsn) {
        const message = "Invalid FVSN in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_fvsn, header.fvsn});
        return error.InvalidWbfHeader;
    }

    if (header.luts != expected_luts) {
        const message = "Invalid LUTS in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_luts, header.luts});
        return error.InvalidWbfHeader;
    }

    if (header.advanced_wfm_flags != expected_advanced_wfm_flags) {
        const message = "Invalid advanced WFM flags revision in WBF header: expected {d}, actual {d}";
        std.debug.print(message, .{expected_advanced_wfm_flags, header.advanced_wfm_flags});
        return error.InvalidWbfHeader;
    }

    return header.*;
}


/// Discover the path to the appropriate WBF file for the current panel.
/// Return value is owned by the caller.
pub fn discover_wbf_file(allocator: std.mem.Allocator) !?[]const u8 {
    // Free temp values when done
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Discover metadata
    var metadata_device = try std.fs.cwd().createFile("/dev/mmcblk2boot1", .{ .read = true });
    defer metadata_device.close();
    const reader = metadata_device.reader();

    var metadata = std.ArrayList([]const u8).init(aa);
    while (true) {
        var length: u32 = try reader.readIntBig(u32);

        if (length == 0) {
            break;
        }

        var buffer = try aa.alloc(u8, length);
        const length_read = try reader.read(buffer);
        std.debug.assert(length == length_read);
        try metadata.append(buffer);
    }

    if (metadata.items.len < 4) {
        return error.InvalidMetadata;
    }

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

    const searched_dir = "/usr/share/remarkable";
    const dir = try std.fs.cwd().openIterableDir(searched_dir, .{});
    var dir_iterator = dir.iterate();

    while (try dir_iterator.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".wbf")) {
            continue;
        }

        var opened_file = try dir.dir.openFile(entry.name, .{});
        defer opened_file.close();

        var wbf_header_bytes: [@sizeOf(WbfHeader)]u8 = undefined;
        const bytes_read = try opened_file.reader().readAll(&wbf_header_bytes);
        std.debug.assert(bytes_read == wbf_header_bytes.len);

        // Ignore invalid files
        const wbf_header = parse_header(&wbf_header_bytes) catch continue;

        if (wbf_header.fpl_lot == fpl_lot) {
            return try std.mem.join(allocator, "/", &[_][]const u8{ searched_dir, entry.name });
        }
    }

    return null;
}
