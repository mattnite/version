const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

const mecha = Pkg{
    .name = "mecha",
    .path = "../mecha/mecha.zig",
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("version", "src/main.zig");
    lib.setBuildMode(mode);
    lib.addPackage(mecha);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.addPackage(mecha);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
