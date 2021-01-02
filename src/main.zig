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

    pub fn cmp(self: Semver, other: Semver) std.math.Order {
        return if (self.major != other.major)
            std.math.order(self.major, other.major)
        else if (self.minor != other.minor)
            std.math.order(self.minor, other.minor)
        else
            std.math.order(self.patch, other.patch);
    }

    pub fn inside(self: Semver, range: Range) bool {
        return self.cmp(range.min).compare(.gte) and self.cmp(range.less_than).compare(.lt);
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

pub const Range = struct {
    min: Semver,
    less_than: Semver,

    const parser = map(
        Range,
        toRange,
        combine(.{
            opt(oneOf(.{ utf8.range('~', '~'), utf8.range('^', '^') })),
            Semver.semver,
            opt(combine(.{ utf8.char('-'), Semver.semver })),
        }),
    );

    fn toRange(tuple: anytype) Range {
        const Kind = enum {
            approx,
            carot,
            explicit,
            exact,
        };

        const kind: Kind = if (tuple[0]) |char|
            if (char == '~') Kind.approx else if (char == '^') Kind.carot else unreachable
        else if (tuple[2] != null)
            Kind.explicit
        else
            Kind.exact;

        return Range{
            .min = Semver{
                .major = tuple[1][0],
                .minor = tuple[1][1],
                .patch = tuple[1][2],
            },
            .less_than = switch (kind) {
                .approx => Semver{
                    .major = tuple[1][0],
                    .minor = tuple[1][1] + 1,
                    .patch = 0,
                },
                .carot => Semver{
                    .major = tuple[1][0] + 1,
                    .minor = 0,
                    .patch = 0,
                },
                .explicit => Semver{
                    .major = tuple[2].?[0],
                    .minor = tuple[2].?[1],
                    .patch = tuple[2].?[2] + 1,
                },
                .exact => Semver{
                    .major = tuple[1][0],
                    .minor = tuple[1][1],
                    .patch = tuple[1][2] + 1,
                },
            },
        };
    }

    pub fn parse(str: []const u8) !Range {
        if (mem.indexOf(u8, str, "-") != null and (mem.indexOf(u8, str, "~") != null or mem.indexOf(u8, str, "^") != null))
            return error.InvalidString;

        const range = (parser(str) orelse return error.InvalidString).value;
        if (range.min.cmp(range.less_than) != .lt) return error.BadOrder;

        return range;
    }

    pub fn contains(self: Range, semver: Semver) bool {
        return semver.inside(range);
    }
};

test "empty string" {
    expectError(error.InvalidString, Range.parse(""));
}

test "approximate" {
    const expected = Range{
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
        .less_than = Semver{
            .major = 1,
            .minor = 3,
            .patch = 0,
        },
    };
    expectEqual(expected, try Range.parse("~1.2.3"));
}

test "caret" {
    const expected = Range{
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
        .less_than = Semver{
            .major = 2,
            .minor = 0,
            .patch = 0,
        },
    };
    expectEqual(expected, try Range.parse("^1.2.3"));
}

test "explicit range" {
    const expected = Range{
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
        .less_than = Semver{
            .major = 2,
            .minor = 3,
            .patch = 6,
        },
    };
    expectEqual(expected, try Range.parse("1.2.3-2.3.5"));
}

test "exact range" {
    const expected = Range{
        .min = Semver{
            .major = 1,
            .minor = 2,
            .patch = 3,
        },
        .less_than = Semver{
            .major = 1,
            .minor = 2,
            .patch = 4,
        },
    };
    expectEqual(expected, try Range.parse("1.2.3"));
}
