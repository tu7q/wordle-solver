const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const AltSolver = @This();

allocator: Allocator,
words: std.ArrayListUnmanaged([]const u8),

pub fn init(allocator: std.mem.Allocator, words: []const []const u8) Allocator.Error!AltSolver {
    for (words) |word| {
        assert(word.len == WORD_LEN);
    }

    var word_list = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, words.len);
    word_list.appendSliceAssumeCapacity(words);

    return .{
        .allocator = allocator,
        .words = word_list,
    };
}

pub fn sortByEntropy(self: AltSolver, allocator: Allocator) Allocator.Error!void {
    const entropy = try allocator.alloc(f32, self.words.items.len);
    defer allocator.free(entropy);

    var counter = std.AutoArrayHashMap(Pattern, u32).init(allocator);
    defer counter.deinit();

    for (0..self.words.items.len) |i| {
        defer counter.clearRetainingCapacity();

        entropy[i] = try self.entropyOfGuess(&counter, i);
    }

    const Context = struct {
        items: [][]const u8,
        entropy: []f32,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.entropy[a] > ctx.entropy[b];
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap([]const u8, &ctx.items[a], &ctx.items[b]);
            std.mem.swap(f32, &ctx.entropy[a], &ctx.entropy[b]);
        }
    };

    const ctx: Context = .{
        .items = self.words.items,
        .entropy = entropy,
    };

    std.mem.sortUnstableContext(0, self.words.items.len, ctx);
}

fn entropyOfGuess(self: AltSolver, counter: *std.AutoArrayHashMap(Pattern, u32), guess: usize) Allocator.Error!f32 {
    const guessed_word = self.words.items[guess];

    for (self.words.items) |word| {
        const result = try counter.getOrPutValue(getPattern(guessed_word, word), 0);
        result.value_ptr.* += 1;
    }

    var entropy: f32 = 0;
    for (counter.values()) |q| {
        const probability: f32 = @as(f32, @floatFromInt(q)) / @as(f32, @floatFromInt(self.words.items.len));
        entropy -= probability * std.math.log2(probability);
    }
    return entropy;
}

pub fn submitPattern(self: *AltSolver, guess: []const u8, pattern: Pattern) void {
    assert(guess.len == WORD_LEN);

    var i: usize = self.words.items.len;
    while (i > 0) {
        i -= 1;

        const word = self.words.items[i];
        if (!std.meta.eql(getPattern(guess, word), pattern)) {
            _ = self.words.swapRemove(i);
        }
    }
}

pub fn deinit(self: *AltSolver) void {
    // No need to free the individual words since they aren't owned by the solver
    self.words.deinit(self.allocator);

    self.* = undefined;
}

pub const WORD_LEN = 5;
pub const Motif = enum {
    /// Letter exists in the word at that spot
    correct,
    /// Letter exists in the word but not in this spot
    partial,
    /// Letter is not in the word
    wrong,
};

pub const Pattern = struct {
    // This is 2 bytes. Compared to [WORD_LEN]Motif
    correct: std.bit_set.IntegerBitSet(WORD_LEN),
    not_wrong: std.bit_set.IntegerBitSet(WORD_LEN),

    pub const all_wrong: Pattern = .{
        .correct = .initEmpty(),
        .not_wrong = .initEmpty(),
    };

    pub fn fromMotifs(motifs: [WORD_LEN]Motif) Pattern {
        var pattern = all_wrong;
        for (motifs, 0..) |motif, i| {
            pattern.set(i, motif);
        }
        return pattern;
    }

    pub fn get(self: Pattern, index: usize) Motif {
        assert(index < WORD_LEN);

        if (!self.not_wrong.isSet(index)) {
            return .wrong;
        }

        return switch (self.correct.isSet(index)) {
            true => .correct,
            false => .partial,
        };
    }

    pub fn set(self: *Pattern, index: usize, motif: Motif) void {
        assert(index < WORD_LEN);

        switch (motif) {
            .correct => {
                self.not_wrong.set(index);
                self.correct.set(index);
            },
            .partial => {
                self.not_wrong.set(index);
                self.correct.unset(index);
            },
            .wrong => {
                self.not_wrong.unset(index);
                self.correct.unset(index);
            },
        }
    }
};

fn getPattern(guess: []const u8, actual: []const u8) Pattern {
    assert(guess.len == WORD_LEN);
    assert(actual.len == WORD_LEN);

    var result: Pattern = .all_wrong;

    var skip = [_]bool{false} ** WORD_LEN;
    var seen = [_]bool{false} ** WORD_LEN;

    for (0..WORD_LEN) |i| {
        if (guess[i] == actual[i]) {
            result.set(i, .correct);
            seen[i] = true;
            skip[i] = true;
        }
    }

    for (0..WORD_LEN) |i| {
        if (skip[i]) continue;
        for (0..WORD_LEN) |j| {
            if (seen[j]) continue;
            if (guess[i] == actual[j]) {
                result.set(i, .partial);
                seen[j] = true;
                break;
            }
        }
    }

    return result;
}
