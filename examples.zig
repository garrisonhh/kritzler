const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;
const kz = @import("kritzler.zig");

const Error = Allocator.Error || @TypeOf(stdout).Error;

const Examples = struct {
    fn hello(ctx: *kz.Context) Error!void {
        const hello_tex = try ctx.print(.{ .fg = .yellow }, "hello", .{});
        const kz_tex = try ctx.print(.{ .fg = .red }, "{s}", .{"kritzler"});
        const tex = try ctx.slap(hello_tex, kz_tex, .right, .{ .space = 1 });

        try ctx.write(tex, stdout);
    }

    fn todo_list(ctx: *kz.Context) Error!void {
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
};

pub fn main() Error!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var ctx = kz.Context.init(gpa.allocator());
    defer ctx.deinit();

    // this just calls each function in examples
    inline for (@typeInfo(Examples).Struct.decls) |decl| {
        try stdout.print("[{s}]\n", .{decl.name});
        try @field(Examples, decl.name)(&ctx);
        try stdout.writeByte('\n');

        std.debug.assert(ctx.numActiveRefs() == 0);
    }
}
