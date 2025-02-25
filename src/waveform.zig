// Understanding waveforms: https://github.com/Modos-Labs/Glider?tab=readme-ov-file#understanding-waveform
// TODO: Test waveform.zig against the real waveform file from rm2.
//
//

const std = @import("std");
const assert = std.debug.assert;

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();

//     var table = try Table.from_wbf(allocator, "./src/waveforms/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf");
//     defer Table.deinit(&table, allocator);

//     const waveform = try table.lookup(0, 20);
//     std.debug.print("Init phases ({}): ", .{waveform.items.len});
//     var step: usize = 0;
//     while (step < waveform.items.len) : (step += 1) {
//         const phase = waveform.items[step][0][30];
//         std.debug.print("{any} ", .{phase});
//     }
//     std.debug.print("\n",.{});
// }

pub const Phase = enum(u8) {
    Noop = 0b00,
    Black = 0b01,
    White = 0b10,
    Noop2 = 0b11,
};

/// Cell grayscale intensity (5 bits).
/// Only even values are used. 0 denotes full black, 30 full white
// TODO: Make Intensity a u5
const intensity_values = 1 << 5;
const PhaseMatrix = [intensity_values][intensity_values]Phase;
const Waveform = std.ArrayList(PhaseMatrix);
const Lookup = [][]usize;

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
        const length: u32 = try reader.readIntBig(u32);

        if (length == 0) {
            break;
        }

        const buffer = try aa.alloc(u8, length);
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

        // FIXME: fpl_lot doesn't actually checkout anymore since software v3.
        if (wbf_header.fpl_lot == fpl_lot) {
            return try std.mem.join(allocator, "/", &[_][]const u8{ searched_dir, entry.name });
        }
    }

    return null;
}

