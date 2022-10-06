//! the kritzler primitive. a 2d buffer for formatted text

const std = @import("std");
const types = @import("types.zig");
const Format = @import("format.zig").Format;

const Allocator = std.mem.Allocator;
const Pos = types.Pos;
const Offset = types.Offset;
const Rect = types.Rect;

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

pub fn from(
    ally: Allocator,
    fmt: Format,
    text: []const u8
) Allocator.Error!Self {
    // count text lines
    var num_lines: usize = 0;
    var max_len: usize = 0;

    var lines = std.mem.split(u8, text, "\n");
    while (lines.next()) |line| {
        num_lines += 1;
        max_len = std.math.max(max_len, line.len);
    }

    // allocate + write lines
    var tex = try Self.init(ally, Pos{max_len, num_lines});
    tex.fill(fmt, ' ');

    lines = std.mem.split(u8, text, "\n");
    var y: usize = 0;
    while (lines.next()) |line| : (y += 1) {
        for (line) |ch, x| {
            tex.buf[tex.indexOf(Pos{x, y})].char = ch;
        }
    }

    return tex;
}

pub fn deinit(self: Self, ally: Allocator) void {
    ally.free(self.buf);
}

pub fn clone(self: Self, ally: Allocator,) Allocator.Error!Self {
    return Self{
        .buf = try ally.dupe(Cell, self.buf),
        .size = self.size,
    };
}

fn indexOf(self: Self, pos: Pos) usize {
    return pos[1] * self.size[0] + pos[0];
}

/// draw a texture onto this one. in order to avoid allocations, any bits of
/// the old texture which go out of bounds are ignored.
pub fn blit(self: *Self, tex: *const Self, to: Offset) void {
    // find texture intersection
    const target = Rect{
        .offset = to,
        .size = tex.size
    };
    const isect = target.intersectionWith(Rect{
        .offset = .{0, 0},
        .size = self.size
    }) orelse {
        // no intersection found, no blitting required!
        return;
    };

    const pos = types.toPos(isect.offset) catch unreachable;
    const row_len = isect.size[0];

    // copy rows
    var rows = tex.rowIterator();
    var i: usize = 0;
    while (rows.next()) |row| : (i += 1) {
        if (pos[1] + i >= @intCast(usize, isect.offset[1]) + isect.size[1]) {
            break;
        }

        const start = self.indexOf(pos + Pos{0, i});
        const dest = self.buf[start..start + row_len];

        std.mem.copy(Cell, dest, row[0..row_len]);
    }
}

/// creates a new texture by drawing two textures on top of each other
pub fn unify(
    self: Self,
    ally: Allocator,
    tex: *const Self,
    to: Offset
) Allocator.Error!Self {
    // find size of new tex
    const target = Rect{
        .offset = to,
        .size = tex.size
    };
    const unified = target.unionWith(Rect{
        .offset = .{0, 0},
        .size = self.size
    });

    // blit two textures onto stacked tex
    var stacked = try Self.init(ally, unified.size);

    stacked.blit(&self, -unified.offset);
    stacked.blit(tex, to - unified.offset);

    return stacked;
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