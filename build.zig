const std = @import("std");
const shittip = @import("shittip");

var builder: *std.Build = undefined;
var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var all_tests_step: *std.Build.Step = undefined;

pub fn build(b: *std.Build) void {
    builder = b;
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});
    all_tests_step = b.step("test", "Run all tests");

    const ext = .{
        .Temp_Allocator = b.dependency("Zig-TempAllocator", .{}).module("Temp_Allocator"),
        .console = b.dependency("Zig-ConsoleHelper", .{}).module("console"),
        .deep_hash_map = b.dependency("Zig-DeepHashMap", .{}).module("deep_hash_map"),
        .sx = b.dependency("Zig-SX", .{}).module("sx"),
        .tempora = b.dependency("tempora", .{}).module("tempora"),
        .dizzy = b.dependency("dizzy", .{}).module("dizzy"),
        .http = b.dependency("shittip", .{}).module("http"),
    };

    const exe = makeExe("bin", .{ .path = "src/main.zig" });
    exe.root_module.addImport("Temp_Allocator", ext.Temp_Allocator);
    exe.root_module.addImport("deep_hash_map", ext.deep_hash_map);
    exe.root_module.addImport("sx", ext.sx);
    exe.root_module.addImport("tempora", ext.tempora);
    exe.root_module.addImport("dizzy", ext.dizzy);
    exe.root_module.addImport("http", ext.http);
    exe.root_module.addImport("http_resources", shittip.resources(b, .{
        .root_path = .{ .path = "src/http/resources" },
    }));
}

fn makeModule(root_source_file: std.Build.LazyPath) *std.Build.Module {
    return builder.createModule(.{ .root_source_file = root_source_file });
}

fn makeExe(comptime name: []const u8, root_source_file: std.Build.LazyPath) *std.Build.Step.Compile {
    const exe = builder.addExecutable(.{
        .name = name,
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    builder.installArtifact(exe);
    var run = builder.addRunArtifact(exe);
    run.step.dependOn(builder.getInstallStep());
    builder.step(name, "run " ++ name).dependOn(&run.step);
    if (builder.args) |args| {
        run.addArgs(args);
    }

    _ = makeTest(name, root_source_file);

    return exe;
}

fn makeTest(comptime name: []const u8, root_source_file: std.Build.LazyPath) *std.Build.Step.Compile {
    const t = builder.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const run = builder.addRunArtifact(t);
    builder.step("test_" ++ name, "test " ++ name).dependOn(&run.step);
    all_tests_step.dependOn(&run.step);

    return t;
}
