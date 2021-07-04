const std = @import("std");
const mecha = @import("mecha");
const mem = std.mem;
usingnamespace @import("mecha");
usingnamespace std.testing;

pub const Semver = struct {
    major: u64,
    minor: u64,
    patch: u64,

    const semver = combine(.{
        int(u64, 10),
        utf8.char('.'),
        int(u64, 10),
        utf8.char('.'),
        int(u64, 10),
    });

    const parser = map(Semver, toStruct(Semver), semver);

    const single_parser = map(
        Semver,
        toStruct(Semver),
        combine(.{
            semver,
            eos,
        }),
    );

    pub fn parse(str: []const u8) !Semver {
        return (single_parser(str) orelse return error.InvalidString).value;
    }

    pub fn format(
        self: Semver,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;
        try writer.print("{}.{}.{}", .{
            self.major,
            self.minor,
            self.patch,
        });
    }

    pub fn cmp(self: Semver, other: Semver) std.math.Order {
        return if (self.major != other.major)
            std.math.order(self.major, other.major)
        else if (self.minor != other.minor)
            std.math.order(self.minor, other.minor)
        else
            std.math.order(self.patch, other.patch);
    }

    pub fn inside(self: Semver, range: Range) bool {
        return self.cmp(range.min).compare(.gte) and self.cmp(range.lessThan()).compare(.lt);
    }
};

test "empty string" {
    expectError(error.InvalidString, Semver.parse(""));
}

test "bad strings" {
    expectError(error.InvalidString, Semver.parse("1"));
    expectError(error.InvalidString, Semver.parse("1."));
    expectError(error.InvalidString, Semver.parse("1.2"));
    expectError(error.InvalidString, Semver.parse("1.2."));
    expectError(error.InvalidString, Semver.parse("1.-2.3"));
    expectError(error.InvalidString, Semver.parse("^1.2.3-3.4.5"));
}

test "semver-suffix" {
    expectError(error.InvalidString, Semver.parse("1.2.3-dev"));
}

test "regular semver" {
    const expected = Semver{ .major = 1, .minor = 2, .patch = 3 };
    expectEqual(expected, try Semver.parse("1.2.3"));
}

test "semver formatting" {
    var buf: [80]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const semver = Semver{ .major = 4, .minor = 2, .patch = 1 };
    try stream.writer().print("{}", .{semver});

    expectEqualStrings("4.2.1", stream.getWritten());
}

test "semver contains/inside range" {
    const range_pre = try Range.parse("^0.4.1");
    const range_post = try Range.parse("^1.4.1");

    expect(!range_pre.contains(try Semver.parse("0.2.0")));
    expect(!range_pre.contains(try Semver.parse("0.4.0")));
    expect(!range_pre.contains(try Semver.parse("0.5.0")));
    expect(range_pre.contains(try Semver.parse("0.4.2")));
    expect(range_pre.contains(try Semver.parse("0.4.128")));

    expect(!range_post.contains(try Semver.parse("1.2.0")));
    expect(!range_post.contains(try Semver.parse("1.4.0")));
    expect(!range_post.contains(try Semver.parse("2.0.0")));
    expect(range_post.contains(try Semver.parse("1.5.0")));
    expect(range_post.contains(try Semver.parse("1.4.2")));
    expect(range_post.contains(try Semver.parse("1.4.128")));
}

pub const Range = struct {
    min: Semver,
    kind: Kind,

    pub const Kind = enum {
        approx,
        caret,
        exact,
    };

    const parser = map(
        Range,
        toRange,
        combine(.{
            opt(
                oneOf(.{
                    utf8.range('~', '~'),
                    utf8.range('^', '^'),
                }),
            ),
            Semver.semver,
        }),
    );

    fn toRange(tuple: anytype) Range {
        const kind: Kind = if (tuple[0]) |char|
            if (char == '~') Kind.approx else if (char == '^') Kind.caret else unreachable
        else
            Kind.exact;

        return Range{
            .kind = kind,
            .min = Semver{
                .major = tuple[1][0],
                .minor = tuple[1][1],
                .patch = tuple[1][2],
            },
        };
    }

    fn lessThan(self: Range) Semver {
        return switch (self.kind) {
            .exact => Semver{
                .major = self.min.major,
                .minor = self.min.minor,
                .patch = self.min.patch + 1,
            },
            .approx => Semver{
                .major = self.min.major,
                .minor = self.min.minor + 1,
                .patch = 0,
            },
            .caret => if (self.min.major == 0) Semver{
                .major = self.min.major,
                .minor = self.min.minor + 1,
                .patch = 0,
            } else Semver{
                .major = self.min.major + 1,
                .minor = 0,
                .patch = 0,
            },
        };
    }

    pub fn parse(str: []const u8) !Range {
        return (parser(str) orelse return error.InvalidString).value;
    }

    pub fn format(
        self: Range,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;
        switch (self.kind) {
            .exact => try writer.print("{}", .{self.min}),
            .approx => try writer.print("~{}", .{self.min}),
            .caret => try writer.print("^{}", .{self.min}),
        }
    }

    pub fn contains(self: Range, semver: Semver) bool {
        return semver.inside(self);
    }
};

test "empty string" {
    expectError(error.InvalidString, Range.parse(""));
}

test "approximate" {
    const expected = Range{
        .kind = .approx,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    expectEqual(expected, try Range.parse("~1.2.3"));
}

test "caret" {
    const expected = Range{
        .kind = .caret,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    expectEqual(expected, try Range.parse("^1.2.3"));
}

test "exact range" {
    const expected = Range{
        .kind = .exact,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    expectEqual(expected, try Range.parse("1.2.3"));
}

test "range formatting: exact" {
    var buf: [80]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const range = Range{
        .kind = .exact,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    try stream.writer().print("{}", .{range});

    expectEqualStrings("1.2.3", stream.getWritten());
}

test "range formatting: approx" {
    var buf: [80]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const range = Range{
        .kind = .approx,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    try stream.writer().print("{}", .{range});

    expectEqualStrings("~1.2.3", stream.getWritten());
}

test "range formatting: caret" {
    var buf: [80]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const range = Range{
        .kind = .caret,
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
    };
    try stream.writer().print("{}", .{range});

    expectEqualStrings("^1.2.3", stream.getWritten());
}
