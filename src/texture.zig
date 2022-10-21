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

/// use zig's std.fmt to print to a texture
pub fn print(
    ally: Allocator,
    fmt: Format,
    comptime fmt_str: []const u8,
    fmt_args: anytype
) std.fmt.AllocPrintError!Self {
    const text = try std.fmt.allocPrint(ally, fmt_str, fmt_args);
    defer ally.free(text);

    return try Self.from(ally, fmt, text);
}

pub fn deinit(self: Self, ally: Allocator) void {
    ally.free(self.buf);
}

pub fn clone(self: Self, ally: Allocator) Allocator.Error!Self {
    return Self{
        .buf = try ally.dupe(Cell, self.buf),
        .size = self.size,
    };
}

fn indexOf(self: Self, pos: Pos) usize {
    return pos[1] * self.size[0] + pos[0];
}

pub fn set(self: Self, pos: Pos, fmt: Format, char: u8) void {
    self.buf[self.indexOf(pos)] = Cell.of(fmt, char);
}

pub fn write(self: Self, pos: Pos, fmt: Format, text: []const u8) void {
    var cursor = pos;
    for (text) |ch| {
        if (ch == '\n') {
            cursor[1] += 1;
            cursor[0] = pos[0];
        } else {
            self.set(cursor, fmt, ch);
            cursor[0] += 1;
        }
    }
}

/// draw a texture onto this one. in order to avoid allocations, any bits of
/// the old texture which go out of bounds are ignored.
pub fn blit(self: Self, tex: Self, to: Offset) void {
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

    const pos = types.toPos(isect.offset);
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
    tex: Self,
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

    stacked.blit(self, -unified.offset);
    stacked.blit(tex, to - unified.offset);

    return stacked;
}

pub const SlapAlign = enum { close, center, far };
pub const SlapDirection = enum {
    left,
    right,
    top,
    bottom,

    fn flip(self: @This()) @This() {
        return switch (self) {
            .left => .right,
            .right => .left,
            .top => .bottom,
            .bottom => .top,
        };
    }
};

fn calcSlapPos(size: Pos, dir: SlapDirection, aln: SlapAlign) Pos {
    // find side vertices
    const a: Pos = switch (dir) {
        .left, .top => .{0, 0},
        .right => .{size[0], 0},
        .bottom => .{0, size[1]},
    };
    const b: Pos = switch (dir) {
        .left => .{0, size[1]},
        .top => .{size[0], 0},
        .right, .bottom => size,
    };

    // interpolate
    return a + switch (aln) {
        .close => Pos{0, 0},
        .center => (b - a) / Pos{2, 2},
        .far => b - a,
    };
}

/// "slap" a texture to a side of this one
pub fn slap(
    self: Self,
    ally: Allocator,
    tex: Self,
    dir: SlapDirection,
    aln: SlapAlign
) Allocator.Error!Self {
    const slap_pos = types.toOffset(calcSlapPos(self.size, dir, aln))
                   - types.toOffset(calcSlapPos(tex.size, dir.flip(), aln));

    return try self.unify(ally, tex, slap_pos);
}

/// slap a bunch of textures together
pub fn stack(
    ally: Allocator,
    textures: []const Self,
    dir: SlapDirection,
    aln: SlapAlign
) Allocator.Error!Self {
    return switch (textures.len) {
        0 => try Self.init(ally, .{0, 0}),
        1 => try textures[0].clone(ally),
        else => stack: {
            var stacked = try Self.init(ally, .{0, 0});
            for (textures) |tex| {
                const slapped = try stacked.slap(ally, tex, dir, aln);
                stacked.deinit(ally);
                stacked = slapped;
            }

            break :stack stacked;
        }
    };
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