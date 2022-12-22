# kritzler

kritzler is a small library for generating ANSI terminal output in two dimensions.

## how the fuck do I use your library

I'm going to assume for the sake of this documentation that you've imported
kritzler as `kz`, and have an `allocator` available.

```zig
// first, initialize a context. this acts as the memory manager for kritzler.
var ctx = kz.Context.init(allocator);
defer ctx.deinit(); // you usually want this too
```

with a context, you can create and manipulate text blocks in several different
ways:

```zig
// this is usually what you want. make a text chunk using the `std.fmt` api.
fn print(self: *Self, sty: Style, comptime fmt: []const u8, args: anytype) PrintError!Ref

// create a blank chunk.
fn blank(self: *Self, size: Pos) Allocator.Error!Ref

// create a 0x0 chunk.
fn stub(self: *Self) Allocator.Error!Ref
```

once you have a couple refs, there are a few simple ways to manipulate them. a
really important note here is that refs have move semantics, e.g. once you use
a ref it is 'dropped' and invalid.

```zig
// slap directions are .left, .right, .bottom, and .top.
// for the advanced options, see src/context.zig.

// slap some refs together. drops both refs.
fn slap(self: *Self, a: Ref, b: Ref, dir: SlapDirection, opt: SlapOpt) Allocator.Error!Ref

// slap more than 2 refs together. drops all refs.
fn stack(self: *Self, refs: []const Ref, dir: SlapDirection, opt: SlapOpt) Allocator.Error!Ref

// this places chunk b over chunk a at an offset, and drops both refs.
// `slap` is implemented in terms of unify.
// `ctx.getSize(ref)` is a useful function to have alongside unify.
fn unify(self: *Self, a: Ref, b: Ref, to: Offset) Allocator.Error!Ref
```

at this point, you may also want these functions:

```zig
fn clone(self: *Self, ref: Ref) Allocator.Error!Ref
fn drop(self: *Self, ref: Ref) void
```

finally, you can write a ref to a writer from the context struct:

```zig
const stdout = @import("std").io.getStdout().writer();

try ctx.write(ref, stdout);
```

*this isn't perfectly exhaustive, but it covers everyhing you need to start
effectively using kritzler. start with reading context.zig if you need more.*

## basic primitives

### `Ref`

`Ref` acts as a handle for rectangles of text.

### `Style`

`Style` has three fields, `fg`, `bg`, and `special`. this is an attempt to slim
down the mess that is ANSI console escape codes into a sensible format. see
`style.zig` for the list of options for each of these (it is pretty small).

### `Pos` and `Offset`

these are `usize` and `isize` 2d vectors, respectively.
