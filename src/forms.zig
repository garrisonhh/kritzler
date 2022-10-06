//! forms provide easy ways to produce standardized output.

const std = @import("std");
const types = @import("types.zig");
const Texture = @import("texture.zig");
const Format = @import("format.zig").Format;

const Allocator = std.mem.Allocator;
const Pos = types.Pos;

/// just add rows with `addRow()` and `display()`
pub fn Table(headers: []const []const u8) type {
    std.debug.assert(headers.len > 0);

    return struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        rows: std.ArrayListUnmanaged([headers.len]Texture),

        pub fn init(ally: Allocator) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(ally),
                .rows = .{},
            };
        }

        pub fn deinit(self: Self) void {
            self.arena.deinit();
        }

        pub fn tempAllocator(self: *Self) Allocator {
            return self.arena.allocator();
        }

        pub fn addRow(
            self: *Self,
            row: [headers.len]Texture
        ) Allocator.Error!void {
            try self.rows.append(self.tempAllocator(), row);
        }

        pub fn display(
            self: *Self,
            writer: anytype
        ) (Allocator.Error || @TypeOf(writer).Error)!void {
            const DELIM_LEN = 2;
            const ally = self.tempAllocator();

            // find column character widths + the total height of the data
            var widths: [headers.len]usize = undefined;
            for (headers) |header, i| widths[i] = header.len;

            var height: usize = 0;
            for (self.rows.items) |row| {
                var row_height: usize = 0;
                for (row) |cell, i| {
                    widths[i] = std.math.max(widths[i], cell.size[0]);
                    row_height = std.math.max(row_height, cell.size[1]);
                }

                height += row_height;
            }

            // find total width
            var total_width: usize = 0;
            for (widths) |width| total_width += width;

            total_width += (headers.len - 1) * DELIM_LEN;

            // draw the column headers
            var header_tex = try Texture.init(ally, .{total_width, 2});
            defer header_tex.deinit(ally);

            var x: usize = 0;
            for (headers) |header, i| {
                header_tex.write(.{x, 0}, Format{ .fg = .cyan }, header);
                x += widths[i] + DELIM_LEN;
            }

            x = 0;
            while (x < total_width) : (x += 1) {
                header_tex.set(.{x, 1}, Format{}, '-');
            }

            try header_tex.display(writer);

            // draw the data
            var data_tex = try Texture.init(ally, .{total_width, height});
            defer data_tex.deinit(ally);

            var row_pos = Pos{0, 0};
            for (self.rows.items) |row| {
                var pos = row_pos;
                var max_height: usize = 0;
                for (row) |cell, i| {
                    if (i > 0) pos[0] += DELIM_LEN;

                    data_tex.blit(&cell, types.toOffset(pos));

                    pos[0] += widths[i];
                    max_height = std.math.max(max_height, cell.size[1]);
                }

                row_pos[1] += max_height;
            }

            try data_tex.display(writer);
        }
    };
}
