const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Solver = @This();

// TODO
// const log = std.log.scoped(.solver);

/// Should not be modified during usage.
/// Will not be free'd when Solver is deinitialized.
words: []const []const u8,

/// Allocator for word result matrix and possible words.
allocator: Allocator,

/// Map corresponding to mat.
/// map[guess_index * word_len + actual_index]
// Since ArrayHashMap maintains insertion order (provided no deletions using indices would still be preservedd)
map: []Pattern, // Change this to a hashmap?
// Is it worth computing this map? going to be about ~1G for 14k elems
// Each pattern shouldn't need long to compute...

// map: std.StringArrayHashMapUnmanaged(Pattern),

/// indicess corresponding to possible words.
possible: std.ArrayListUnmanaged(usize),
// Linearly scanning through list of bool might be *faster?
// But this is find and will line up with the entropy list

// /// corresponds to the entropy of a possible word/guess
// entropy: std.ArrayListUnmanaged(usize),

pub fn init(allocator: Allocator, words: []const []const u8) Allocator.Error!Solver {
    for (words) |w| {
        assert(w.len == WORD_LEN);
    }

    var possible = try std.ArrayListUnmanaged(usize).initCapacity(allocator, words.len);
    errdefer possible.deinit(allocator);
    for (0..words.len) |i| {
        possible.appendAssumeCapacity(i);
    }

    const map = try allocator.alloc(Pattern, words.len * words.len);
    errdefer allocator.free(map);

    for (0..words.len) |i| {
        for (0..words.len) |j| {
            map[i * words.len + j] = getPattern(words[i], words[j]);
        }
    }

    return .{
        .allocator = allocator,
        .words = words,
        .map = map,
        .possible = possible,
    };
}

pub fn deinit(self: *Solver) void {
    self.allocator.free(self.map);
    self.possible.deinit(self.allocator);

    self.* = undefined;
}

/// Sort the possible words by the amount of information they will give
/// Temporary allocator required to compute (and temporarily store) the entropy for each possible word.
pub fn sortPossibleByEntropy(self: Solver, allocator: Allocator) !void {
    const len = self.possible.items.len;

    const entropies = try allocator.alloc(f64, len);
    defer allocator.free(entropies);

    for (self.possible.items, 0..) |w, i| {
        entropies[i] = try self.entropyOfGuess(allocator, w);
    }

    const Context = struct {
        items: []usize,
        entropies: []f64,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.entropies[a] > ctx.entropies[b];
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(usize, &ctx.items[a], &ctx.items[b]);
            std.mem.swap(f64, &ctx.entropies[a], &ctx.entropies[b]);
        }
    };

    const ctx: Context = .{
        .items = self.possible.items,
        .entropies = entropies,
    };

    // std.mem.sortContext(0, len, ctx);
    std.mem.sortUnstableContext(0, len, ctx);
}

/// For a given guess compute the expected entropy of the guess.
fn entropyOfGuess(self: Solver, allocator: Allocator, guess: usize) Allocator.Error!f64 {
    // sum (p * log2 (1/p))
    // -sum(p * log2(p))

    var counter: std.AutoArrayHashMapUnmanaged(Pattern, usize) = .empty;
    defer counter.deinit(allocator);

    for (self.possible.items) |p| {
        const pattern = self.map[guess * self.words.len + p];

        const entry = try counter.getOrPutValue(allocator, pattern, 0);
        entry.value_ptr.* += 1;
    }

    var e: f64 = 0;
    for (counter.values()) |q| {
        const prob = @as(f64, @floatFromInt(q)) / @as(f64, @floatFromInt(self.possible.items.len));

        e -= prob * std.math.log2(prob);
    }
    return e;
}

/// Using guess as index of word. Use HashMap instead bcs of this?
pub fn submitPattern(self: Solver, guess: usize, pattern: Pattern) void {
    assert(guess.len == WORD_LEN);

    var j: usize = self.possible.items.len;
    while (j > 0) {
        j -= 1;

        const p = self.possible.items[j];
        if (!std.mem.eql(self.map[guess * self.words.len + p], pattern)) {
            _ = self.possible.swapRemove(j);
        }
    }
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
