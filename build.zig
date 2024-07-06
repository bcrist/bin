const std = @import("std");
const shittip = @import("shittip");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ext = .{
        .Temp_Allocator = b.dependency("Temp_Allocator", .{}).module("Temp_Allocator"),
        .deep_hash_map = b.dependency("deep_hash_map", .{}).module("deep_hash_map"),
        .sx = b.dependency("sx", .{}).module("sx"),
        .tempora = b.dependency("tempora", .{}).module("tempora"),
        .dizzy = b.dependency("dizzy", .{}).module("dizzy"),
        .http = b.dependency("shittip", .{}).module("http"),
    };

    const exe = b.addExecutable(.{
        .name = "bin",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("Temp_Allocator", ext.Temp_Allocator);
    exe.root_module.addImport("deep_hash_map", ext.deep_hash_map);
    exe.root_module.addImport("sx", ext.sx);
    exe.root_module.addImport("tempora", ext.tempora);
    exe.root_module.addImport("dizzy", ext.dizzy);
    exe.root_module.addImport("http", ext.http);
    exe.root_module.addImport("http_resources", shittip.resources(b, &.{
        .{ .path = "src/http/resources" },
        .{ .path = "src/http/stylesheets" },
        .{ .path = "src/http/templates" },
    }, .{}));

    b.installArtifact(exe);
    var run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "run bin").dependOn(&run.step);
    if (b.args) |args| {
        run.addArgs(args);
    }

    // const t = b.addTest(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_tests = b.addRunArtifact(t);
    // b.step("test", "Run tests").dependOn(&run_tests.step);
}
