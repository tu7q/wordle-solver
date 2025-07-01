//! Wordle Grid
//! Very scuffed user input stuff...

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Key = vaxis.Key;

const ziglet = @import("ziglet");

const WordleGrid = @This();

const Motif = @import("../AltSolver.zig").Motif;

formatter: ziglet.Formatter,

words: [ROWS][COLS]u8 = undefined,
motifs: [ROWS][COLS]Motif = undefined,
input: InputState = .{},
lock_input: bool = false,

userdata: ?*anyopaque = null,
onGuessEntered: *const fn (userdata: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void,

pub fn widget(self: *WordleGrid) vxfw.Widget {
    return .{
        .userdata = @ptrCast(@alignCast(self)),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *WordleGrid = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *WordleGrid, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    switch (event) {
        .init => {
            return;
        },
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true })) {
                ctx.quit = true;
                return;
            } else if (self.lock_input) {
                return;
            } else if (key.matches(Key.enter, .{}) and self.input.isCurrentPhaseFull()) {
                if (self.input.advancePhase() == .typing) { // If we have advanced to typing
                    if (std.mem.allEqual(Motif, &self.getLastGuess().?.@"1", .correct)) {
                        self.lock_input = true;
                    }
                    return self.onGuessEntered(self.userdata, ctx);
                }
            } else if (key.matches(Key.backspace, .{})) {
                self.input.deleteLast();
                return ctx.consumeAndRedraw();
            } else if (key.text) |text| {
                if (text.len != 1) return;

                switch (self.input.phase) {
                    .typing => {
                        if (std.ascii.isAlphabetic(text[0])) {
                            self.input.addLetter(&self.words, text[0]);
                            return ctx.consumeAndRedraw();
                        }
                    },
                    .colouring => {
                        const maybe_motif: ?Motif = switch (text[0]) {
                            '0' => .wrong,
                            '1' => .partial,
                            '2' => .correct,
                            else => null,
                        };
                        if (maybe_motif) |motif| {
                            self.input.addMotif(&self.motifs, motif);
                            return ctx.consumeAndRedraw();
                        }
                    },
                }
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *WordleGrid = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *WordleGrid, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const size = self.getSize();

    const containsWidth = if (ctx.max.width) |width| width >= size.width else true;
    const containsHeight = if (ctx.max.height) |height| height >= size.height else true;
    if (!containsWidth or !containsHeight) {
        return .empty(self.widget());
    }

    // Initialize the surface
    const surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

    // Draw the things
    for (0..ROWS) |row| {
        self.drawWordleRowBorder(surface, @intCast(row));

        if (row <= self.input.word_index) {
            var text = if (row < self.input.word_index) &self.words[row] else if (self.input.phase == .typing) self.words[row][0..self.input.cursor] else &self.words[row];
            text = try std.ascii.allocUpperString(ctx.arena, text);

            const motifs = if (row < self.input.word_index) &self.motifs[row] else if (self.input.phase == .colouring) self.motifs[row][0..self.input.cursor] else &.{};
            try self.drawText(surface, ctx.arena, @intCast(row), text, motifs);
        }
    }

    return surface;
}

/// Size of the entire widget
pub fn getSize(self: WordleGrid) vxfw.Size {
    var size = self.getRowSize();
    size.height *= ROWS;
    return size;
}

/// Size of a row
pub fn getRowSize(self: WordleGrid) vxfw.Size {
    const letter_size = self.getLetterSize();
    return .{
        .width = COLS * (letter_size.width + 1) + 1,
        .height = 2 + letter_size.height,
    };
}

/// Size of space for each letter
pub fn getLetterSize(self: WordleGrid) vxfw.Size {
    // These intCasts are safe since any width/height bigger than usize would be ridiculous.
    const width: u16 = @intCast(self.formatter.headers.max_length);
    const height: u16 = @intCast(self.formatter.headers.height);
    return .{
        .width = width,
        .height = height,
    };
}

fn drawWordleRowBorder(self: *WordleGrid, surface: vxfw.Surface, word_row: u16) void {
    const letter_size = self.getLetterSize();
    const row_size = self.getRowSize();

    const right_edge = row_size.width -| 1;
    const top_edge = row_size.height * word_row;
    const btm_edge = row_size.height * (word_row + 1) -| 1;

    // Corners
    surface.writeCell(0, top_edge, .{ .char = .{ .grapheme = "╭" } });
    surface.writeCell(0, btm_edge, .{ .char = .{ .grapheme = "╰" } });
    surface.writeCell(right_edge, top_edge, .{ .char = .{ .grapheme = "╮" } });
    surface.writeCell(right_edge, btm_edge, .{ .char = .{ .grapheme = "╯" } });

    var col: u16 = 1;
    while (col < right_edge) : (col += 1) {
        // This module is probably wrong.
        const is_intersection = col % (letter_size.width + 1) == 0;

        const top_grapheme = if (is_intersection) "┬" else "─";
        const btm_grapheme = if (is_intersection) "┴" else "─";

        surface.writeCell(col, top_edge, .{ .char = .{ .grapheme = top_grapheme } });
        surface.writeCell(col, btm_edge, .{ .char = .{ .grapheme = btm_grapheme } });

        if (is_intersection) {
            var row: u16 = top_edge + 1;
            while (row < btm_edge) : (row += 1) {
                surface.writeCell(col, row, .{ .char = .{ .grapheme = "│" } });
            }
        }
    }

    // All the intersection '│' are in. But the left and right most aren't.
    var row: u16 = top_edge + 1;
    while (row < btm_edge) : (row += 1) {
        surface.writeCell(0, row, .{ .char = .{ .grapheme = "│" } });
        surface.writeCell(right_edge, row, .{ .char = .{ .grapheme = "│" } });
    }
}

// NOTE: Still spaghetti but its working
fn drawText(self: WordleGrid, surface: vxfw.Surface, arena: Allocator, word_row: u16, text: []const u8, motifs: []const Motif) Allocator.Error!void {
    assert(text.len <= COLS);

    const row_size = self.getRowSize();
    const letter_size = self.getLetterSize();

    for (text, 0..) |letter, letter_index| {
        const left_edge = 1 + letter_index * (letter_size.width + 1);
        const top_edge = row_size.height * word_row + 1;

        const lines = self.formatter.formatTextAsLines(arena, &[_]u8{letter}, .{}) catch |err| switch (err) {
            error.InvalidUtf8 => @panic("tried to draw invalid utf8 character"),
            else => |e| return e,
        };

        const max_width = blk: {
            var width: usize = 0;
            for (lines) |line| {
                width = @max(width, line.len);
            }
            break :blk width;
        };

        const padding = (letter_size.width - max_width + 1) / 2;

        for (lines, 0..) |line, line_row| {
            for (0..line.len) |line_col| {
                const grapheme: []const u8 = line[line_col..][0..1];

                const col = left_edge + line_col + padding;
                const row = top_edge + line_row;

                surface.writeCell(
                    @intCast(col),
                    @intCast(row),
                    .{ .char = .{ .grapheme = grapheme } },
                );
            }
        }
    }

    for (motifs, 0..) |motif, motif_index| {
        const left_edge = 1 + motif_index * (letter_size.width + 1);
        const top_edge = row_size.height * word_row + 1;

        for (0..letter_size.width) |col| {
            for (0..letter_size.height) |row| {
                var cell = surface.readCell(left_edge + col, top_edge + row);
                cell.style.fg = switch (motif) {
                    .correct => vaxis.Color.rgbFromUint(0x00FF00),
                    .partial => vaxis.Color.rgbFromUint(0xFF4500),
                    .wrong => vaxis.Color.rgbFromUint(0x696969),
                };
                surface.writeCell(@intCast(left_edge + col), @intCast(top_edge + row), cell);
            }
        }
    }
}

pub fn getLastGuess(self: *WordleGrid) ?struct { [COLS]u8, [COLS]Motif } {
    return self.input.getLastGuess(self.words, self.motifs);
}

const COLS = 5;
const ROWS = 6;

const InputState = struct {
    const Phase = enum {
        typing,
        colouring,
    };

    word_index: usize = 0,
    cursor: usize = 0,
    phase: Phase = .typing,

    /// Get the last entered guess.
    pub fn getLastGuess(self: *InputState, words: [ROWS][COLS]u8, motifs: [ROWS][COLS]Motif) ?struct { [COLS]u8, [COLS]Motif } {
        if (self.word_index == 0) return null;
        const last_guess_index = self.word_index - 1;
        return .{ words[last_guess_index], motifs[last_guess_index] };
    }

    pub fn deleteLast(self: *InputState) void {
        if (self.cursor == 0) return;

        self.cursor -= 1;
    }

    /// Attempts to add the motif to current state, silently fails if impossible
    pub fn addMotif(self: *InputState, motifs: *[ROWS][COLS]Motif, motif: Motif) void {
        if (self.word_index >= ROWS) return;
        if (self.cursor >= COLS) return;

        motifs.*[self.word_index][self.cursor] = motif;
        self.cursor += 1;
    }

    /// Attempts to add the letter to current state, silently fails if impossible
    pub fn addLetter(self: *InputState, words: *[ROWS][COLS]u8, letter: u8) void {
        assert(std.ascii.isAlphabetic(letter));

        if (self.word_index >= ROWS) return;
        if (self.cursor >= COLS) return;

        const lower_letter = std.ascii.toLower(letter);

        words.*[self.word_index][self.cursor] = lower_letter;
        self.cursor += 1;
    }

    pub fn isCurrentPhaseFull(self: InputState) bool {
        return self.cursor == COLS;
    }

    /// Advances the phase and returns the new phase
    pub fn advancePhase(self: *InputState) Phase {
        assert(self.cursor == COLS);

        self.cursor = 0;
        self.phase = switch (self.phase) {
            .typing => .colouring,
            .colouring => blk: {
                self.word_index += 1;
                break :blk .typing;
            },
        };

        return self.phase;
    }
};
