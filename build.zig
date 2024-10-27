const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const link_vendor = b.option(bool, "link_vendor", "Whether link to vendored rocksdb(default: true)") orelse true;

    const module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    var librocksdb: ?*Step.Compile = null;
    if (link_vendor) {
        if (try buildStaticRocksdb(b, target, optimize)) |v| {
            librocksdb = v;
            module.linkLibrary(v);
        } else {
            return;
        }
    } else {
        module.linkSystemLibrary("rocksdb", .{});
    }

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

fn buildStaticRocksdb(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !?*Step.Compile {
    const is_darwin = target.result.isDarwin();
    const is_linux = target.result.os.tag == .linux;

    const rocksdb_dep = b.lazyDependency("rocksdb", .{
        .target = target,
        .optimize = optimize,
    }) orelse return null;
    const lib = b.addStaticLibrary(.{
        .name = "rocksdb",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.root_module.sanitize_c = false;
    if (optimize != .Debug) {
        lib.define("NDEBUG", Some("1"));
    }

    lib.defineCMacro("ROCKSDB_PLATFORM_POSIX", null);
    lib.defineCMacro("ROCKSDB_LIB_IO_POSIX", null);
    lib.defineCMacro("ROCKSDB_SUPPORT_THREAD_LOCAL", null);
    if (is_darwin) {
        lib.defineCMacro("OS_MACOSX", null);
    } else if (is_linux) {
        lib.defineCMacro("OS_LINUX", null);
    }

    lib.linkLibCpp();
    lib.addIncludePath(rocksdb_dep.path("include"));
    lib.addIncludePath(rocksdb_dep.path("."));
    const cflags = &.{
        "-std=c++17",
        "-Wsign-compare",
        "-Wshadow",
        "-Wno-unused-parameter",
        "-Wno-unused-variable",
        "-Woverloaded-virtual",
        "-Wnon-virtual-dtor",
        "-Wno-missing-field-initializers",
        "-Wno-strict-aliasing",
        "-Wno-invalid-offsetof",
    };
    const src_file = b.path("sys/rocksdb_lib_sources.txt").getPath2(b, null);
    var f = try std.fs.openFileAbsolute(src_file, .{});
    const body = try f.readToEndAlloc(b.allocator, 1024_1000);
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |src| {
        // We have a pre-generated a version of build_version.cc in the local directory
        if (std.mem.eql(u8, "util/build_version.cc", src) or src.len == 0) {
            continue;
        }
        lib.addCSourceFile(.{
            .file = rocksdb_dep.path(src),
            .flags = cflags,
        });
    }
    lib.addCSourceFile(.{
        .file = b.path("sys/build_version.cc"),
        .flags = cflags,
    });
    b.installArtifact(lib);
    lib.installHeadersDirectory(rocksdb_dep.path("include/rocksdb"), "rocksdb", .{});
    return lib;
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
