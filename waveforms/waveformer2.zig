const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tables_contents = comptime t: {
        var contents: [79][]const u8 = undefined;
        var i: usize = 0;
        while (i < 79) : (i += 1) {
            const filename = "remarkable_TB" ++ std.fmt.comptimePrint("{}", .{i}) ++ ".csv";
            contents[i] = @embedFile(filename);
        }
        break :t contents;
    };
    const tables = t: {
        var tables: [79]Table = undefined;
        var i: usize = 0;
        while (i < 79) : (i += 1) {
            tables[i] = try parse_table(allocator, tables_contents[i]);
        }
        break :t tables;
    };
    defer {
        for (tables) |transitions| {
            for (transitions) |transition| {
                allocator.free(transition.operations);
            }
            allocator.free(transitions);
        }
    }

    const sections = try parse_sections(allocator, @embedFile("remarkable_desc.iwf"));
    defer {
        for (sections, 0..) |section, i| {
            allocator.free(section.name);
            var iter = section.data.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            sections[i].data.deinit();
        }
        allocator.free(sections);
    }

    var waveform: Waveform = undefined;
    const eql = std.mem.eql;
    for (sections) |section| {
        if (eql(u8, section.name, "WAVEFORM")) {
            waveform.version = section.data.get("VERSION") orelse return error.InvalidIwf;
            waveform.prefix = section.data.get("PREFIX") orelse return error.InvalidIwf;
            waveform.name = section.data.get("NAME") orelse return error.InvalidIwf;
            waveform.bpp = try std.fmt.parseInt(u32, section.data.get("BPP") orelse return error.InvalidIwf, 10);
            waveform.mode_count = try std.fmt.parseInt(u32, section.data.get("MODES") orelse return error.InvalidIwf, 10);
            waveform.temp_count = try std.fmt.parseInt(u32, section.data.get("TEMPS") orelse return error.InvalidIwf, 10);
            waveform.table_count = try std.fmt.parseInt(u32, section.data.get("TABLES") orelse return error.InvalidIwf, 10);
            waveform.temp_upper_bound = try std.fmt.parseInt(u32, section.data.get("TUPBOUND") orelse return error.InvalidIwf, 10);
            waveform.temp_ranges = try allocator.alloc(u32, waveform.temp_count);
            waveform.frame_counts = try allocator.alloc(u32, waveform.table_count);
            waveform.modes = try allocator.alloc(Mode, waveform.mode_count);

            var iter = section.data.keyIterator();
            while (iter.next()) |entry| {
                if ((entry.*)[0] != 'T') continue;
                if ((entry.*)[1] == 'B') {
                    const tb_fc_stripped = std.mem.trim(u8, (entry.*)[2..], "FC");
                    const table_index = try std.fmt.parseInt(u32, tb_fc_stripped, 10);
                    waveform.frame_counts[table_index] = try std.fmt.parseInt(u32, section.data.get(entry.*) orelse return error.InvalidIwf, 10);
                } else if (std.ascii.isDigit((entry.*)[1])) {
                    const t_range_stripped = std.mem.trimRight(u8, (entry.*)[1..], "RANGE");
                    const temp_index = try std.fmt.parseInt(u32, t_range_stripped, 10);
                    waveform.temp_ranges[temp_index] = try std.fmt.parseInt(u32, section.data.get(entry.*) orelse return error.InvalidIwf, 10);
                }
            }
        } else {
            const mode_stripped = std.mem.trimLeft(u8, section.name, "MODE");
            const mode_index = try std.fmt.parseInt(u32, mode_stripped, 10);
            waveform.modes[mode_index] = Mode{
                .name = section.data.get("NAME") orelse return error.InvalidIwf,
                .tables = try allocator.alloc(Table, waveform.temp_count),
            };
            var iter = section.data.keyIterator();
            while (iter.next()) |entry| {
                if (entry.*[0] != 'T') continue;
                const t_table_stripped = std.mem.trimRight(u8, (entry.*)[1..], "TABLE");
                const table_index = try std.fmt.parseInt(u32, t_table_stripped, 10);
                const table_value = try std.fmt.parseInt(u32, section.data.get(entry.*) orelse return error.InvalidIwf, 10);
                waveform.modes[mode_index].tables[table_index] = tables[table_value];
            }
        }
    }
    defer {
        allocator.free(waveform.temp_ranges);
        allocator.free(waveform.frame_counts);
        for (waveform.modes) |mode| {
            allocator.free(mode.tables);
        }
        allocator.free(waveform.modes);
    }
}

const HashMap = std.StringHashMap([]const u8);

const Section = struct {
    name: []const u8,
    data: HashMap,
};

const Mode = struct {
    name: []const u8,
    tables: []Table,
};

const Waveform = struct {
    version: []const u8,
    prefix: []const u8,
    name: []const u8,
    bpp: u32,
    mode_count: u32,
    temp_count: u32,
    table_count: u32,
    temp_ranges: []u32,
    temp_upper_bound: u32,
    frame_counts: []u32,
    modes: []Mode,
};

test "iwf" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const desc_file = try std.fs.cwd().openFile("remarkable_desc.iwf", .{});
    defer desc_file.close();

    const desc = try desc_file.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(desc);
    const sections = try parse_sections(allocator, desc);
    defer {
        for (sections, 0..) |section, i| {
            allocator.free(section.name);
            var iter = section.data.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            sections[i].data.deinit();
        }
        allocator.free(sections);
    }

    // for (sections) |section| {
    //     std.debug.print("Section: {s} ({})\n", .{ section.name, section.data.count() });
    //     var iter = section.data.iterator();
    //     while (iter.next()) |entry| {
    //         std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    //     }
    // }
}

