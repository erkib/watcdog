const std = @import("std");
const builtin = @import("builtin");
const wd = @import("watchdog");

pub fn timevalToSeconds(tv: anytype) f64 {
    const sec = if (@hasField(@TypeOf(tv), "sec")) tv.sec else if (@hasField(@TypeOf(tv), "tv_sec")) tv.tv_sec else 0;
    const usec = if (@hasField(@TypeOf(tv), "usec")) tv.usec else if (@hasField(@TypeOf(tv), "tv_usec")) tv.tv_usec else 0;
    return @as(f64, @floatFromInt(sec)) + @as(f64, @floatFromInt(usec)) / 1_000_000.0;
}

pub fn isSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

pub fn printTelemetry(stdout: *std.Io.Writer, term: std.process.Child.Term, elapsed_ns: anytype) !bool {
    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);

    try stdout.print(
        "\n{s}{s}\n📊 === Telemetry Statistics ==={s}\n",
        .{
            wd.COLOR_CYAN,
            wd.COLOR_BOLD,
            wd.COLOR_RESET,
        },
    );
    try stdout.flush();

    // Parse the exit termination status cleanly
    var is_success = false;
    switch (term) {
        .exited => |code| {
            if (code == 0) {
                try stdout.print(
                    "• Status: {s}{s}Success (Exit Code 0){s}\n",
                    .{
                        wd.COLOR_GREEN,
                        wd.COLOR_BOLD,
                        wd.COLOR_RESET,
                    },
                );
                is_success = true;
            } else {
                try stdout.print(
                    "• Status: {s}{s}Failure (Exit Code {}){s}\n",
                    .{
                        wd.COLOR_RED,
                        wd.COLOR_BOLD,
                        code,
                        wd.COLOR_RESET,
                    },
                );
            }
        },
        .signal => |sig| {
            try stdout.print(
                "• Status: {s}Terminated by Signal ({}){s}\n",
                .{
                    wd.COLOR_YEL,
                    sig,
                    wd.COLOR_RESET,
                },
            );
        },
        .stopped => |sig| {
            try stdout.print(
                "• Status: {s}Stopped by Signal ({}){s}\n",
                .{
                    wd.COLOR_YEL,
                    sig,
                    wd.COLOR_RESET,
                },
            );
        },
        .unknown => |code| {
            try stdout.print(
                "• Status: {s}Terminated unpredictably (Code {}){s}\n",
                .{
                    wd.COLOR_RED,
                    code,
                    wd.COLOR_RESET,
                },
            );
        },
    }
    try stdout.flush();

    // Format the time output nicely based on how long it took
    if (elapsed_ms >= 1000) {
        const seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
        try stdout.print(
            "• Execution Time: {s}{d:.2} seconds{s}\n",
            .{
                wd.COLOR_BOLD,
                seconds,
                wd.COLOR_RESET,
            },
        );
    } else {
        try stdout.print("• Execution Time: {s}{} ms{s}\n", .{ wd.COLOR_BOLD, elapsed_ms, wd.COLOR_RESET });
    }

    // Format detailed resource usage statistics based on child process rusage
    if (@hasDecl(std.posix, "getrusage")) {
        const usage = std.posix.getrusage(-1);
        const user_cpu_sec = timevalToSeconds(usage.utime);
        const sys_cpu_sec = timevalToSeconds(usage.stime);
        const total_cpu_sec = user_cpu_sec + sys_cpu_sec;
        const elapsed_sec = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const cpu_util_pct = if (elapsed_sec > 0) (total_cpu_sec / elapsed_sec) * 100.0 else 0.0;

        try stdout.print(
            "• User CPU Time: {s}{d:.3}s{s}\n",
            .{
                wd.COLOR_BOLD,
                user_cpu_sec,
                wd.COLOR_RESET,
            },
        );
        try stdout.print(
            "• System CPU Time: {s}{d:.3}s{s}\n",
            .{
                wd.COLOR_BOLD,
                sys_cpu_sec,
                wd.COLOR_RESET,
            },
        );
        try stdout.print(
            "• CPU Utilization: {s}{d:.1}%{s}\n",
            .{
                wd.COLOR_BOLD,
                cpu_util_pct,
                wd.COLOR_RESET,
            },
        );

        // Format the maximum memory usage
        const raw_rss = if (usage.maxrss > 0) @as(u64, @intCast(usage.maxrss)) else 0;
        const max_rss_bytes: u64 = if (builtin.os.tag.isDarwin()) raw_rss else raw_rss * 1024;

        if (max_rss_bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
            try stdout.print(
                "• Max Memory Usage: {s}{d:.2} GB{s}\n",
                .{
                    wd.COLOR_BOLD,
                    gb,
                    wd.COLOR_RESET,
                },
            );
        } else if (max_rss_bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0);
            try stdout.print(
                "• Max Memory Usage: {s}{d:.2} MB{s}\n",
                .{
                    wd.COLOR_BOLD,
                    mb,
                    wd.COLOR_RESET,
                },
            );
        } else if (max_rss_bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(max_rss_bytes)) / 1024.0;
            try stdout.print(
                "• Max Memory Usage: {s}{d:.2} KB{s}\n",
                .{
                    wd.COLOR_BOLD,
                    kb,
                    wd.COLOR_RESET,
                },
            );
        } else {
            try stdout.print(
                "• Max Memory Usage: {s}{} bytes{s}\n",
                .{
                    wd.COLOR_BOLD,
                    max_rss_bytes,
                    wd.COLOR_RESET,
                },
            );
        }

        // Page faults
        const min_flt = if (usage.minflt > 0) usage.minflt else 0;
        const maj_flt = if (usage.majflt > 0) usage.majflt else 0;
        try stdout.print(
            "• Page Faults: {s}{} minor, {} major{s}\n",
            .{
                wd.COLOR_BOLD,
                min_flt,
                maj_flt,
                wd.COLOR_RESET,
            },
        );

        // Context switches
        const vcsw = if (usage.nvcsw > 0) usage.nvcsw else 0;
        const ivcsw = if (usage.nivcsw > 0) usage.nivcsw else 0;
        try stdout.print(
            "• Context Switches: {s}{} voluntary, {} involuntary{s}\n",
            .{
                wd.COLOR_BOLD,
                vcsw,
                ivcsw,
                wd.COLOR_RESET,
            },
        );

        // I/O operations
        const in_blk = if (usage.inblock > 0) usage.inblock else 0;
        const out_blk = if (usage.oublock > 0) usage.oublock else 0;
        try stdout.print(
            "• I/O Operations: {s}{} input, {} output blocks{s}\n",
            .{
                wd.COLOR_BOLD,
                in_blk,
                out_blk,
                wd.COLOR_RESET,
            },
        );
    }
    try stdout.print(
        "{s}{s}================================{s}\n",
        .{
            wd.COLOR_CYAN,
            wd.COLOR_BOLD,
            wd.COLOR_RESET,
        },
    );
    try stdout.flush();

    return is_success;
}

