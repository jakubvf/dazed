const std = @import("std");

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
        const wbf_header = WbfHeader.parse(&wbf_header_bytes) catch continue;

        if (wbf_header.fpl_lot == fpl_lot) {
            return try std.mem.join(allocator, "/", &[_][]const u8{ searched_dir, entry.name });
        }
    }

    return null;
}

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


    /// Parse the header of a WBF file and check its integrity.
    pub fn parse(header_bytes: []u8) !WbfHeader {
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

};


///
/// Waveform types.
///
/// Users can usually choose from several kinds of waveforms that provide
/// different trade-offs between image fidelity and rendering speed.
///
/// See <https://www.waveshare.com/w/upload/c/c4/E-paper-mode-declaration.pdf>
///
const ModeKind = enum {
    Unknown,

    // Initialization mode used to force all pixels to go back to a
    // known white state
    Init,

    // Fast, non-flashy update that only supports transitions to black or white
    Du,

    // Same as DU but supports 4 gray tones
    Du4,

    // Faster than DU and only supports transitions *between* black and white
    A2,

    // Full resolution mode (16 gray tones)
    Gc16,

    // Full resolution mode with support for Regal
    Glr16,
};

pub const ModeID = u8;

pub const Table = struct {
    // Display frame rate
    frame_rate: u8,
    // Number of available modes
    mode_count: ModeID,
    // Mappings of mode IDs to mode kinds and reverse mapping
    mode_kind_by_id: std.ArrayList(ModeKind),
    // Set of temperature thresholds
    // The last value is the maximal operating temperature
    temperatures: []Temperature,
    // All available waveforms. This table may be smaller than
    // `(temperatures.size() - 1) * mode_count` since some modes/temperatures
    // combinations reuse the same waveform
    // waveforms: std.ArrayList(Waveform),
    // Vector for retrieving the waveform for any given mode and temperature
    // waveform_lookup: Lookup,

    //
    // Scan available modes and assign them a mode kind based on which
    // features they support.
    //
    fn populate_mode_kind_mappings(table: *Table) void {
        _ = table;
    }

    // pub fn init(allocator: std.mem.Allocator) Table {}
    pub fn deinit(table: *Table) void {
        _ = table;
    }

    // Reads waveform table definitions from a WBF file and returns a parsed waveform table.
    pub fn from_wbf(allocator: std.mem.Allocator, path: []const u8) !Table {
        var result = Table{
            .frame_rate = 0,
            .mode_count = 0,
            .mode_kind_by_id = std.ArrayList(ModeKind).init(allocator),
            .temperatures = undefined,
        };

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        var file_contents = try file.readToEndAlloc(allocator, 1024 * 1024 * 16); // 16MiB
        defer allocator.free(file_contents);

        const header = try WbfHeader.parse(file_contents);

        result.frame_rate = if (header.frame_rate == 0) 85 else header.frame_rate;
        result.mode_count = header.mode_count + 1; // ?

        // Check expected size
        if (header.filesize != file_contents.len) {
            std.debug.print("Invalid filesize in WBF header: specified {} bytes, actual {} bytes\n", .{header.filesize, file_contents.len});
            return error.InvalidWbfHeader;
        }

        // Verify CRC32 checksum
        const crc_verif = crc32_checksum(file_contents[4..]);
        if (header.checksum != crc_verif) {
            std.debug.print("Corrupted WBF file: expected CRC32 0x{X}, actual 0x{X}\n", .{header.checksum, crc_verif});
            return error.InvalidWbfHeader;
        }

        // Parse temperature table
        const count = header.temp_range_count + 2;
        result.temperatures = try parse_temperatures(allocator, file_contents[@sizeOf(WbfHeader)..count]);

        return result;
    }

    fn parse_temperatures(allocator: std.mem.Allocator, temperatures_bytes_and_checksum: []const u8) ![]Temperature {
        var temperatures = try allocator.alloc(Temperature, temperatures_bytes_and_checksum.len);
        for (temperatures_bytes_and_checksum, 0..temperatures_bytes_and_checksum.len - 1) |value, i| {
            temperatures[i] = @as(i8, @bitCast(value));
        }

        const checksum = basic_checksum(temperatures_bytes_and_checksum[0..temperatures_bytes_and_checksum.len - 1]);
        const checksum_expected = temperatures_bytes_and_checksum[temperatures_bytes_and_checksum.len - 1];

        if (checksum != checksum_expected) {
            return error.CorruptedWBFTemperatures;
        }

        return temperatures;
    }
};

const Temperature = i8;

const crc32_table = [_]u32{
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f,
    0xe963a535, 0x9e6495a3, 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9,
    0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c,
    0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d, 0x76dc4190, 0x01db7106,
    0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d,
    0x91646c97, 0xe6635c01, 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7,
    0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa,
    0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683, 0xe3630b12, 0x94643b84,
    0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb,
    0x196c3671, 0x6e6b06e7, 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55,
    0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28,
    0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242,
    0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69,
    0x616bffd3, 0x166ccf45, 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693,
    0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
};

pub fn crc32_checksum(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;

    for (data) |byte| {
        crc = (crc >> 8) ^ crc32_table[(crc ^ @as(u8, @intCast(byte))) & 0xFF];
    }

    return ~crc;
}
