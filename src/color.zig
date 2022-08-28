//! for easily using ansi terminal color codes

const std = @import("std");

const Self = @This();

pub const Format = enum(u32) {
    bold = 1,
    underline = 4,
    blink = 5,
    crossed_out = 9,
    normal = 22,
};

pub const Color = enum(u32) {
    // fg ansi code is +30 from these numbers, bg is +40
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    default = 9,
};

fg: Color = .default,
bg: Color = .default,
fmt: Format = .normal,

pub fn format(
    self: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype
) @TypeOf(writer).Error!void {
    _ = fmt;
    _ = options;

    // ansi color code
    const code = "\x1b[{d}m";
    try writer.print(code ** 4, .{
        0, // reset
        @enumToInt(self.fmt),
        30 + @enumToInt(self.fg),
        40 + @enumToInt(self.bg)
    });
}