fn parse_sections(allocator: std.mem.Allocator, desc: []const u8) ![]Section {
    var sections = std.ArrayList(Section).init(allocator);
    var current_section: ?Section = null;

    var iter = std.mem.splitSequence(u8, desc, "\n");
    while (iter.next()) |line| {
        if (line.len == 0) continue;

        // look for section header
        if (line[0] == '[') {
            if (current_section) |section| {
                try sections.append(section);
            }

            const name = std.mem.trim(u8, line, &[_]u8{ '[', ']' });
            current_section = Section{
                .name = try allocator.dupe(u8, name),
                .data = HashMap.init(allocator),
            };
        } else {
            // parse entry
            const section = &(current_section orelse return error.InvalidIwf);
            var key_value = std.mem.splitSequence(u8, line, "=");
            const key = try allocator.dupe(
                u8,
                std.mem.trim(
                    u8,
                    key_value.next() orelse return error.InvalidIwf,
                    &[_]u8{' '},
                ),
            );
            const value = try allocator.dupe(
                u8,
                std.mem.trim(
                    u8,
                    key_value.next() orelse return error.InvalidIwf,
                    &[_]u8{' '},
                ),
            );
            try section.data.put(key, value);
        }
    }
    if (current_section) |section| {
        try sections.append(section);
        return sections.toOwnedSlice();
    } else {
        return error.InvalidIwf;
    }
}

// The csv file describes how to get from pixel A (1st value) to pixel B (2nd value)
// using a predefined set of operations (rest of the values).
// Supported operations are: 0 (noop), 1 (darken), 2 (brighten).
// Resource: https://gitlab.com/zephray/glider#understanding-waveform

pub const Operation = enum(u2) {
    Noop = 0,
    Darken = 1,
    Brighten = 2,
};

pub const Transition = struct {
    from: u5,
    to: u5,
    operations: []const Operation,
};

pub const Table = []const Transition;

test "csv" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // const table_file = try std.fs.cwd().openFile("remarkable_TB0.csv", .{});
    // defer table_file.close();
    // const table = try table_file.reader().readAllAlloc(allocator, 1024 * 1024);
    // defer allocator.free(table);

    const transitions = try parse_table(allocator, @embedFile("remarkable_TB0.csv"));
    defer {
        for (transitions) |transition| {
            allocator.free(transition.operations);
        }
        allocator.free(transitions);
    }
    // std.debug.print("Transition count: {}\n", .{transitions.len});
    // std.debug.print("Transition sample: {any}\n", .{transitions[1023]});
    // std.debug.print("allocated memory: {}\n", .{transitions.len * @sizeOf(Transition) + transitions.len * @sizeOf(@TypeOf(transitions[0].operations[0])) * transitions[0].operations.len});
    // std.debug.print("frame count: {}\n", .{transitions[0].operations.len});
}

fn parse_table(allocator: std.mem.Allocator, table: []const u8) ![]Transition {
    var transitions = std.ArrayList(Transition).init(allocator);
    var current_transition: ?Transition = null;

    var iter = std.mem.splitSequence(u8, table, "\n");
    while (iter.next()) |line| {
        if (line.len == 0) continue;

        var values = std.mem.splitSequence(u8, line, ",");

        const from = try std.fmt.parseInt(u5, values.next() orelse return error.InvalidTable, 10);
        const to = try std.fmt.parseInt(u5, values.next() orelse return error.InvalidTable, 10);
        current_transition = Transition{
            .from = from,
            .to = to,
            .operations = undefined,
        };

        var operations = std.ArrayList(Operation).init(allocator);
        while (values.next()) |value| {
            if (value.len != 1) break;
            const operation: Operation = @enumFromInt(value[0] - '0');
            try operations.append(operation);
        }
        current_transition.?.operations = try operations.toOwnedSlice();

        try transitions.append(current_transition.?);
    }

    return try transitions.toOwnedSlice();
}

fn TransitionComptime(comptime fc: u32) type {
    return struct {
        from: u5,
        to: u5,
        operations: [fc]Operation,
    };
}
test "csv-comptime" {
    // Disabled because it's too slow. Can do ~380 transitions in a reasonable amount of time.
    if (false) {
        const transitions = comptime t: {
            const table = @embedFile("remarkable_TB0.csv");
            const TransitionType = TransitionComptime(149);
            var transitions: [1024]TransitionType = undefined;
            var current_transition: ?TransitionType = null;
            // This is too low to parse the whole table (1024)
            @setEvalBranchQuota(1000000);

            var i: usize = 0;
            var iter = std.mem.splitSequence(u8, table, "\n");
            while (iter.next()) |line| : (i += 1) {
                if (line.len == 0) continue;

                var values = std.mem.splitSequence(u8, line, ",");

                const from = try std.fmt.parseInt(u5, values.next() orelse return error.InvalidTable, 10);
                const to = try std.fmt.parseInt(u5, values.next() orelse return error.InvalidTable, 10);
                current_transition = TransitionType{
                    .from = from,
                    .to = to,
                    .operations = undefined,
                };

                var j: usize = 0;
                while (values.next()) |value| : (j += 1) {
                    if (value.len != 1) break;
                    const operation: Operation = @enumFromInt(value[0] - '0');
                    current_transition.?.operations[j] = operation;
                }
                transitions[i] = current_transition.?;
            }

            break :t transitions;
        };

        std.debug.print("Transition count: {}\n", .{transitions.len});
        std.debug.print("Transition sample: {any}\n", .{transitions[0]});
        std.debug.print("frame count: {}\n", .{transitions[0].operations.len});
    }
}
