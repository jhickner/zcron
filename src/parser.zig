const std = @import("std");
const m = @import("mecha");

pub const CronEntry = struct {
    title: []const u8,
    schedule: CronSchedule,
};

pub const CronSchedule = struct {
    seconds: [60]bool = [_]bool{true} ** 60,
    minutes: [60]bool = [_]bool{true} ** 60,
    hours: [24]bool = [_]bool{true} ** 24,
    days: [31]bool = [_]bool{true} ** 31,
    months: [12]bool = [_]bool{true} ** 12,
    day_of_week: [7]bool = [_]bool{true} ** 7,
};

/// A component of one segment of the cron entry, used during parsing
/// examples: "1", "*", "1-10/2"
const Component = struct {
    tp: union(enum) {
        all,
        single: u8,
        range: struct {
            start: u8,
            end: u8,
        },
    },
    step: ?u8 = null,
};

/////////////////////////////////////////////////////////////////////////////
// Parsers

pub const entries = m.many(entry, .{ .separator = line_break });

const entry = m.combine(.{
    schedule,
    space,
    m.many(m.ascii.range(32, 126), .{}),
}).map(toEntry);

const schedule = m.many(components, .{ .separator = space, .max = 6 }).convert(toSchedule);

const components = m.combine(.{
    m.many(component, .{ .separator = comma }),
    m.opt(step),
}).convert(maybeAddStep);

const component = m.oneOf(.{
    all,
    range,
    number.map(toSingle),
});

const all = m.ascii.char('*').mapConst(Component{ .tp = .all });

const range = m.combine(.{
    number,
    m.ascii.char('-').discard(),
    number,
}).convert(toRange);

const number = m.many(m.ascii.digit(10), .{ .collect = false }).map(digitsToNumber);

const step = m.combine(.{
    m.ascii.char('/').discard(),
    number,
});

const comma = m.ascii.char(',').discard();
const space = m.ascii.char(' ').discard();

const line_break = m.oneOf(.{
    m.ascii.char('\n'),
    m.ascii.char('\r'),
}).discard();

/////////////////////////////////////////////////////////////////////////////
// Conversion fns

fn toEntry(args: std.meta.Tuple(&[_]type{ CronSchedule, []const u8 })) CronEntry {
    return CronEntry{ .schedule = args[0], .title = args[1] };
}

fn digitsToNumber(digits: []const u8) u8 {
    var result: u8 = 0;
    for (digits) |digit| {
        result = result *| 10 +| (digit -| 48);
    }
    return result;
}

fn toSingle(d: u8) Component {
    return .{ .tp = .{ .single = d } };
}

fn maybeAddStep(_: std.mem.Allocator, args: std.meta.Tuple(&[_]type{ []Component, ?u8 })) ![]Component {
    var cs = args[0];
    if (args[1]) |n| {
        if (args[0].len != 1) return error.InvalidStep_RequiresOneSpecifier;
        if (cs[0].tp == .single) return error.InvalidStep_RequiresAllOrRange;
        cs[0].step = n;
    }
    return cs;
}

fn toRange(_: std.mem.Allocator, nums: std.meta.Tuple(&[_]type{ u8, u8 })) !Component {
    const start = nums[0];
    const end = nums[1];
    if (start > end) return error.InvalidRange;
    return .{ .tp = .{ .range = .{ .start = start, .end = end } } };
}

fn toSchedule(_: std.mem.Allocator, args: [][]Component) !CronSchedule {
    var result = CronSchedule{};

    // Apply components in order, as many as we have
    // seconds 0-59
    if (args.len > 0) result.seconds = try toScheduleRange(60, 0, args[0]);
    // minutes 0-59
    if (args.len > 1) result.minutes = try toScheduleRange(60, 0, args[1]);
    // hours 0-23
    if (args.len > 2) result.hours = try toScheduleRange(24, 0, args[2]);

    // days 1-31
    if (args.len > 3) result.days = try toScheduleRange(31, 1, args[3]);
    // months 1-12
    if (args.len > 4) result.months = try toScheduleRange(12, 1, args[4]);
    // days 0-6, 0==Sunday
    if (args.len > 5) result.day_of_week = try toScheduleRange(7, 0, args[5]);
    if (args.len > 6) return error.TooManyScheduleComponents;

    return result;
}

fn toScheduleRange(comptime S: usize, offset: usize, args: []Component) ![S]bool {
    var result = [_]bool{false} ** S;

    for (args) |c| {
        switch (c.tp) {
            .all => {
                const stp = c.step orelse 1;
                var i: u8 = 0;
                while (i < S) : (i += stp) {
                    result[i] = true;
                }
            },
            .single => |v| {
                if (v -| offset >= S) return error.ValueTooLarge;
                result[v -| offset] = true;
            },
            .range => |r| {
                if (r.start -| offset >= S or r.end -| offset >= S) return error.RangeTooLarge;

                const stp = c.step orelse 1;
                var i: u8 = r.start;
                while (i <= r.end) : (i += stp) {
                    result[i -| offset] = true;
                }
            },
        }
    }
    return result;
}

test "parser" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    try m.expectResult(u8, .{ .value = 123, .rest = "" }, number.parse(alloc, "123"));
    try m.expectResult(
        Component,
        .{ .value = .{ .tp = .{ .range = .{ .start = 1, .end = 10 } } }, .rest = "" },
        range.parse(alloc, "1-10"),
    );

    try m.expectResult(
        Component,
        .{ .value = .{ .tp = .all }, .rest = "" },
        component.parse(alloc, "*"),
    );
    try m.expectResult(
        Component,
        .{ .value = .{ .tp = .{ .single = 3 } }, .rest = "" },
        component.parse(alloc, "3"),
    );
    try m.expectResult(
        Component,
        .{ .value = .{ .tp = .{ .range = .{ .start = 1, .end = 10 } } }, .rest = "" },
        component.parse(alloc, "1-10"),
    );

    var cs2 = [_]Component{.{ .tp = .{ .range = .{ .start = 1, .end = 20 } }, .step = 5 }};
    try m.expectResult([]Component, .{ .value = cs2[0..], .rest = "" }, components.parse(alloc, "1-20/5"));

    try m.expectResult(CronSchedule, .{ .value = CronSchedule{}, .rest = "" }, schedule.parse(alloc, "* * * * * *"));

    const res = try entry.parse(alloc, "* * * * * * Hello World!");
    std.debug.assert(std.mem.eql(u8, res.value.title, "Hello World!"));

    const block =
        \\* * * * * * First entry
        \\0 0 0 0 0 0 Second entry
        \\* * 3 */3 * 4 Third entry
    ;
    const block_res = try entries.parse(alloc, block);
    std.debug.assert(block_res.value.len == 3);
}
