const std = @import("std");

pub fn main() void {
    emain() catch |e| {
        std.debug.print("error: {}\n", .{e});
        std.os.exit(1);
    };
}

const Move = struct {
    const Direction = enum {
        up,
        right,
        down,
        left,
    };

    direction: Direction,
    magnitude: u32,

    fn fromLine(line: []const u8) !@This() {
        var line_parts = std.mem.split(u8, line, " ");

        const direction: Move.Direction = blk: {
            const ch = line_parts.next().?[0];
            switch (ch) {
                'U' => break :blk .up,
                'R' => break :blk .right,
                'D' => break :blk .down,
                'L' => break :blk .left,
                else => {
                    std.debug.print("{}\n", .{ch});
                    unreachable;
                },
            }
        };

        const magnitude = try std.fmt.parseInt(u32, std.mem.trimRight(u8, line_parts.next().?, "\n"), 10);

        return .{ .direction = direction, .magnitude = magnitude };
    }
};

fn emain() !void {
    const allocator: std.mem.Allocator = std.heap.page_allocator;
    const stdin = std.io.getStdIn();

    var debug = false;
    {
        var args = std.process.args();
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-d")) {
                debug = true;

                if (args.next()) |time_str| {
                    const sleep_time = try std.fmt.parseInt(u64, time_str, 10);
                    std.debug.print("waiting...\n", .{});
                    std.time.sleep(sleep_time * 1_000_000_000);
                }
            }
        }
    }

    var moves = std.ArrayList(Move).init(allocator);
    var stdin_rdr = stdin.reader();
    while (true) {
        const line = try stdin_rdr.readUntilDelimiterOrEofAlloc(allocator, '\n', 1000);
        if (line == null) {
            break;
        }

        const move = try Move.fromLine(line.?);
        try moves.append(move);
    }

    try one(allocator, moves.items, debug);
}

fn one(allocator: std.mem.Allocator, moves: []const Move, debug: bool) !void {
    var state = State(9).init();
    var tail_locations = std.AutoHashMap(Vec2, u32).init(allocator);

    if (debug) {
        std.debug.print("{}\n", .{state});
    }

    for (moves) |move| {
        if (debug) {
            std.debug.print("{}\n", .{move});
        }

        var i: u32 = 0;
        while (i < move.magnitude) : (i += 1) {
            try state.moveHead(move.direction);

            const tail = state.tail();
            if (tail_locations.get(tail)) |old_val| {
                try tail_locations.put(tail, old_val + 1);
            } else {
                try tail_locations.put(tail, 1);
            }

            if (debug) {
                std.debug.print("{}\n", .{state});
            }
        }
    }

    {
        const writer = std.io.getStdOut().writer();

        const keys = blk: {
            var iter = tail_locations.keyIterator();
            var keys = std.ArrayList(Vec2).init(allocator);
            while (iter.next()) |key| {
                try keys.append(key.*);
            }

            break :blk keys;
        };

        const tailLocationT = @TypeOf(tail_locations);
        const Printer = struct {
            tailLocations: tailLocationT,
            writer: @TypeOf(writer),

            pub fn printPoint(self: @This(), point: Vec2) !void {
                if (self.tailLocations.contains(point)) {
                    try self.writer.writeAll("# ");
                } else {
                    try self.writer.writeAll(". ");
                }
            }

            pub fn writeAll(self: @This(), bytes: []const u8) !void {
                try self.writer.writeAll(bytes);
            }
        };

        try printPoints(keys.items, Printer{
            .writer = writer,
            .tailLocations = tail_locations,
        });

        try std.fmt.format(writer, "{}\n", .{tail_locations.count()});
    }
}

