//! context manages memory for kritzler chunks, which allows kritzler users
//! to generally be able to treat chunks as primitives.
//!
//! the only weirdness that this creates is the possibility of use-after-free
//! bugs, since Refs follow move semantics. luckily, this is checkable at
//! runtime at least, and manual chunk cloning is pretty intuitive. kritzler
//! also encourages a pure style that will make these bugs rare.

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const style = @import("style.zig");
const Color = style.Color;
const Style = style.Style;
const types = @import("types.zig");
const Pos = types.Pos;
const Offset = types.Offset;
const Rect = types.Rect;

const Self = @This();

/// the kritzler primitive
pub const Chunk = struct {
    gen: u32,
    styles: []Style,
    text: []u8,
    size: Pos,

    fn deinit(self: @This(), ally: Allocator) void {
        ally.free(self.styles);
        ally.free(self.text);
    }
};

pub const Ref = packed struct(u64) { gen: u32, index: u32 };

ally: Allocator,
chunks: std.ArrayListUnmanaged(Chunk) = .{},
reusable: std.ArrayListUnmanaged(u32) = .{},

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
    };
}

pub fn deinit(self: *Self) void {
    for (self.chunks.items) |chunk| chunk.deinit(self.ally);
    self.chunks.deinit(self.ally);
    self.reusable.deinit(self.ally);
}

fn assertCurrent(self: *Self, ref: Ref) void {
    if (builtin.mode == .Debug) {
        if (self.chunks.items[ref.index].gen != ref.gen) {
            std.debug.panic(
                "mismatched chunk generation. remember to clone your chunks.",
                .{}
            );
        }
    }
}

/// remember that addChunk can invalidate this pointer
fn get(self: *Self, ref: Ref) *Chunk {
    self.assertCurrent(ref);
    return &self.chunks.items[ref.index];
}

/// frees up a chunk for reuse
fn drop(self: *Self, ref: Ref) void {
    self.get(ref).gen += 1;
    try self.reusable.append(ref.index);
}

/// creates a chunk, returns pointer for convenience
fn new(self: *Self, size: Pos) Allocator.Error!Ref {
    var index: u32 = undefined;
    var chunk: *Chunk = undefined;

    // get chunk + index
    if (self.reusable.items.len > 0) {
        // reuse old slot
        index = self.reusable.pop();
        chunk = &self.chunks.items[index];
        chunk.deinit(self.ally);
    } else {
        // create new slot
        index = @truncate(u32, self.chunks.items.len);
        chunk = try self.chunks.addOne(self.ally);
        chunk.gen = 0;
    }

    chunk.size = size;

    // allocate chunk memory
    const mem_size = size[0] * size[1];
    chunk.styles = try self.ally.alloc(Style, mem_size);
    chunk.text = try self.ally.alloc(u8, mem_size);

    return Ref{
        .gen = chunk.gen,
        .index = index,
    };
}

/// create a new, blank chunk of a certain size
pub fn blank(self: *Self, size: Pos) Allocator.Error!Ref {
    const res = try self.new(size);
    std.mem.set(Style, res.chunk.styles, .{});
    std.mem.set(u8, res.chunk.text, ' ');

    return res.ref;
}

/// create a chunk without a size (useful in some situations)
pub fn stub(self: *Self) Ref {
    return self.new(.{0, 0}) catch unreachable;
}

/// create a copy of another chunk
pub fn clone(self: *Self, ref: Ref) Allocator.Error!Ref {
    const old = self.get(ref).*;
    const new_ref = self.new(old.size);
    const chunk = self.get(new_ref);

    std.mem.copy(Style, chunk.styles, old.styles);
    std.mem.copy(u8, chunk.text, old.text);

    return new_ref;
}

pub const PrintError = Allocator.Error || std.fmt.AllocPrintError;

/// print to a new chunk
pub fn print(
    self: *Self,
    sty: Style,
    comptime fmt: []const u8,
    args: anytype
) PrintError!Ref {
    // get naive printed text
    const text = try std.fmt.allocPrint(self.ally, fmt, args);
    defer self.ally.free(text);

    // extract lines
    var lines = std.ArrayList([]const u8).init(self.ally);
    defer lines.deinit();

    var line_iter = std.mem.split(u8, text, "\n");
    while (line_iter.next()) |line| try lines.append(line);

    // remove trailing newlines
    if (lines.items.len > 0) {
        while (true) {
            const last = lines.items[lines.items.len - 1];
            if (last.len > 0) break;
            _ = lines.pop();
        }
    }

    // find size of chunk
    var size = Pos{ 0, lines.items.len };
    for (lines.items) |line| size[0] = @max(size[0], line.len);

    // write style + text to chunk, filling the gaps with spaces
    const ref = try self.new(size);
    const chunk = self.get(ref);

    std.mem.set(Style, chunk.styles, sty);

    var i: usize = 0;
    for (lines.items) |line| {
        const next = i + size[0];
        const dest = chunk.text[i..next];
        i = next;

        std.mem.copy(u8, dest, line);
        std.mem.set(u8, dest[line.len..], ' ');
    }

    return ref;
}

const WriteBuffer = struct {
    style: Style = .{},
    buf: [256]u8 = undefined,
    filled: usize = 0,

    fn putchar(
        self: *@This(),
        sty: Style,
        ch: u8,
        writer: anytype
    ) @TypeOf(writer).Error!void {
        std.debug.assert(ch != '\n');

        if (!sty.eql(self.style)) {
            if (self.filled > 0) try self.flush(writer);
            self.style = sty;
        }

        self.buf[self.filled] = ch;
        self.filled += 1;

        if (self.filled == self.buf.len) {
            try self.flush(writer);
        }
    }

    fn newline(self: *@This(), writer: anytype) @TypeOf(writer).Error!void {
        try writer.print(
            "{}{s}{}\n",
            .{ self.style, self.buf[0..self.filled], &Style{} }
        );

        self.style = .{};
        self.filled = 0;
    }

    fn flush(self: *@This(), writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("{}{s}", .{ self.style, self.buf[0..self.filled] });
        self.style = .{};
        self.filled = 0;
    }
};

/// write a chunk to a writer
pub fn write(
    self: *Self,
    ref: Ref,
    writer: anytype
) @TypeOf(writer).Error!void {
    const chunk = self.get(ref);

    var buf = WriteBuffer{};
    var y: usize = 0;
    while (y < chunk.size[1]) : (y += 1) {
        const start = y * chunk.size[0];
        const end = start + chunk.size[0];
        const line_styles = chunk.styles[start..end];
        const line = chunk.text[start..end];

        for (line) |ch, i| {
            try buf.putchar(line_styles[i], ch, writer);
        }

        try buf.newline(writer);
    }
}