test "isSuccess logic" {
    try std.testing.expect(isSuccess(.{ .exited = 0 }));
    try std.testing.expect(!isSuccess(.{ .exited = 1 }));
    try std.testing.expect(!isSuccess(.{ .signal = .TERM }));
    try std.testing.expect(!isSuccess(.{ .stopped = .TERM }));
    try std.testing.expect(!isSuccess(.{ .unknown = 1 }));
}

test "telemetry cpu and utilization formatting logic" {
    var buffer: [128]u8 = undefined;

    // CPU times formatting
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const user_cpu_sec: f64 = 0.045;
        const sys_cpu_sec: f64 = 0.012;
        try writer.print("User: {d:.3}s | Sys: {d:.3}s", .{ user_cpu_sec, sys_cpu_sec });
        try std.testing.expectEqualStrings("User: 0.045s | Sys: 0.012s", writer.buffered());
    }

    // CPU utilization calculation & formatting
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const total_cpu_sec: f64 = 0.050;
        const elapsed_sec: f64 = 0.100;
        const cpu_util_pct = (total_cpu_sec / elapsed_sec) * 100.0;
        try writer.print("{d:.1}%", .{cpu_util_pct});
        try std.testing.expectEqualStrings("50.0%", writer.buffered());
    }
}

test "telemetry resource metrics formatting logic" {
    var buffer: [128]u8 = undefined;

    // Page Faults
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const min_flt: usize = 342;
        const maj_flt: usize = 0;
        try writer.print("{} minor, {} major", .{ min_flt, maj_flt });
        try std.testing.expectEqualStrings("342 minor, 0 major", writer.buffered());
    }

    // Context Switches
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const vcsw: usize = 12;
        const ivcsw: usize = 3;
        try writer.print("{} voluntary, {} involuntary", .{ vcsw, ivcsw });
        try std.testing.expectEqualStrings("12 voluntary, 3 involuntary", writer.buffered());
    }

    // I/O Operations
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const in_blk: usize = 8;
        const out_blk: usize = 0;
        try writer.print("{} input, {} output blocks", .{ in_blk, out_blk });
        try std.testing.expectEqualStrings("8 input, 0 output blocks", writer.buffered());
    }
}

