const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Solver = @import("AltSolver.zig");
const Allocator = std.mem.Allocator;

const ziglet = @import("ziglet");
const font_buffer: []const u8 = @embedFile("./data/cybermedium.flf");

const Model = @import("Model.zig");

const datetime = @import("datetime");

const log = std.log.scoped(.main);

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();

    const allocator = da.allocator();

    // When program started and exited.
    blk: {
        const now_str = nowStr(allocator) catch break :blk;
        defer allocator.free(now_str);
        defer log.info("Entered Main: {s}", .{now_str});
    }
    defer blk: {
        const now_str = nowStr(allocator) catch break :blk;
        defer allocator.free(now_str);
        defer log.info("Exited Main: {s}", .{now_str});
    }

    // heap allocated for some reason...
    const font = try allocator.create(ziglet.DefaultFont);
    defer allocator.destroy(font);

    font.* = try ziglet.DefaultFont.init(allocator, font_buffer);
    defer font.deinit(allocator);

    const words = try readWords(allocator, "words.txt");
    defer {
        for (words) |w| {
            allocator.free(w);
        }
        allocator.free(words);
    }

    var solver = try Solver.init(allocator, words);
    defer solver.deinit();

    var model = try allocator.create(Model);
    defer allocator.destroy(model);
    model.* = .{
        .allocator = allocator,
        .grid = .{
            .formatter = font.formatter(),
            .onGuessEntered = Model.typeErasedOnGuessEntered,
        },
        .solver = solver,
    };

    const app = try allocator.create(vxfw.App);
    defer allocator.destroy(app);

    app.* = try vxfw.App.init(allocator);
    defer app.deinit();

    try app.run(model.widget(), .{});
}

fn nowStr(allocator: Allocator) ![]const u8 {
    const now = datetime.datetime.Datetime.now();
    return try now.formatHttp(allocator);
}

fn readWords(allocator: Allocator, filename: []const u8) ![][]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var words = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (words.items) |w| {
            allocator.free(w);
        }
        words.deinit();
    }

    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', Solver.WORD_LEN + 3)) |line| {
        const trimmed_line = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (trimmed_line.len != Solver.WORD_LEN) {
            return error.InvalidWordLength;
        }

        try words.append(@constCast(trimmed_line));
    }

    return words.toOwnedSlice();
}

pub const std_options = std.Options{
    .logFn = logFn,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const allocator = std.heap.page_allocator;

    const exe_path = std.fs.selfExeDirPathAlloc(allocator) catch |err| {
        std.debug.print("Failed to get path to exe: {}\n", .{err});
        return;
    };
    defer allocator.free(exe_path);

    const sub_path = "./log.txt";

    const path = std.fs.path.join(allocator, &[2][]const u8{ exe_path, sub_path }) catch |err| {
        std.debug.print("Failed to join paths: {}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = std.fs.createFileAbsolute(path, .{ .truncate = false, .read = true }) catch |err| {
        std.debug.print("Failed to open log file path: {}\n", .{err});
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Failed to get stat of log file: {}\n", .{err});
        return;
    };
    file.seekTo(stat.size) catch |err| {
        std.debug.print("Failed to seek log file: {}\n", .{err});
        return;
    };

    const prefix = "[" ++ comptime level.asText() ++ "]" ++ "(" ++ @tagName(scope) ++ ") ";

    const message = std.fmt.allocPrint(allocator, prefix ++ format ++ "\n", args) catch |err| {
        std.debug.print("Failed to format log message: {}\n", .{err});
        return;
    };

    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {}\n", .{err});
        return;
    };
}
