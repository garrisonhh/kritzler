const std = @import("std");
const Color = @import("color.zig");

const Allocator = std.mem.Allocator;

pub const Vec2 = @Vector(2, isize);
pub const Rect = @Vector(4, isize);

fn combine_rect(pos: Vec2, dims: Vec2) Rect {
    return Rect{pos[0], pos[1], dims[0], dims[1]};
}

/// given multiline text, returns its dimensions
fn detect_text_dims(text: []const u8) Vec2 {
    var longest: usize = 0;
    var lines: usize = 1;
    var current: usize = 0;
    for (text) |ch| {
        if (ch == '\n') {
            longest = std.math.max(longest, current);
            current = 0;
            lines += 1;
        }
        current += 1;
    }

    return Vec2{
        @intCast(isize, std.math.max(longest, current)),
        @intCast(i32, lines)
    };
}

const Box = struct {
    const Self = @This();

    rect: Rect,
    color: Color,
    text: []const u8,

    fn init(pos: Vec2, color: Color, text: []const u8) Self {
        return Self{
            .rect = combine_rect(pos, detect_text_dims(text)),
            .color = color,
            .text = text,
        };
    }
};

/// implements `Canvas.flush()` behavior
/// expects to be placed on an arena
const Buffer = struct {
    const Self = @This();

    bounds: Rect,
    text: []u8,
    colors: []Color,

    fn init(canvas: *Canvas) Allocator.Error!Self {
        const ally = canvas.arena.allocator();
        const bounds = canvas.find_box_bounds();

        const area = @intCast(usize, bounds[2] * bounds[3]);
        const text = try ally.alloc(u8, area);
        const colors = try ally.alloc(Color, area);

        std.mem.set(u8, text, ' ');
        std.mem.set(Color, colors, Color{});

        return Self{
            .bounds = bounds,
            .text = text,
            .colors = colors
        };
    }

    fn index_of(self: Self, pos: Vec2) usize {
        return @intCast(usize, self.bounds[2] * pos[1] + pos[0]);
    }

    fn set(self: Self, pos: Vec2, ch: u8, color: Color) void {
        const index = self.index_of(pos);
        self.text[index] = ch;
        self.colors[index] = color;
    }

    fn add(self: Self, box: Box) void {
        const offset = Vec2{box.rect[0], box.rect[1]}
                     - Vec2{self.bounds[0], self.bounds[1]};
        var pos = Vec2{0, 0};

        for (box.text) |ch| {
            if (ch == '\n') {
                pos[0] = 0;
                pos[1] += 1;
            } else {
                self.set(offset + pos, ch, box.color);
                pos[0] += 1;
            }
        }
    }

    fn flush(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        const width = @intCast(usize, self.bounds[2]);

        var last_color = Color{};
        var cur_color = Color{};

        for (self.text) |ch, i| {
            last_color = cur_color;
            cur_color = self.colors[i];

            if (!std.meta.eql(cur_color, last_color)) {
                try writer.print("{}", .{cur_color});
            }

            try writer.writeByte(ch);

            if ((i + 1) % width == 0) {
                cur_color = Color{};
                try writer.print("{}\n", .{cur_color});
            }
        }

        try writer.writeByte('\n');
    }
};

/// used to queue up messages (and other textboxes) for nice output
pub const Canvas = struct {
    const Self = @This();

    boxes: std.MultiArrayList(Box),
    ally: Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(ally: Allocator) Self {
        var arena = std.heap.ArenaAllocator.init(ally);

        return Self{
            .boxes = std.MultiArrayList(Box){},
            .ally = ally,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Self) void {
        self.boxes.deinit(self.ally);
        self.arena.deinit();
    }

    /// prints to canvas arena, for use in messages
    pub fn print(
        self: *Self,
        comptime fmt: []const u8,
        args: anytype,
    ) std.fmt.AllocPrintError![]const u8 {
        return try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
    }

    /// adds a box!
    pub fn scribble(
        self: *Self,
        pos: Vec2,
        color: Color,
        comptime fmt: []const u8,
        args: anytype,
    ) (std.fmt.AllocPrintError || Allocator.Error)!void {
        // ensure Color is being used properly
        comptime {
            const fields = std.meta.fields(@TypeOf(args));
            for (fields) |field| {
                const t = field.field_type;
                if (t == Color) {
                    return error.AttemptedToScribbleColors;
                }
            }
        }

        const msg = try self.print(fmt, args);
        try self.boxes.append(self.ally, Box.init(pos, color, msg));
    }

    /// find bounds of all queued boxes
    fn find_box_bounds(self: Self) Rect {
        const rects = self.boxes.items(.rect);
        var bounds = rects[0];

        for (rects[1..]) |rect| {
            if (rect[0] < bounds[0]) {
                bounds[2] += bounds[0] - rect[0];
                bounds[0] = rect[0];
            }
            if (rect[1] < bounds[1]) {
                bounds[3] += bounds[1] - rect[1];
                bounds[1] = rect[1];
            }

            const rect_maxx = rect[0] + rect[2];
            const bounds_maxx = bounds[0] + bounds[2];
            if (rect_maxx > bounds_maxx) {
                bounds[2] += rect_maxx - bounds_maxx;
            }

            const rect_maxy = rect[1] + rect[3];
            const bounds_maxy = bounds[1] + bounds[3];
            if (rect_maxy > bounds_maxy) {
                bounds[3] += rect_maxy - bounds_maxy;
            }
        }

        return bounds;
    }

    /// print and consume boxes
    pub fn flush(
        self: *Self,
        writer: anytype
    ) (@TypeOf(writer).Error || Allocator.Error)!void {
        // create and flush buffer
        const buf = try Buffer.init(self);

        var i: usize = 0;
        while (i < self.boxes.len) : (i += 1) buf.add(self.boxes.get(i));

        try buf.flush(writer);

        // free memory
        try self.boxes.resize(self.ally, 0);

        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.ally);
    }
};