const WbfHeader = packed struct {
    checksum: u32, // CRC32 checksum
    filesize: u32, // Total file length
    serial: u32, // Unique serial number for the waveform file
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
    old_frame_rate: u8, // Old field used for frame rate specification,
    // (only supported value: 0x85 for 85 Hz)
    frame_rate: u8, // New frame rate field (in Hz)
    vcom_offset: u8,
    _reserved1: u16,
    extra_info_addr: u24,
    checksum1: u8, // Checksum for bytes 0-30 with 8 first bytes to 0
    wmta: u24,
    fvsn: u8,
    luts: u8,
    mode_count: u8, // Index of the last mode
    temp_range_count: u8, // Index of the last temperature range
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

        const header = @as(*WbfHeader, @alignCast(@ptrCast(header_bytes.ptr)));
        // NOTE: The original waved library converts WbfHeader fields to little-endian.
        // On Remarkable2, this doesn't actually need to happen.

        const checksum1 = basic_checksum(header_bytes[8..31]);
        if (header.checksum1 != checksum1) {
            std.log.err("Corrupted WBF header: expected checksum1 {d}, actual {d}\n", .{ header.checksum1, checksum1 });
            return error.InvalidWbfHeader;
        }

        const checksum2 = basic_checksum(header_bytes[32..47]);
        if (header.checksum2 != checksum2) {
            std.log.err("Corrupted WBF header: expected checksum2 {d}, actual {d}\n", .{ header.checksum2, checksum2 });
            return error.InvalidWbfHeader;
        }

        if (header.run_type != expected_run_type) {
            std.log.err("Invalid run type in WBF header: expected {d}, actual {d}", .{ expected_run_type, header.run_type });
            return error.InvalidWbfHeader;
        }

        if (header.fpl_platform != expected_fpl_platform) {
            const message = "Invalid FPL platform in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_fpl_platform, header.fpl_platform });
            return error.InvalidWbfHeader;
        }

        if (header.adhesive_run != expected_adhesive_run) {
            const message = "Invalid adhesive run in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_adhesive_run, header.adhesive_run });
            return error.InvalidWbfHeader;
        }

        if (header.waveform_type != expected_waveform_type) {
            const message = "Invalid waveform type in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_waveform_type, header.waveform_type });
            return error.InvalidWbfHeader;
        }

        if (header.waveform_revision != expected_waveform_revision) {
            const message = "Invalid waveform revision in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_waveform_revision, header.waveform_revision });
            return error.InvalidWbfHeader;
        }

        if (header.vcom_offset != expected_vcom_offset) {
            const message = "Invalid VCOM offset in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_vcom_offset, header.vcom_offset });
            return error.InvalidWbfHeader;
        }

        if (header.fvsn != expected_fvsn) {
            const message = "Invalid FVSN in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_fvsn, header.fvsn });
            return error.InvalidWbfHeader;
        }

        if (header.luts != expected_luts) {
            const message = "Invalid LUTS in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_luts, header.luts });
            return error.InvalidWbfHeader;
        }

        if (header.advanced_wfm_flags != expected_advanced_wfm_flags) {
            const message = "Invalid advanced WFM flags revision in WBF header: expected {d}, actual {d}";
            std.log.err(message, .{ expected_advanced_wfm_flags, header.advanced_wfm_flags });
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
    unknown,

    // Initialization mode used to force all pixels to go back to a
    // known white state
    init,

    // Fast, non-flashy update that only supports transitions to black or white
    du,

    // Same as DU but supports 4 gray tones
    du4,

    // Faster than DU and only supports transitions *between* black and white
    a2,

    // Full resolution mode (16 gray tones)
    gc16,

    // Full resolution mode with support for Regal
    glr16,
};

pub const ModeID = u8;

pub const Table = struct { // Display frame rate
    frame_rate: u8,
    // Number of available modes
    mode_count: ModeID,
    // Mappings of mode IDs to mode kinds and reverse mapping
    mode_kind_by_id: std.ArrayList(ModeKind),
    // Set of temperature thresholds
    // The last value is the max operating temperature
    temperatures: []Temperature,
    // All available waveforms. This table may be smaller than
    // `(temperatures.size() - 1) * mode_count` since some modes/temperatures
    // combinations reuse the same waveform
    waveforms: []Waveform,
    // Vector for retrieving the waveform for any given mode and temperature
    waveform_lookup: Lookup,

    //
    // Scan available modes and assign them a mode kind based on which
    // features they support.
    //
    fn populate_mode_kind_mappings(table: *Table) void {
        _ = table;
    }

    pub fn lookup(self: *const Table, mode: ModeID, temperature: Temperature) !*const Waveform {
        if (mode < 0 or mode >= self.mode_count) {
            std.log.err("Mode ID {} not supported, available modes are 0-{}", .{mode, self.mode_count - 1});
            return error.WaveformLookup;
        }

        if (temperature < self.temperatures[0]) {
            std.log.err("Temperature {} too low!", .{temperature});
            return error.WaveformLookup;
        }

        if (temperature > self.temperatures[self.temperatures.len - 1]) {
            std.log.err("Temperature {} too high!", .{temperature});
            return error.WaveformLookup;
        }

        var index: usize = 0;
        // -1 => the last temperature is the upper bound
        while (index < self.temperatures.len - 1) : (index += 1) {
            if (temperature < self.temperatures[index]) {
                return &self.waveforms[self.waveform_lookup[mode][index - 1]];
            }
        }

            return error.WaveformLookup;

    }

    // pub fn init(allocator: std.mem.Allocator) Table {}
    pub fn deinit(table: *Table, allocator: std.mem.Allocator) void {
        allocator.free(table.temperatures);
    }

    // Reads waveform table definitions from a WBF file and returns a parsed waveform table.
    pub fn from_wbf(allocator: std.mem.Allocator, path: []const u8) !Table {
        var result = Table{
            .frame_rate = 0,
            .mode_count = 0,
            .mode_kind_by_id = std.ArrayList(ModeKind).init(allocator),
            .temperatures = undefined,
            .waveforms = undefined,
            .waveform_lookup = undefined,
        };

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        var file_contents = try file.readToEndAlloc(allocator, 1024 * 1024 * 16); // 16MiB
        defer allocator.free(file_contents);

        var file_offset: usize = 0;

        const header = try WbfHeader.parse(file_contents[0..@sizeOf(WbfHeader)]);

        file_offset += @sizeOf(WbfHeader);

        result.frame_rate = if (header.frame_rate == 0) 85 else header.frame_rate;
        result.mode_count = header.mode_count + 1; // ?

        // Check expected size
        if (header.filesize != file_contents.len) {
            std.log.err("Invalid filesize in WBF header: specified {} bytes, actual {} bytes\n", .{ header.filesize, file_contents.len });
            return error.InvalidWbfHeader;
        }

        // Verify CRC32 checksum
        const zeroes = [_]u8{ 0, 0, 0, 0 };
        var crc_verif: u32 = 0;
        crc_verif = crc32_checksum(crc_verif, &zeroes);
        crc_verif = crc32_checksum(crc_verif, file_contents[4..]);

        if (header.checksum != crc_verif) {
            std.log.err("Corrupted WBF file: expected CRC32 0x{X}, actual 0x{X}\n", .{ header.checksum, crc_verif });
            return error.ReadingWbfFile;
        }

        // Parse temperature table
        result.temperatures = tb: {
            // header.temp_range_count doesn't account for lower bound and upper bound
            const temperature_count = header.temp_range_count + 2;

            const temps = try allocator.dupe(Temperature, file_contents[file_offset .. file_offset + temperature_count]);
            const checksum = basic_checksum(file_contents[file_offset .. file_offset + temperature_count]);
            const checksum_expected = file_contents[file_offset + temperature_count];
            if (checksum != checksum_expected) {
                std.log.err("Corrupted WBF temperatures: expected checksum 0x{X}, actual 0x{X}\n", .{ checksum_expected, checksum });
                return error.ReadingWbfFile;
            }

            file_offset += temperature_count;
            file_offset += 1; // don't forget the checksum!

            break :tb temps;
        };

        // Skip extra information (contains a string equal to the file name)
        {
            const file_name_string_len = file_contents[file_offset];
            file_offset += 1; // string len

            const checksum = basic_checksum(file_contents[file_offset - 1 .. file_offset - 1 + file_name_string_len + 1]);
            const checksum_expected = file_contents[file_offset - 1 + file_name_string_len + 1];
            if (checksum != checksum_expected) {
                std.log.err("Corrupted file name string: expected checksum 0x{X}, actual 0x{X}\n", .{ checksum_expected, checksum });
                return error.ReadingWbfFile;
            }
            file_offset += file_name_string_len + 1; // checksum
        }

        // Parse waveforms
        const blocks = try find_waveform_blocks(allocator, &header, file_contents, file_contents[file_offset..]);
        defer allocator.free(blocks);

        result.waveforms, result.waveform_lookup = try parseWaveforms(allocator, &header, blocks, file_contents, file_contents[file_offset..]);


        return result;
    }

    fn parseWaveforms(
        allocator: std.mem.Allocator,
        header: *const WbfHeader,
        blocks: []const u32,
        file: []const u8,
        table: []const u8,
    ) !struct { []Waveform, Lookup } {
        var waveforms = std.ArrayList(Waveform).init(allocator);

        var block_iterator: usize = 0;
        while (block_iterator + 1 != blocks.len) : (block_iterator += 1) {
            try waveforms.append(try parseWaveformBlock(
                allocator,
                file[blocks[block_iterator]..blocks[block_iterator + 1]],
            ));
        }

        const mode_count = header.mode_count + 1;
        const temp_count = header.temp_range_count + 1;
        var waveform_lookup = try allocator.alloc([]usize, mode_count);

        var table_offset: usize = 0;
        var mode: usize = 0;
        while (mode < mode_count) : (mode += 1) {
            var mode_ptr = @as(usize, @intCast(try parsePointer(table[table_offset .. table_offset + 4])));
            table_offset += 4; // parsePointer doesn't move forward the offset


            var temp_lookup = try std.ArrayList(usize).initCapacity(allocator, temp_count);
            defer temp_lookup.deinit();

            var temperature: usize = 0;
            while (temperature < temp_count) : (temperature += 1) {
                const waveform_begin = try parsePointer(file[mode_ptr .. mode_ptr + 4]);
                mode_ptr += 4;

                // This is going to require updating on 0.14.0... here ya go
                // https://ziglang.org/documentation/master/std/#std.sort.lowerBound
                const S = struct {
                    fn lower_u32(context: void, lhs: u32, rhs: u32) bool {
                        _ = context;
                        return lhs < rhs;
                    }
                };
                const lowerBound_index = std.sort.lowerBound(u32, waveform_begin, blocks, {}, S.lower_u32);
                try temp_lookup.append(lowerBound_index);
            }

            waveform_lookup[mode] = try temp_lookup.toOwnedSlice();
        }

        return .{ try waveforms.toOwnedSlice(), waveform_lookup };
    }

    /// Parse a waveform block in a WBF file.
    fn parseWaveformBlock(allocator: std.mem.Allocator, block: []const u8) !Waveform {
        var matrix: PhaseMatrix = undefined;
        var result = Waveform.init(allocator);

        var begin: usize = 0;
        const end = block.len - 2;

        var i: u8 = 0;
        var j: u8 = 0;
        var repeat_mode = true;

        while (begin != end) {
            const byte = block[begin];
            begin += 1;

            if (byte == 0xFC) {
                repeat_mode = !repeat_mode;
                continue;
            }

            const p4: Phase = @enumFromInt(byte & 3);
            const p3: Phase = @enumFromInt((byte >> 2) & 3);
            const p2: Phase = @enumFromInt((byte >> 4) & 3);
            const p1: Phase = @enumFromInt(byte >> 6);

            var repeat: usize = 1;

            if (repeat_mode and begin != end) {
                // In repeat_mode, each byte is followed by a repetition number;
                // otherwise, this number is assumed to be 1
                repeat = @as(usize, block[begin]) + 1;
                begin += 1;

                if (byte == 0xFF) {
                    break;
                }
            }

            var n: usize = 0;
            while (n < repeat) : (n += 1) {
                matrix[j + 0][i] = p1;
                matrix[j + 1][i] = p2;
                matrix[j + 2][i] = p3;
                matrix[j + 3][i] = p4;
                j += 4;

                if (j == intensity_values) {
                    j = 0;
                    i += 1;
                }

                if (i == intensity_values) {
                    i = 0;
                    try result.append(matrix);
                }
            }
        }

        return result;
    }

    // Computes the ordered list of waveform block addresses in a WBF file.
    fn find_waveform_blocks(allocator: std.mem.Allocator, header: *const WbfHeader, file: []const u8, table: []const u8) ![]u32 {
        // waved uses std::set... Zig doesn't have that so we use a Hash Map with void for value
        var hash_map = std.AutoArrayHashMap(u32, void).init(allocator);
        defer hash_map.deinit();

        const mode_count = header.mode_count + 1;
        const temp_count = header.temp_range_count + 1;

        var table_offset: usize = 0;

        var mode_index: usize = 0;
        while (mode_index < mode_count) : (mode_index += 1) {
            var mode_ptr = @as(usize, @intCast(try parsePointer(table[table_offset .. table_offset + 4])));
            table_offset += 4; // parsePointer doesn't move forward the offset

            var temperature: usize = 0;
            while (temperature < temp_count) : (temperature += 1) {
                const mode = file[mode_ptr .. mode_ptr + 4];
                const ptr = try parsePointer(mode);
                mode_ptr += 4;
                try hash_map.put(ptr, void{});
            }
        }

        // dance for including the length on the end
        var result = try std.ArrayList(u32).initCapacity(allocator, hash_map.keys().len + 1);
        try result.appendSlice(hash_map.keys());
        std.mem.sort(u32, result.items, {}, comptime std.sort.asc(u32));
        try result.append(@truncate(file.len));

        return result.toOwnedSlice();
    }

    // Read a pointer field to a WBF file section.
    fn parsePointer(ptr: []const u8) !u32 {
        assert(ptr.len == 4);
        const byte1: u8 = ptr[0];
        const byte2: u8 = ptr[1];
        const byte3: u8 = ptr[2];
        const checksum_expected = ptr[3];
        const checksum = @addWithOverflow(byte1, @addWithOverflow(byte2, byte3)[0])[0];

        if (checksum != checksum_expected) {
            std.log.err("Corrupted WBF pointer: expected checksum 0x{X}, actual 0x{X}\n", .{ checksum_expected, checksum });
            return error.CorruptedWBFPointer;
        }

        const result = @as(u32, @intCast(byte1 | @as(u32, byte2) << 8 | @as(u32, byte3) << 16));
        return result;
    }
};

const Temperature = u8;

pub fn crc32_checksum(initial: u32, data: []const u8) u32 {
    var crc: u32 = initial ^ 0xFFFFFFFF;

    for (data) |byte| {
        //crc = (crc >> 8) ^ crc32_table[(crc ^ @as(u8, @intCast(byte))) & 0xFF];
        crc = crc32_table[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }

    return crc ^ 0xFFFFFFFF;
}

const crc32_table = [_]u32{
    0x00000000,
    0x77073096,
    0xee0e612c,
    0x990951ba,
    0x076dc419,
    0x706af48f,
    0xe963a535,
    0x9e6495a3,
    0x0edb8832,
    0x79dcb8a4,
    0xe0d5e91e,
    0x97d2d988,
    0x09b64c2b,
    0x7eb17cbd,
    0xe7b82d07,
    0x90bf1d91,
    0x1db71064,
    0x6ab020f2,
    0xf3b97148,
    0x84be41de,
    0x1adad47d,
    0x6ddde4eb,
    0xf4d4b551,
    0x83d385c7,
    0x136c9856,
    0x646ba8c0,
    0xfd62f97a,
    0x8a65c9ec,
    0x14015c4f,
    0x63066cd9,
    0xfa0f3d63,
    0x8d080df5,
    0x3b6e20c8,
    0x4c69105e,
    0xd56041e4,
    0xa2677172,
    0x3c03e4d1,
    0x4b04d447,
    0xd20d85fd,
    0xa50ab56b,
    0x35b5a8fa,
    0x42b2986c,
    0xdbbbc9d6,
    0xacbcf940,
    0x32d86ce3,
    0x45df5c75,
    0xdcd60dcf,
    0xabd13d59,
    0x26d930ac,
    0x51de003a,
    0xc8d75180,
    0xbfd06116,
    0x21b4f4b5,
    0x56b3c423,
    0xcfba9599,
    0xb8bda50f,
    0x2802b89e,
    0x5f058808,
    0xc60cd9b2,
    0xb10be924,
    0x2f6f7c87,
    0x58684c11,
    0xc1611dab,
    0xb6662d3d,
    0x76dc4190,
    0x01db7106,
    0x98d220bc,
    0xefd5102a,
    0x71b18589,
    0x06b6b51f,
    0x9fbfe4a5,
    0xe8b8d433,
    0x7807c9a2,
    0x0f00f934,
    0x9609a88e,
    0xe10e9818,
    0x7f6a0dbb,
    0x086d3d2d,
    0x91646c97,
    0xe6635c01,
    0x6b6b51f4,
    0x1c6c6162,
    0x856530d8,
    0xf262004e,
    0x6c0695ed,
    0x1b01a57b,
    0x8208f4c1,
    0xf50fc457,
    0x65b0d9c6,
    0x12b7e950,
    0x8bbeb8ea,
    0xfcb9887c,
    0x62dd1ddf,
    0x15da2d49,
    0x8cd37cf3,
    0xfbd44c65,
    0x4db26158,
    0x3ab551ce,
    0xa3bc0074,
    0xd4bb30e2,
    0x4adfa541,
    0x3dd895d7,
    0xa4d1c46d,
    0xd3d6f4fb,
    0x4369e96a,
    0x346ed9fc,
    0xad678846,
    0xda60b8d0,
    0x44042d73,
    0x33031de5,
    0xaa0a4c5f,
    0xdd0d7cc9,
    0x5005713c,
    0x270241aa,
    0xbe0b1010,
    0xc90c2086,
    0x5768b525,
    0x206f85b3,
    0xb966d409,
    0xce61e49f,
    0x5edef90e,
    0x29d9c998,
    0xb0d09822,
    0xc7d7a8b4,
    0x59b33d17,
    0x2eb40d81,
    0xb7bd5c3b,
    0xc0ba6cad,
    0xedb88320,
    0x9abfb3b6,
    0x03b6e20c,
    0x74b1d29a,
    0xead54739,
    0x9dd277af,
    0x04db2615,
    0x73dc1683,
    0xe3630b12,
    0x94643b84,
    0x0d6d6a3e,
    0x7a6a5aa8,
    0xe40ecf0b,
    0x9309ff9d,
    0x0a00ae27,
    0x7d079eb1,
    0xf00f9344,
    0x8708a3d2,
    0x1e01f268,
    0x6906c2fe,
    0xf762575d,
    0x806567cb,
    0x196c3671,
    0x6e6b06e7,
    0xfed41b76,
    0x89d32be0,
    0x10da7a5a,
    0x67dd4acc,
    0xf9b9df6f,
    0x8ebeeff9,
    0x17b7be43,
    0x60b08ed5,
    0xd6d6a3e8,
    0xa1d1937e,
    0x38d8c2c4,
    0x4fdff252,
    0xd1bb67f1,
    0xa6bc5767,
    0x3fb506dd,
    0x48b2364b,
    0xd80d2bda,
    0xaf0a1b4c,
    0x36034af6,
    0x41047a60,
    0xdf60efc3,
    0xa867df55,
    0x316e8eef,
    0x4669be79,
    0xcb61b38c,
    0xbc66831a,
    0x256fd2a0,
    0x5268e236,
    0xcc0c7795,
    0xbb0b4703,
    0x220216b9,
    0x5505262f,
    0xc5ba3bbe,
    0xb2bd0b28,
    0x2bb45a92,
    0x5cb36a04,
    0xc2d7ffa7,
    0xb5d0cf31,
    0x2cd99e8b,
    0x5bdeae1d,
    0x9b64c2b0,
    0xec63f226,
    0x756aa39c,
    0x026d930a,
    0x9c0906a9,
    0xeb0e363f,
    0x72076785,
    0x05005713,
    0x95bf4a82,
    0xe2b87a14,
    0x7bb12bae,
    0x0cb61b38,
    0x92d28e9b,
    0xe5d5be0d,
    0x7cdcefb7,
    0x0bdbdf21,
    0x86d3d2d4,
    0xf1d4e242,
    0x68ddb3f8,
    0x1fda836e,
    0x81be16cd,
    0xf6b9265b,
    0x6fb077e1,
    0x18b74777,
    0x88085ae6,
    0xff0f6a70,
    0x66063bca,
    0x11010b5c,
    0x8f659eff,
    0xf862ae69,
    0x616bffd3,
    0x166ccf45,
    0xa00ae278,
    0xd70dd2ee,
    0x4e048354,
    0x3903b3c2,
    0xa7672661,
    0xd06016f7,
    0x4969474d,
    0x3e6e77db,
    0xaed16a4a,
    0xd9d65adc,
    0x40df0b66,
    0x37d83bf0,
    0xa9bcae53,
    0xdebb9ec5,
    0x47b2cf7f,
    0x30b5ffe9,
    0xbdbdf21c,
    0xcabac28a,
    0x53b39330,
    0x24b4a3a6,
    0xbad03605,
    0xcdd70693,
    0x54de5729,
    0x23d967bf,
    0xb3667a2e,
    0xc4614ab8,
    0x5d681b02,
    0x2a6f2b94,
    0xb40bbe37,
    0xc30c8ea1,
    0x5a05df1b,
    0x2d02ef8d,
};
