const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    module.linkSystemLibrary("rocksdb", .{});

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    const run_step = b.step("run", "Run all examples");
    test_step.dependOn(&run_lib_unit_tests.step);
    buildExample(b, "basic", run_step, target, optimize, module);
    buildExample(b, "cf", run_step, target, optimize, module);
}

fn buildExample(
    b: *std.Build,
    comptime name: []const u8,
    run_all: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(std.fmt.comptimePrint("examples/{s}.zig", .{name})),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("rocksdb", module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run-" ++ name, "Run the app");
    run_step.dependOn(&run_cmd.step);
    run_all.dependOn(&run_cmd.step);
}