test "telemetry memory formatting logic" {
    var buffer: [128]u8 = undefined;

    // Bytes: formatted as bytes
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const max_rss_bytes: u64 = 512;
        if (max_rss_bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
            try writer.print("{d:.2} GB", .{gb});
        } else if (max_rss_bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0);
            try writer.print("{d:.2} MB", .{mb});
        } else if (max_rss_bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(max_rss_bytes)) / 1024.0;
            try writer.print("{d:.2} KB", .{kb});
        } else {
            try writer.print("{} bytes", .{max_rss_bytes});
        }
        try std.testing.expectEqualStrings("512 bytes", writer.buffered());
    }

    // Kilobytes: formatted as KB
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const max_rss_bytes: u64 = 1024 * 512;
        if (max_rss_bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
            try writer.print("{d:.2} GB", .{gb});
        } else if (max_rss_bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0);
            try writer.print("{d:.2} MB", .{mb});
        } else if (max_rss_bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(max_rss_bytes)) / 1024.0;
            try writer.print("{d:.2} KB", .{kb});
        } else {
            try writer.print("{} bytes", .{max_rss_bytes});
        }
        try std.testing.expectEqualStrings("512.00 KB", writer.buffered());
    }

    // Megabytes: formatted as MB
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const max_rss_bytes: u64 = 1024 * 1024 * 12 + 1024 * 512; // 12.5 MB
        if (max_rss_bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
            try writer.print("{d:.2} GB", .{gb});
        } else if (max_rss_bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0);
            try writer.print("{d:.2} MB", .{mb});
        } else if (max_rss_bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(max_rss_bytes)) / 1024.0;
            try writer.print("{d:.2} KB", .{kb});
        } else {
            try writer.print("{} bytes", .{max_rss_bytes});
        }
        try std.testing.expectEqualStrings("12.50 MB", writer.buffered());
    }

    // Gigabytes: formatted as GB
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const max_rss_bytes: u64 = 1024 * 1024 * 1024 * 2; // 2.00 GB
        if (max_rss_bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
            try writer.print("{d:.2} GB", .{gb});
        } else if (max_rss_bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(max_rss_bytes)) / (1024.0 * 1024.0);
            try writer.print("{d:.2} MB", .{mb});
        } else if (max_rss_bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(max_rss_bytes)) / 1024.0;
            try writer.print("{d:.2} KB", .{kb});
        } else {
            try writer.print("{} bytes", .{max_rss_bytes});
        }
        try std.testing.expectEqualStrings("2.00 GB", writer.buffered());
    }
}

test "telemetry time formatting logic" {
    var buffer: [128]u8 = undefined;

    // Sub-second: formatted as ms
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const elapsed_ms: u64 = 450;
        if (elapsed_ms >= 1000) {
            const seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
            try writer.print("{d:.2} seconds", .{seconds});
        } else {
            try writer.print("{} ms", .{elapsed_ms});
        }
        try std.testing.expectEqualStrings("450 ms", writer.buffered());
    }

    // Multi-second: formatted as seconds
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const elapsed_ms: u64 = 2500;
        if (elapsed_ms >= 1000) {
            const seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
            try writer.print("{d:.2} seconds", .{seconds});
        } else {
            try writer.print("{} ms", .{elapsed_ms});
        }
        try std.testing.expectEqualStrings("2.50 seconds", writer.buffered());
    }
}

test "telemetry status formatting logic" {
    var buffer: [128]u8 = undefined;

    // Success status
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const term = std.process.Child.Term{ .exited = 0 };
        switch (term) {
            .exited => |code| {
                if (code == 0) {
                    try writer.print("Success (Exit Code 0)", .{});
                } else {
                    try writer.print("Failure (Exit Code {})", .{code});
                }
            },
            .signal => |sig| try writer.print("Terminated by Signal ({})", .{sig}),
            .stopped => |sig| try writer.print("Stopped by Signal ({})", .{sig}),
            .unknown => |code| try writer.print("Terminated unpredictably (Code {})", .{code}),
        }
        try std.testing.expectEqualStrings("Success (Exit Code 0)", writer.buffered());
    }

    // Non-zero exit status
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const term = std.process.Child.Term{ .exited = 42 };
        switch (term) {
            .exited => |code| {
                if (code == 0) {
                    try writer.print("Success (Exit Code 0)", .{});
                } else {
                    try writer.print("Failure (Exit Code {})", .{code});
                }
            },
            .signal => |sig| try writer.print("Terminated by Signal ({})", .{sig}),
            .stopped => |sig| try writer.print("Stopped by Signal ({})", .{sig}),
            .unknown => |code| try writer.print("Terminated unpredictably (Code {})", .{code}),
        }
        try std.testing.expectEqualStrings("Failure (Exit Code 42)", writer.buffered());
    }

    // Signal status
    {
        var writer = std.Io.Writer.fixed(&buffer);
        const term = std.process.Child.Term{ .signal = .TERM };
        switch (term) {
            .exited => |code| {
                if (code == 0) {
                    try writer.print("Success (Exit Code 0)", .{});
                } else {
                    try writer.print("Failure (Exit Code {})", .{code});
                }
            },
            .signal => |sig| try writer.print("Terminated by Signal ({s})", .{@tagName(sig)}),
            .stopped => |sig| try writer.print("Stopped by Signal ({s})", .{@tagName(sig)}),
            .unknown => |code| try writer.print("Terminated unpredictably (Code {})", .{code}),
        }
        try std.testing.expectEqualStrings("Terminated by Signal (TERM)", writer.buffered());
    }
}

test "printTelemetry writes statistics correctly" {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const success = try printTelemetry(&writer, .{ .exited = 0 }, 150_000_000);
    try std.testing.expect(success);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Telemetry Statistics") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Status: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Execution Time: ") != null);
}
