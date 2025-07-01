//! Model for the application

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Key = vaxis.Key;

// const Solver = @import("Solver.zig");
const Solver = @import("AltSolver.zig");
const Pattern = Solver.Pattern;

const WordleGrid = @import("./widgets/WordleGrid.zig");
const Model = @This();

// LAYOUT MOCKUP

//  #Possible                                                         Possible  Top Picks E[Info]
//            ╭────────┬────────┬────────┬────────┬────────╮            abbas     ramin     4.55
//            │  ____  │  _     │  ____  │  ___   │  ____  │            abyss     marid     4.46
// 12,972 Pos │  [__   │  |     │  |__|  │   |    │  |___  │ 4.49 Bits            minar     4.42
//            │  ___]  │  |___  │  |  |  │   |    │  |___  │                      rains     4.39
//            ╰────────┴────────┴────────┴────────┴────────╯                      parki     4.41
//            ╭────────┬────────┬────────┬────────┬────────╮                      ranid     4.40
//            │  ____  │  ____  │   _    │  _  _  │  ____  │                      naris     4.37
//    578 Pos │  |__/  │  |__|  │   |    │  |\ |  │  [__   │ 3.39 Bits            minor     4.39
//            │  |  \  │  |  |  │   |    │  | \|  │  ___]  │                      ranis     4.37
//            ╰────────┴────────┴────────┴────────┴────────╯                      mirks     4.39
//            ╭────────┬────────┬────────┬────────┬────────╮                      naric     4.37
//            │  _  _  │  ____  │  _  _  │  ___   │  _  _  │                      porin     4.37
//     55 Pos │  |_/   │  |  |  │  |\/|  │  |__]  │  |  |  │ 4.78 Bits            ramis     3.34
//            │  | \_  │  |__|  │  |  |  │  |__]  │  |__|  │
//            ╰────────┴────────┴────────┴────────┴────────╯
//            ╭────────┬────────┬────────┬────────┬────────╮
//            │  ____  │  ___   │  ___   │  ____  │  ____  │
//      2 Pos │  |__|  │  |__]  │  |__]  │  |__|  │  [__   │ 1.00 Bits
//            │  |  |  │  |__]  │  |__]  │  |  |  │  ___]  │
//            ╰────────┴────────┴────────┴────────┴────────╯
//            ╭────────┬────────┬────────┬────────┬────────╮
//            │        │        │        │        │        │
//      1 Pos │        │        │        │        │        │
//            │        │        │        │        │        │
//            ╰────────┴────────┴────────┴────────┴────────╯
//            ╭────────┬────────┬────────┬────────┬────────╮
//            │        │        │        │        │        │
//            │        │        │        │        │        │
//            │        │        │        │        │        │
//            ╰────────┴────────┴────────┴────────┴────────╯

allocator: Allocator,
grid: WordleGrid,
solver: Solver,
scroll_bars: vxfw.ScrollBars = .{ .scroll_view = .{ .children = .{
    .builder = .{
        .buildFn = widgetBuilder,
        .userdata = undefined,
    },
} } },
top_picks: std.ArrayListUnmanaged(vxfw.Text) = .empty,

pub fn widget(self: *Model) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *Model = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *Model, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    switch (event) {
        .init => {
            self.scroll_bars.scroll_view.children.builder.userdata = @alignCast(@ptrCast(self));

            // Userdata is the model
            self.grid.userdata = @ptrCast(@alignCast(self));
            // Let the wordle grid have focus (handle events)
            try ctx.requestFocus(self.grid.widget());

            // Initial solver results.
            try self.solver.sortByEntropy(self.allocator);

            self.top_picks.clearAndFree(self.allocator);
            for (self.solver.words.items) |text| {
                try self.top_picks.append(self.allocator, .{
                    .text = text,
                });
            }

            if (self.solver.words.items.len > 0) {
                std.log.info("best word is: '{s}'", .{self.solver.words.items[0]});
            }
        },
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true })) {
                ctx.quit = true;
                return ctx.consumeEvent();
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *Model, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const split_view = try ctx.arena.create(vxfw.SplitView);
    split_view.* = .{
        .lhs = self.grid.widget(),
        .rhs = self.scroll_bars.widget(),
        .width = 15,
        .constrain = .rhs,
    };

    const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
    children[0] = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = try split_view.widget().draw(ctx),
    };

    const surface: vxfw.Surface = .{
        .size = ctx.max.size(),
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };

    return surface;
}

pub fn typeErasedOnGuessEntered(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    if (maybe_ptr) |ptr| {
        const self: *Model = @ptrCast(@alignCast(ptr));
        return self.onGuessEntered(ctx);
    }
}

pub fn onGuessEntered(self: *Model, ctx: *vxfw.EventContext) anyerror!void {
    {
        const word, const motifs = self.grid.getLastGuess() orelse return;
        const pattern = Pattern.fromMotifs(motifs);

        if (std.mem.allEqual(@typeInfo(@TypeOf(motifs)).array.child, &motifs, .correct)) {
            std.log.info("Found solution!", .{});

            return ctx.requestFocus(self.widget()); // remove WordleGrid focus.
        }

        // Okay solver optimization time...
        self.solver.submitPattern(&word, pattern);
    }

    // Probably good enough
    // TODO: Avoid using hidden page_allocator
    try self.solver.sortByEntropy(std.heap.page_allocator);

    self.top_picks.clearAndFree(self.allocator);
    for (self.solver.words.items) |text| {
        try self.top_picks.append(self.allocator, .{
            .text = text,
        });
    }

    if (self.solver.words.items.len > 0) {
        std.log.info("best word is: '{s}'", .{self.solver.words.items[0]});
    }

    return ctx.consumeAndRedraw();
}

fn widgetBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
    const self: *const Model = @ptrCast(@alignCast(ptr));
    if (idx >= self.top_picks.items.len) return null;

    return self.top_picks.items[idx].widget();
}
