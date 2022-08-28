const std = @import("std");
const Color = @import("color.zig");
const Canvas = @import("canvas.zig").Canvas;

const Allocator = std.mem.Allocator;

pub const TableCol = struct {
    title: []const u8,
    fmt: []const u8 = "{}",
    color: Color = Color{},
};

pub fn Table(comptime cols: []const TableCol) type {
    return struct {
        const Self = @This();

        const Row = [cols.len][]const u8;

        ally: Allocator,
        title: []const u8,
        rows: std.ArrayList(Row),

        pub fn init(
            ally: Allocator,
            comptime title: []const u8,
            args: anytype
        ) Allocator.Error!Self {
            return Self{
                .ally = ally,
                .title = try std.fmt.allocPrint(ally, title, args),
                .rows = std.ArrayList(Row).init(ally)
            };
        }

        pub fn deinit(self: *Self) void {
            self.ally.free(self.title);
            self.free_rows();
        }

        fn free_rows(self: *Self) void {
            for (self.rows.items) |row| {
                for (row) |cell| self.ally.free(cell);
            }
            self.rows.deinit();
        }

        /// allocPrint shorthand
        fn print(
            self: Self,
            comptime fmt: []const u8,
            args: anytype
        ) std.fmt.AllocPrintError![]u8 {
            return try std.fmt.allocPrint(self.ally, fmt, args);
        }

        pub fn add_row(self: *Self, args: anytype) !void {
            // get fields
            const fields = @typeInfo(@TypeOf(args)).Struct.fields;
            std.debug.assert(fields.len == cols.len);

            // print fields and store
            var row: Row = undefined;
            inline for (fields) |field, i| {
                const data = @field(args, field.name);
                row[i] = try self.print(cols[i].fmt, .{data});
            }

            try self.rows.append(row);
        }

        pub fn flush(self: *Self, writer: anytype) !void {
            // find column widths
            var widths: [cols.len]usize = undefined;
            inline for (cols) |col, i| widths[i] = col.title.len;

            for (self.rows.items) |row| {
                for (row) |cell, i| {
                    widths[i] = std.math.max(widths[i], cell.len);
                }
            }

            // x values where column starts
            var starts: [cols.len]isize = undefined;
            starts[0] = 0;

            for (widths[0..widths.len - 1]) |width, i| {
                starts[i + 1] = starts[i] + @intCast(isize, width) + 3;
            }

            // horizontal bar for separating title and column titles
            const bar_len = @intCast(usize, starts[starts.len - 1])
                          + widths[widths.len - 1];
            var bar = try self.ally.alloc(u8, bar_len);
            defer self.ally.free(bar);

            std.mem.set(u8, bar, '-');

            // draw everything
            var canvas = Canvas.init(self.ally);
            defer canvas.deinit();

            try canvas.scribble(
                .{0, -4},
                Color{ .fg = .cyan },
                "{s}",
                .{self.title}
            );

            try canvas.scribble(.{0, -3}, Color{}, "{s}", .{bar});

            inline for (cols) |col, i| {
                if (i > 0) {
                    try canvas.scribble(
                        .{starts[i] - 2, -2},
                        Color{},
                        "|",
                        .{}
                    );
                }

                try canvas.scribble(
                    .{starts[i], -2},
                    Color{},
                    "{s}",
                    .{col.title}
                );
            }

            try canvas.scribble(.{0, -1}, Color{}, "{s}", .{bar});

            for (self.rows.items) |row, i| {
                for (row) |cell, j| {
                    const y = @intCast(isize, i);

                    if (j > 0) {
                        try canvas.scribble(
                            .{starts[j] - 2, y},
                            Color{},
                            "|",
                            .{}
                        );
                    }

                    try canvas.scribble(
                        .{starts[j], y},
                        cols[j].color,
                        "{s}",
                        .{cell}
                    );
                }
            }

            try canvas.flush(writer);

            self.rows.shrinkAndFree(0);
        }
    };
}