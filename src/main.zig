const std = @import("std");
const a = @import("arguments");
const n = @import("notificaions");
const wd = @import("watchdog");

pub fn main(init: std.process.Init) !u8 {
    // --- STEP 1: ALLOCATOR & ARGUMENT PARSING ---
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const config = a.parseConfig(args) catch |err| switch (err) {
        error.NoArguments => {
            try wd.printUsage(stdout);
            return 1;
        },

        error.InvalidTimeout => {
            try stderr.print(
                "{s}Error: Invalid timeout value '{s}'. Must be a positive integer.{s}\n",
                .{wd.COLOR_RED, a.argOrValue orelse "", wd.COLOR_RESET});
            try stderr.flush();
            return 1;
        },

        error.TimeoutRequiresValue => {
            try stderr.print(
                "{s}Error: Flag '{s}' requires an integer value.{s}\n",
                .{wd.COLOR_RED, a.argOrValue orelse "--timeout/-t", wd.COLOR_RESET});
            try stderr.flush();
            return 1;
        },

        error.CommandMissing => {
            try stderr.print(
                "{s}Error: Missing target command. You must provide a command after '--'.{s}\n\n",
                .{wd.COLOR_RED, wd.COLOR_RESET});
            try stderr.flush();
            try wd.printUsage(stdout);
            return 1;
        },

        error.Unknown => {
            try stderr.print(
                "{s}Error: Unknown configuration option '{s}'.{s}\n\n",
                .{wd.COLOR_RED, a.argOrValue orelse "", wd.COLOR_RESET});
            try stderr.flush();
            try wd.printUsage(stdout);
            return 1;
        }
    };

    // Debug level: Show app config
    if (config.debug) {
        try stdout.print("=== Watchdog Configuration ===\n", .{});
        if (config.timeout_seconds) |t| {
            try stdout.print("• Timeout Limit: {} seconds\n", .{t});
        }
        else {
            try stdout.print("• Timeout Limit: None\n", .{});
        }

        try stdout.print("• Target Command: ", .{});
        for (config.target_argv) |cmd_part| {
            try stdout.print("{s} ", .{cmd_part});
        }
        try stdout.print("\n==============================\n\n", .{});
        try stdout.flush();
    }

    // --- STEP 2: SPAWN THE CHILD PROCESS ---
    try stdout.print(
        "{s}{s}🚀 Launching target process...{s}\n\n",
        .{wd.COLOR_CYAN, wd.COLOR_BOLD, wd.COLOR_RESET});
    try stdout.flush();

    // Initialize the child process with our isolated command slice
    var child = std.process.spawn(init.io, .{ .argv = config.target_argv }) catch |err| {
        try stderr.print(
            "{s}❌ Failed to execute command: {}{s}\n",
            .{wd.COLOR_RED, err, wd.COLOR_RESET});
        try stderr.flush();
        return 1;
    };

    // --- STEP 3: SPAWN BACKGROUND TIMEOUT WATCHER ---
    var ctx = wd.WatchContext{
        .child = &child,
        .io = init.io,
        .mutex = .init,
        .stdout = stdout,
        .timeout_seconds = config.timeout_seconds,
    };
    const timeout_thread = try std.Thread.spawn(.{}, wd.timeoutWatcher, .{&ctx});
    defer timeout_thread.join();

    // Start a monotonic timer. Monotonic timers are immune to system clock shifts
    // (like daylight savings updates or manual time changes).
    var timer = std.Io.Clock.awake.now(init.io);

    // Spawn the process and wait blocks until the child exits.
    // It passes standard input/output/error directly through to your terminal.
    const term = child.wait(init.io) catch |err| {
        try stderr.print(
            "{s}❌ Failed to execute command: {}{s}\n",
            .{wd.COLOR_RED, err, wd.COLOR_RESET});
        try stderr.flush();
        return 1;
    };

    // Signal to the background thread that the task is finished
    try ctx.mutex.lock(init.io);
    ctx.is_done = true;
    ctx.mutex.unlock(init.io);

    // --- STEP 4: TELEMETRY ANALYSIS ---
    const elapsed_ns = timer.untilNow(init.io, .awake).nanoseconds;
    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);

    try stdout.print(
        "\n{s}{s}\n📊 === Telemetry Statistics ==={s}\n",
        .{wd.COLOR_CYAN, wd.COLOR_BOLD, wd.COLOR_RESET});
    try stdout.flush();

    // Parse the exit termination status cleanly
    var is_success = false;
    switch (term) {
        .exited => |code| {
            if (code == 0) {
                try stdout.print(
                    "• Status: {s}{s}Success (Exit Code 0){s}\n",
                    .{wd.COLOR_GREEN, wd.COLOR_BOLD, wd.COLOR_RESET});
                is_success = true;
            }
            else {
                try stdout.print(
                    "• Status: {s}{s}Failure (Exit Code {}){s}\n",
                    . {wd.COLOR_RED, wd.COLOR_BOLD, code, wd.COLOR_RESET});
            }
        },
        .signal => |sig| {
            try stdout.print(
                "• Status: {s}Terminated by Signal ({}){s}\n",
                .{wd.COLOR_YEL, sig, wd.COLOR_RESET});
        },
        .stopped => |sig| {
            try stdout.print(
                "• Status: {s}Stopped by Signal ({}){s}\n",
                .{wd.COLOR_YEL, sig, wd.COLOR_RESET});
        },
        .unknown => |code| {
            try stdout.print(
                "• Status: {s}Terminated unpredictably (Code {}){s}\n",
                .{wd.COLOR_RED, code, wd.COLOR_RESET});
        },
    }
    try stdout.flush();

    // Format the time output nicely based on how long it took
    if (elapsed_ms >= 1000) {
        const seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
        try stdout.print(
            "• Execution Time: {s}{d:.2} seconds{s}\n",
            .{wd.COLOR_BOLD, seconds, wd.COLOR_RESET});
    }
    else {
        try stdout.print(
            "• Execution Time: {s}{} ms{s}\n",
            .{wd.COLOR_BOLD, elapsed_ms, wd.COLOR_RESET});
    }
    try stdout.print(
        "{s}{s}================================{s}\n",
        .{wd.COLOR_CYAN, wd.COLOR_BOLD, wd.COLOR_RESET});
    try stdout.flush();

    // --- STEP 5: TRIGGER DESKTOP PUSH NOTIFICATION ---
    const title = "Watchdog Alert";
    const message = if (ctx.is_killed)
        "Task was forced to terminate because it hit the timeout ceiling!"
    else if (is_success)
        "Task finished running perfectly!"
    else
        "Task crashed or returned a non-zero error code.";

    n.sendNotification(init.gpa, init.io, title, message) catch |err| {
        try stderr.print(
            "\n{s}Note: Failed to push OS desktop notification: {}{s}\n",
            .{wd.COLOR_RED, err, wd.COLOR_RESET});
        try stderr.flush();
    };

    return 0;
}
