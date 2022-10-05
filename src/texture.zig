//! the kritzler primitive. a 2d buffer for formatted text

const std = @import("std");
const types = @import("types.zig");
const Format = @import("format.zig").Format;

const Allocator = std.mem.Allocator;
const Pos = types.Pos;
const Offset = types.Offset;

const Self = @This();

const Cell = struct {
    fmt: Format,
    char: u8,

    fn of(fmt: Format, char: u8) Cell {
        return Cell{ .fmt = fmt, .char = char };
    }
};

buf: []Cell,
size: Pos,

pub fn init(ally: Allocator, size: types.Pos) Allocator.Error!Self {
    std.debug.assert(size[0] > 0 and size[1] > 0);

    const buf = try ally.alloc(Cell, size[0] * size[1]);
    std.mem.set(Cell, buf, Cell.of(Format.RESET, ' '));

    return Self{
        .buf = buf,
        .size = size,
    };
}

pub fn deinit(self: Self, ally: Allocator) void {
    ally.free(self.buf);
}

fn indexOf(self: Self, pos: Pos) usize {
    return pos[1] * self.size[0] + pos[0];
}

pub fn blit(self: *Self, tex: *const Self, to: Pos) void {
    const allowed_len = std.math.min(self.size[0] - to[0], tex.size[0]);

    var rows = tex.rowIterator();
    var i: usize = 0;
    while (rows.next()) |row| : (i += 1) {
        const pos = to + Pos{0, i};
        if (pos[1] >= self.size[1]) break;

        const start = self.indexOf(pos);
        const dest = self.buf[start..start + allowed_len];

        std.mem.copy(Cell, dest, row[0..allowed_len]);
    }
}

pub fn fill(self: *Self, fmt: Format, char: u8) void {
    std.mem.set(Cell, self.buf, Cell.of(fmt, char));
}

pub const RowIterator = struct {
    buf: []const Cell,
    width: usize,

    pub fn next(self: *RowIterator) ?[]const Cell {
        if (self.buf.len == 0) return null;

        defer self.buf = self.buf[self.width..];
        return self.buf[0..self.width];
    }
};

pub fn rowIterator(self: *const Self) RowIterator {
    return RowIterator{
        .buf = self.buf,
        .width = self.size[0],
    };
}

pub fn display(self: Self, writer: anytype) @TypeOf(writer).Error!void {
    var rows = self.rowIterator();
    var fmt = Format.RESET;
    while (rows.next()) |row| {
        try writer.print("{}", .{fmt});

        for (row) |cell| {
            if (!std.meta.eql(fmt, cell.fmt)) {
                fmt = cell.fmt;
                try writer.print("{}", .{fmt});
            }

            try writer.writeByte(cell.char);
        }

        try writer.print("{}\n", .{Format.RESET});
    }
}