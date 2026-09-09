//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

// ANSI Terminal Escape Codes for Styling
pub const COLOR_RESET = "\x1b[0m";
pub const COLOR_BOLD = "\x1b[1m";
pub const COLOR_RED = "\x1b[31m";
pub const COLOR_GREEN = "\x1b[32m";
pub const COLOR_YEL = "\x1b[33m";
pub const COLOR_CYAN = "\x1b[36m";

pub const WatchContext = struct {
    child: *std.process.Child,
    timeout_seconds: ?u64,
    mutex: std.Io.Mutex,
    io: std.Io,
    is_done: bool = false,
    is_killed: bool = false,
    stdout: *std.Io.Writer,
};

// Background thread function
pub fn timeoutWatcher(ctx: *WatchContext) !void {
    // If no timeout was requested, this thread has nothing to monitor
    const timeout_secs = ctx.timeout_seconds orelse return;

    // Sleep in 100ms intervals to keep responsiveness fast if the child exits quickly
    const total_intervals = timeout_secs * 10;
    var i: u64 = 0;
    while (i < total_intervals) : (i += 1) {
        try std.Io.sleep(ctx.io, std.Io.Duration.fromMilliseconds(100), .awake);

        try ctx.mutex.lock(ctx.io);
        if (ctx.is_done) {
            ctx.mutex.unlock(ctx.io);
            return; // Target process finished safely on time!
        }
        ctx.mutex.unlock(ctx.io);
    }

    // If we reach here, the timeout limit expired!
    try ctx.mutex.lock(ctx.io);
    defer ctx.mutex.unlock(ctx.io);

    if (!ctx.is_done) {
        try ctx.stdout.print(
            "\n{s}{s}\n⚠️  [Watchdog] Process exceeded timeout limit of {}s. Sending termination signal...{s}\n",
            .{
                COLOR_YEL,
                COLOR_BOLD,
                timeout_secs,
                COLOR_RESET,
            },
        );
        try ctx.stdout.flush();

        // Forcibly terminate the running process by sending a signal
        if (ctx.child.id) |pid| {
            try std.posix.kill(pid, std.posix.SIG.TERM);
        }
        ctx.is_done = true;
        ctx.is_killed = true;
    }
}

pub fn printUsage(stdout: *std.Io.Writer) !void {
    const usage_text =
        \\Usage: watchdog [options] -- <command> [arguments...]
        \\
        \\Options:
        \\  -t, --timeout <seconds>   Kill the process if it runs longer than specified.
        \\  -d, --debug               Be more verbose in output.
        \\
        \\Example:
        \\  watchdog --timeout 5 -- sleep 10
        \\
    ;
    try stdout.print("{s}", .{usage_text});
    try stdout.flush();
}

test "printUsage outputs expected text" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printUsage(&writer);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: watchdog") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "-t, --timeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "-d, --debug") != null);
}

test "timeoutWatcher returns immediately when timeout_seconds is null" {
    var ctx = WatchContext{
        .child = undefined,
        .timeout_seconds = null,
        .mutex = .init,
        .io = std.testing.io,
        .stdout = undefined,
    };
    try timeoutWatcher(&ctx);
    try std.testing.expect(!ctx.is_killed);
    try std.testing.expect(!ctx.is_done);
}

test "timeoutWatcher exits early when process finishes on time" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    var ctx = WatchContext{
        .child = undefined,
        .timeout_seconds = 2,
        .mutex = .init,
        .io = std.testing.io,
        .stdout = &writer,
        .is_done = false,
        .is_killed = false,
    };

    const thread = try std.Thread.spawn(.{}, timeoutWatcher, .{&ctx});

    // Simulate child process finishing after 50ms
    try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(50), .awake);
    try ctx.mutex.lock(std.testing.io);
    ctx.is_done = true;
    ctx.mutex.unlock(std.testing.io);

    thread.join();

    try std.testing.expect(ctx.is_done);
    try std.testing.expect(!ctx.is_killed);
}