const Vec2 = struct {
    x: i32,
    y: i32,

    fn distance(self: @This(), other: @This()) @This() {
        return .{ .x = other.x - self.x, .y = other.y - self.y };
    }

    fn abs(self: @This()) !@This() {
        return .{
            .x = try std.math.absInt(self.x),
            .y = try std.math.absInt(self.y),
        };
    }

    fn add(self: @This(), other: @This()) @This() {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    fn bounds(vecs: []const @This()) Bounds {
        var result: Bounds = .{
            .bottomLeft = .{ .x = 0, .y = 0 },
            .topRight = .{ .x = 0, .y = 0 },
        };

        for (vecs) |vec| {
            if (vec.x < result.bottomLeft.x) {
                result.bottomLeft.x = vec.x;
            }

            if (vec.y < result.bottomLeft.y) {
                result.bottomLeft.y = vec.y;
            }

            if (vec.x > result.topRight.x) {
                result.topRight.x = vec.x;
            }

            if (vec.y > result.topRight.y) {
                result.topRight.y = vec.y;
            }
        }

        return result;
    }
};

const Bounds =
    struct { bottomLeft: Vec2, topRight: Vec2 };

fn State(comptime numKnots: u32) type {
    return struct {
        start: Vec2 = .{ .x = 0, .y = 0 },
        head: Vec2 = .{ .x = 0, .y = 0 },
        knots: [numKnots]Vec2 = [_]Vec2{.{ .x = 0, .y = 0 }} ** numKnots,

        fn init() @This() {
            return .{};
        }

        fn moveHead(self: *@This(), direction: Move.Direction) !void {
            switch (direction) {
                .up => self.head.y += 1,
                .right => self.head.x += 1,
                .down => self.head.y -= 1,
                .left => self.head.x -= 1,
            }

            for (self.knots) |*knot, i| {
                const nextKnot = if (i == 0) self.head else self.knots[i - 1];
                try self.correctKnot(knot, nextKnot);
            }
        }

        fn correctKnot(self: *@This(), knot: *Vec2, nextKnot: Vec2) !void {
            const distance = knot.*.distance(nextKnot);
            const abs_distance = try distance.abs();

            // If the knot is touching the next knot, nothing to do.
            if (abs_distance.x <= 1 and abs_distance.y <= 1) {
                return;
            }

            const sign_x = std.math.sign(distance.x);
            const sign_y = std.math.sign(distance.y);

            // Check if we just need to move horizontally.
            if (abs_distance.x > 1 and abs_distance.y == 0) {
                knot.*.x += sign_x;
                return;
            }

            // Check if we just need to move vertically.
            if (abs_distance.x == 0 and abs_distance.y > 1) {
                knot.*.y += sign_y;
                return;
            }

            // Check if we need to move horizontally and vertically.
            {
                if (abs_distance.y > 1) {
                    knot.*.x = nextKnot.x;
                    knot.*.y = nextKnot.y - sign_y;
                    return;
                }

                if (abs_distance.x > 1) {
                    knot.*.x = nextKnot.x - sign_x;
                    knot.*.y = nextKnot.y;
                    return;
                }
            }

            std.debug.print("{}", .{self});
            unreachable;
        }

        fn tail(self: @This()) Vec2 {
            return self.knots[numKnots - 1];
        }

        pub fn format(
            self: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            const Printer = struct {
                start: Vec2,
                head: Vec2,
                knots: [numKnots]Vec2,
                writer: @TypeOf(writer),

                pub fn printPoint(printer: @This(), point: Vec2) !void {
                    if (std.meta.eql(point, printer.head)) {
                        try printer.writer.writeAll("H ");
                        return;
                    }

                    for (printer.knots) |knot, i| {
                        if (std.meta.eql(point, knot)) {
                            try printer.writer.print("{} ", .{i + 1});
                            return;
                        }
                    }

                    if (std.meta.eql(point, printer.start)) {
                        try printer.writer.writeAll("s ");
                        return;
                    }

                    try printer.writer.writeAll(". ");
                }

                pub fn writeAll(printer: @This(), bytes: []const u8) !void {
                    try printer.writer.writeAll(bytes);
                }
            };

            try printPoints(&[_]Vec2{ self.start, self.head } ++ &self.knots, Printer{
                .start = self.start,
                .head = self.head,
                .knots = self.knots,
                .writer = writer,
            });

            try writer.print("head: {}, knots: {any}, start: {}", .{ self.head, self.knots, self.start });
        }
    };
}

fn printPoints(points: []const Vec2, printer: anytype) !void {
    const SPACE = 5;

    var bounds = Vec2.bounds(points);
    bounds.topRight = bounds.topRight.add(.{ .x = SPACE, .y = SPACE });
    bounds.bottomLeft = bounds.bottomLeft.add(.{ .x = -SPACE, .y = -SPACE });

    var y = bounds.topRight.y;
    while (y >= bounds.bottomLeft.y) : (y -= 1) {
        var x = bounds.bottomLeft.x;
        while (x <= bounds.topRight.x) : (x += 1) {
            const point: Vec2 = .{ .x = x, .y = y };

            try printer.printPoint(point);
        }

        try printer.writeAll("\n");
    }
}
