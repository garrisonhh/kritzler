const std = @import("std");
const Color = @import("color.zig");
const Canvas = @import("canvas.zig").Canvas;

const Allocator = std.mem.Allocator;

/// generic configuration for a form element
pub const ElementConfig = struct {
    title: []const u8,
    fmt: []const u8 = "{}",
    color: Color = Color{},
};

/// constructor for nicely formatted tables
pub fn Table(comptime cols: []const ElementConfig) type {
    return struct {
        const Self = @This();

        const Row = [cols.len][]const u8;

        ally: Allocator,
        arena: std.heap.ArenaAllocator,
        title: []const u8,
        rows: std.ArrayList(Row),

        pub fn init(
            ally: Allocator,
            comptime title: []const u8,
            args: anytype
        ) Allocator.Error!Self {
            var arena = std.heap.ArenaAllocator.init(ally);

            return Self{
                .ally = ally,
                .arena = arena,
                .title = try std.fmt.allocPrint(arena.allocator(), title, args),
                .rows = std.ArrayList(Row).init(ally)
            };
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
            self.arena.deinit();
        }

        /// shorthand for allocPrint()ing on this ally
        pub fn print(
            self: *Self,
            comptime fmt: []const u8,
            args: anytype
        ) std.fmt.AllocPrintError![]u8 {
            return try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
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

        /// prints out table and deinitializes everything
        pub fn flush(
            self: *Self,
            writer: anytype
        ) (Allocator.Error || @TypeOf(writer).Error)!void {
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

/// takes a slice of whatever and formats it nicely!
pub fn List(comptime cfg: ElementConfig) type {
    return struct {
        const Self = @This();

        ally: Allocator,
        arena: std.heap.ArenaAllocator,
        list: std.ArrayList([]const u8),

        pub fn init(ally: Allocator) Self {
            return Self{
                .ally = ally,
                .arena = std.heap.ArenaAllocator.init(ally),
                .list = std.ArrayList([]const u8).init(ally),
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.list.deinit();
        }

        pub fn print(
            self: *Self,
            comptime fmt: []const u8,
            args: anytype
        ) std.fmt.AllocPrintError![]u8 {
            return std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        }

        pub fn add(
            self: *Self,
            elem: anytype
        ) (std.fmt.AllocPrintError || Allocator.Error)!void {
            try self.list.append(try self.print(cfg.fmt, .{elem}));
        }

        pub fn flush(
            self: *Self,
            writer: anytype
        ) (std.fmt.AllocPrintError || @TypeOf(writer).Error)!void {
            var canvas = Canvas.init(self.ally);
            defer canvas.deinit();

            try canvas.scribble(.{0, -1}, Color{ .fg = .cyan }, cfg.title, .{});

            for (self.list.items) |elem, i| {
                const y = @intCast(isize, i);

                const ord = try canvas.print("{} | ", .{i});
                try canvas.scribble(
                    .{-@intCast(isize, ord.len), y},
                    Color{ .fmt = .bold },
                    "{s}",
                    .{ord}
                );

                try canvas.scribble(.{0, y}, cfg.color, "{s}", .{elem});
            }

            try canvas.flush(writer);
            self.list.clearAndFree();
        }
    };
}

pub fn fast_list(
    ally: Allocator,
    comptime cfg: ElementConfig,
    elements: anytype,
    writer: anytype
) !void {
    var list = List(cfg).init(ally);
    defer list.deinit();

    for (elements) |elem| try list.add(elem);

    try list.flush(writer);
}