const std = @import("std");
const builtin = @import("builtin");
const zcc = @import("compile_commands");
const app_name = "chipmunk";

const release_flags = [_][]const u8{"-DNDEBUG"};
const debug_flags = [_][]const u8{};

const c_sources = [_][]const u8{
    "src/chipmunk.c",
    "src/cpArbiter.c",
    "src/cpArray.c",
    "src/cpBBTree.c",
    "src/cpBody.c",
    "src/cpCollision.c",
    "src/cpConstraint.c",
    "src/cpDampedRotarySpring.c",
    "src/cpDampedSpring.c",
    "src/cpGearJoint.c",
    "src/cpGrooveJoint.c",
    "src/cpHashSet.c",
    "src/cpMarch.c",
    "src/cpPinJoint.c",
    "src/cpPivotJoint.c",
    "src/cpPolyline.c",
    "src/cpPolyShape.c",
    "src/cpRatchetJoint.c",
    "src/cpRobust.c",
    "src/cpRotaryLimitJoint.c",
    "src/cpShape.c",
    "src/cpSimpleMotor.c",
    "src/cpSlideJoint.c",
    "src/cpSpace.c",
    "src/cpSpaceComponent.c",
    "src/cpSpaceDebug.c",
    "src/cpSpaceHash.c",
    "src/cpSpaceQuery.c",
    "src/cpSpaceStep.c",
    "src/cpSpatialIndex.c",
    "src/cpSweep1D.c",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});
    var targets = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);

    const lib = b.addStaticLibrary(.{
        .name = app_name,
        .optimize = mode,
        .target = target,
    });
    try targets.append(lib);

    if (b.option(bool, "use_doubles", "Use double precision floating point values")) |use_doubles| {
        lib.defineCMacro("CP_USE_DOUBLES", if (use_doubles) "1" else "0");
    }

    // copied from chipmunk cmake. may be redundant with zig default flags
    // also the compiler is obviously never msvc so idk if the if is necessary
    var flags = std.ArrayList([]const u8).init(b.allocator);
    //if (lib.rootModuleTarget().getAbi() != .msvc) {
    try flags.appendSlice(&.{ "-fblocks", "-std=gnu99" });
    if (builtin.mode != .Debug) {
        try flags.append("-ffast-math");
    } else {
        try flags.append("-Wall");
    }
    //}

    // universal includes / links
    try include(b, targets, "include");
    try link(targets, "m");

    switch (target.result.os.tag) {
        .wasi, .emscripten => {
            std.log.info("building for emscripten\n", .{});

            if (b.sysroot == null) {
                std.log.err("\n\nUSAGE: Please build with a specified sysroot: 'zig build --sysroot \"$EMSDK/upstream/emscripten\"'\n\n", .{});
                return error.SysRootExpected;
            }

            // include emscripten headers for compat, for example sys/sysctl
            const emscripten_include_flag = try std.fmt.allocPrint(b.allocator, "-I{s}/include", .{b.sysroot.?});
            try flags.appendSlice(&.{emscripten_include_flag});

            // define some macros in case there web-conditional code in chipmunk
            lib.defineCMacro("__EMSCRIPTEN__", null);
            lib.defineCMacro("PLATFORM_WEB", null);

            // run emranlib
            const emranlib_file = switch (b.graph.host.result.os.tag) {
                .windows => "emranlib.bat",
                else => "emranlib",
            };
            // TODO: remove bin if on linux, or make my linux packaging for EMSDK have the same file structure as windows
            const emranlib_path = try std.fs.path.join(b.allocator, &.{ b.sysroot.?, "bin", emranlib_file });
            const run_emranlib = b.addSystemCommand(&.{emranlib_path});
            run_emranlib.addArtifactArg(lib);
            b.getInstallStep().dependOn(&run_emranlib.step);
        },
        else => {
            switch (mode) {
                .Debug => {
                    try flags.appendSlice(&debug_flags);
                },
                else => {
                    try flags.appendSlice(&release_flags);
                },
            }
            lib.linkLibC();
        },
    }

    lib.addCSourceFiles(.{
        .files = &c_sources,
        .flags = flags.items,
    });

    // always install chipmunk headers
    lib.installHeadersDirectory(.{ .src_path = .{
        .owner = b,
        .sub_path = "include/chipmunk",
    } }, "chipmunk", .{});

    for (targets.items) |t| {
        b.installArtifact(t);
    }

    zcc.createStep(b, "cdb", try targets.toOwnedSlice());
}

fn link(
    targets: std.ArrayList(*std.Build.Step.Compile),
    lib: []const u8,
) !void {
    for (targets.items) |target| {
        target.linkSystemLibrary(lib);
    }
}

fn include(
    b: *std.Build,
    targets: std.ArrayList(*std.Build.Step.Compile),
    path: []const u8,
) !void {
    for (targets.items) |target| {
        target.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = path } });
    }
}
