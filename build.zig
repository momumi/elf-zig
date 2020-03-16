const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Library building
    {
        const lib = b.addStaticLibrary("elf-zig", "src/elf.zig");
        lib.setBuildMode(mode);
        lib.install();

        var main_tests = b.addTest("src/elf.zig");
        main_tests.setBuildMode(mode);

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&main_tests.step);
    }

    // example-hello
    {
        const exe = b.addExecutable("example-hello", "examples/hello.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();

        exe.addPackagePath("elf", "src/elf.zig");

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("example-hello", "Build and run the hello example");
        run_step.dependOn(&run_cmd.step);
    }

    // example-hello-section
    {
        const exe = b.addExecutable("example-hello-section", "examples/hello-section.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();

        exe.addPackagePath("elf", "src/elf.zig");

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("example-hello-section", "Build and run the hello example");
        run_step.dependOn(&run_cmd.step);

        const run_step_default = b.step("run", "Build and run the hello example");
        run_step_default.dependOn(&run_cmd.step);
    }
}
