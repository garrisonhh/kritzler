const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;
const kz = @import("kritzler.zig");

const Error = Allocator.Error || @TypeOf(stdout).Error;

const Examples = struct {
    pub fn hello(ally: Allocator) Error!void {
        var ctx = kz.Context.init(ally);
        defer ctx.deinit();

        const hello_tex = try ctx.print(.{ .fg = .yellow }, "hello", .{});
        const kz_tex = try ctx.print(.{ .fg = .red }, "{s}", .{"kritzler"});
        const tex = try ctx.slap(hello_tex, kz_tex, .right, .{ .space = 1 });

        try ctx.write(tex, stdout);
    }

    pub fn todo_list(ally: Allocator) Error!void {
        var ctx = kz.Context.init(ally);
        defer ctx.deinit();

        const items = [_][]const u8{
            "rewrite kritzler",
            "promote kritzler",
            "jump off a bridge after I find a bug in kritzler",
        };

        // create all of the bullet pointed items
        const bullet = try ctx.print(.{ .fg = .magenta }, "* ", .{});
        defer ctx.drop(bullet);

        var item_texs = std.ArrayList(kz.Ref).init(ctx.ally);
        defer item_texs.deinit();
        for (items) |item| {
            const item_tex = try ctx.print(.{ .special = .italic }, "{s}", .{item});
            // notice the clone. this is required because otherwise `bullet` would
            // be invalidated after the first slap.
            const row = try ctx.slap(try ctx.clone(bullet), item_tex, .right, .{});

            try item_texs.append(row);
        }

        // stack the items
        const all_items = try ctx.stack(item_texs.items, .bottom, .{});

        // add a title
        const title = try ctx.print(.{ .fg = .cyan }, "my todo list:", .{});
        const final_tex = try ctx.slap(all_items, title, .top, .{});

        try ctx.write(final_tex, stdout);
    }

    /// a realistic struct type
    const Vec2 = struct {
        const Self = @This();

        x: f64,
        y: f64,

        fn of(x: f64, y: f64) Self {
            return Self{ .x = x, .y = y };
        }

        /// Vec2 doesn't require any more context to render itself
        pub fn render(self: Self, ctx: *kz.Context, _: void) !kz.Ref {
            return try ctx.print(.{}, "({d:2.4}, {d:2.4})", .{self.x, self.y});
        }
    };

    pub fn simple_interface(ally: Allocator) Error!void {
        try kz.display(ally, {}, Vec2.of(1.4, -4.5), stdout);
    }

    const Monster = struct {
        const Tag = enum {
            goblin,
            spider,
            human,
        };

        tag: Tag,
        pos: Vec2,
    };

    /// a handle table for monsters
    const Monsters = struct {
        const Self = @This();

        data: std.ArrayListUnmanaged(Monster) = .{},

        fn deinit(self: *Self, ally: Allocator) void {
            self.data.deinit(ally);
        }

        fn add(self: *Self, ally: Allocator, monster: Monster) Allocator.Error!MonsterId {
            const id = MonsterId{ .index = self.data.items.len };
            try self.data.append(ally, monster);
            return id;
        }

        fn get(self: Self, id: MonsterId) Monster {
            return self.data.items[id.index];
        }
    };

    /// a handle into the monsters handle table
    const MonsterId = struct {
        index: usize,

        pub fn render(self: @This(), ctx: *kz.Context, table: Monsters) !kz.Ref {
            const m = table.get(self);
            const tag = try ctx.print(.{ .fg = .red }, "{s}", .{@tagName(m.tag)});
            const pos = try m.pos.render(ctx, {});
            return try ctx.slap(tag, pos, .right, .{ .space = 1 });
        }
    };

    pub fn complex_interface(ally: Allocator) Error!void {
        var prng = std.rand.DefaultPrng.init(0);
        const random = prng.random();

        var table = Monsters{};
        defer table.deinit(ally);

        // generate a bunch of monsters
        const N = 100;
        var ids: [N]MonsterId = undefined;

        var i: usize = 0;
        while (i < N) : (i += 1) {
            ids[i] = try table.add(ally, Monster{
                .tag = random.enumValue(Monster.Tag),
                .pos = Vec2.of(random.float(f64) * 10, random.float(f64) * 10)
            });
        }

        // display a few of my favorite monsters
        i = 0;
        while (i < 5) : (i += 1) {
            const fav = ids[random.intRangeLessThan(usize, 0, N)];

            // in english, this is something like "using the provided allocator
            // and table, display my favorite monster through stdout."
            try kz.display(ally, table, fav, stdout);
        }
    }
};

pub fn main() Error!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    // this just calls each function in examples
    inline for (@typeInfo(Examples).Struct.decls) |decl| {
        if (decl.is_pub) {
            try stdout.print("[{s}]\n", .{decl.name});
            try @field(Examples, decl.name)(ally);
            try stdout.writeByte('\n');
        }
    }
}
