//! exports for kritzler lib, for ease of adding to build files

pub const Color = @import("src/color.zig");
pub const Canvas = @import("src/canvas.zig").Canvas;

pub const forms = @import("src/forms.zig");
pub const Table = forms.Table;
pub const List = forms.List;