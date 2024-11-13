// Wondering about defining these in cron format?

const std = @import("std");
const posix = std.posix;
const z = @import("zeit");
pub const parser = @import("parser.zig");

pub fn handleUSRSignal(_: c_int) callconv(.C) void {
    std.debug.print("signal received\n", .{});
}

pub fn trackSig() !void {
    try posix.sigaction(posix.SIG.USR1, &posix.Sigaction{
        .handler = .{ .handler = handleUSRSignal },
        .mask = posix.empty_sigset,
        .flags = 0,
    }, null);
}

fn isScheduleMatch(cs: parser.CronSchedule, t: z.Time) bool {
    const days = z.daysFromCivil(z.Date{ .day = t.day, .year = t.year, .month = t.month });
    const day_of_week = @intFromEnum(z.weekdayFromDays(days));

    return (cs.seconds[t.second] and
        cs.minutes[t.minute] and
        cs.hours[t.hour] and
        cs.days[t.day -| 1] and // t.day is 1-indexed
        cs.months[@intFromEnum(t.month) -| 1] and // t.month is 1-indexed
        cs.day_of_week[day_of_week]);
}

fn mkCommand(alloc: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(alloc);
    var iter = std.mem.splitScalar(u8, s, ' ');
    while (iter.next()) |slice| {
        try list.append(slice);
    }
    return list.toOwnedSlice();
}

fn loadEntries(alloc: std.mem.Allocator, conf_name: []const u8) ![]parser.CronEntry {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeFolder;
    const path = try std.fs.path.join(alloc, &.{ home, conf_name });
    defer alloc.free(path);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(alloc, 1024 * 1024); // 1MB max
    defer alloc.free(contents);

    const parsed = try parser.entries.parse(alloc, contents);
    return parsed.value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entries = try loadEntries(allocator, ".zcron");

    const stdout = std.io.getStdOut().writer();
    try stdout.print("zcron loaded with {} entries.\n", .{entries.len});

    try stdout.print("\nTODO:\n- allow comments in conf\n", .{});

    const local = try z.local(allocator, null);
    defer local.deinit();

    while (true) {
        const now = try z.instant(.{});
        const local_now = now.in(&local);

        for (entries) |entry| {
            if (isScheduleMatch(entry.schedule, local_now.time())) {
                try stdout.print("{s}\n", .{entry.title});
                const cmd = try mkCommand(allocator, entry.title);
                var cp = std.process.Child.init(cmd, allocator);
                try cp.spawn();
            }
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

test {
    std.testing.refAllDecls(@This());
}
