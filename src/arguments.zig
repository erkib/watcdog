const std = @import("std");

pub const WatchdogConfig = struct {
    debug: bool,
    timeout_seconds: ?u64,
    target_argv: []const []const u8,
};

pub const WatchdogArgumentsError = error{
    NoArguments,
    InvalidTimeout,
    TimeoutRequiresValue,
    CommandMissing,
    Unknown,
};

pub var argOrValue: ?[]const u8 = undefined;

pub fn parseConfig(args: []const []const u8) WatchdogArgumentsError!WatchdogConfig {
    // If they run just 'watchdog' without any parameters, show how to use it
    if (args.len < 2) {
        return WatchdogArgumentsError.NoArguments;
    }

    // 3. Define state variables to hold our parsed configurations
    var is_debug = false;
    var timeout_seconds: ?u64 = null;
    var target_command_index: ?usize = null;

    // 4. Iterate through arguments to find our flags and the critical `--` separator
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--")) {
            // Everything past this exact index belongs to the target process
            if (i + 1 < args.len) {
                target_command_index = i + 1;
            }
            break;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--timeout")) {
            // Check if there is a following argument to parse as an integer
            if (i + 1 < args.len) {
                i += 1;
                timeout_seconds = std.fmt.parseInt(u64, args[i], 10) catch {
                    argOrValue = args[i][0..args[i].len];
                    return WatchdogArgumentsError.InvalidTimeout;
                };
            } else {
                argOrValue = arg[0..arg.len];
                return WatchdogArgumentsError.TimeoutRequiresValue;
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            is_debug = true;
        } else {
            argOrValue = arg[0..arg.len];
            return WatchdogArgumentsError.Unknown;
        }
    }

    // 5. Enforce that a target command must actually follow the `--`
    const cmd_idx = target_command_index orelse {
        return WatchdogArgumentsError.CommandMissing;
    };

    // Slice the original array to cleanly grab only the user's intended target command
    return WatchdogConfig{
        .debug = is_debug,
        .timeout_seconds = timeout_seconds,
        .target_argv = args[cmd_idx..args.len],
    };
}

test "parseConfig returns NoArguments when args slice has fewer than 2 elements" {
    const empty_args: []const []const u8 = &.{};
    try std.testing.expectError(
        WatchdogArgumentsError.NoArguments,
        parseConfig(empty_args),
    );

    const single_arg: []const []const u8 = &.{"watchdog"};
    try std.testing.expectError(
        WatchdogArgumentsError.NoArguments,
        parseConfig(single_arg),
    );
}

test "parseConfig minimal valid command with separator" {
    const args: []const []const u8 = &.{ "watchdog", "--", "echo", "hello" };
    const config = try parseConfig(args);

    try std.testing.expect(!config.debug);
    try std.testing.expectEqual(@as(?u64, null), config.timeout_seconds);
    try std.testing.expectEqual(@as(usize, 2), config.target_argv.len);
    try std.testing.expectEqualStrings("echo", config.target_argv[0]);
    try std.testing.expectEqualStrings("hello", config.target_argv[1]);
}

test "parseConfig with debug flag" {
    const args_short: []const []const u8 = &.{ "watchdog", "-d", "--", "ls" };
    const config_short = try parseConfig(args_short);
    try std.testing.expect(config_short.debug);
    try std.testing.expectEqual(@as(?u64, null), config_short.timeout_seconds);
    try std.testing.expectEqual(@as(usize, 1), config_short.target_argv.len);
    try std.testing.expectEqualStrings("ls", config_short.target_argv[0]);

    const args_long: []const []const u8 = &.{ "watchdog", "--debug", "--", "ls" };
    const config_long = try parseConfig(args_long);
    try std.testing.expect(config_long.debug);
}

test "parseConfig with timeout flag" {
    const args_short: []const []const u8 = &.{ "watchdog", "-t", "10", "--", "sleep", "5" };
    const config_short = try parseConfig(args_short);
    try std.testing.expect(!config_short.debug);
    try std.testing.expectEqual(@as(?u64, 10), config_short.timeout_seconds);
    try std.testing.expectEqual(@as(usize, 2), config_short.target_argv.len);
    try std.testing.expectEqualStrings("sleep", config_short.target_argv[0]);
    try std.testing.expectEqualStrings("5", config_short.target_argv[1]);

    const args_long: []const []const u8 = &.{ "watchdog", "--timeout", "30", "--", "sleep", "5" };
    const config_long = try parseConfig(args_long);
    try std.testing.expectEqual(@as(?u64, 30), config_long.timeout_seconds);
}

test "parseConfig with all options combined" {
    const args: []const []const u8 = &.{ "watchdog", "-d", "--timeout", "60", "--", "my_app", "--arg1", "-v" };
    const config = try parseConfig(args);
    try std.testing.expect(config.debug);
    try std.testing.expectEqual(@as(?u64, 60), config.timeout_seconds);
    try std.testing.expectEqual(@as(usize, 3), config.target_argv.len);
    try std.testing.expectEqualStrings("my_app", config.target_argv[0]);
    try std.testing.expectEqualStrings("--arg1", config.target_argv[1]);
    try std.testing.expectEqualStrings("-v", config.target_argv[2]);
}

test "parseConfig preserves arguments after separator unchanged" {
    const args: []const []const u8 = &.{ "watchdog", "--", "cmd", "-d", "-t", "5", "--timeout" };
    const config = try parseConfig(args);
    try std.testing.expect(!config.debug);
    try std.testing.expectEqual(@as(?u64, null), config.timeout_seconds);
    try std.testing.expectEqual(@as(usize, 5), config.target_argv.len);
    try std.testing.expectEqualStrings("cmd", config.target_argv[0]);
    try std.testing.expectEqualStrings("-d", config.target_argv[1]);
    try std.testing.expectEqualStrings("-t", config.target_argv[2]);
    try std.testing.expectEqualStrings("5", config.target_argv[3]);
    try std.testing.expectEqualStrings("--timeout", config.target_argv[4]);
}

test "parseConfig returns CommandMissing when separator is missing" {
    const args: []const []const u8 = &.{ "watchdog", "-d" };
    try std.testing.expectError(WatchdogArgumentsError.CommandMissing, parseConfig(args));

    const args_with_timeout: []const []const u8 = &.{ "watchdog", "-t", "5" };
    try std.testing.expectError(
        WatchdogArgumentsError.CommandMissing,
        parseConfig(args_with_timeout),
    );
}

test "parseConfig returns CommandMissing when nothing follows separator" {
    const args: []const []const u8 = &.{ "watchdog", "--" };
    try std.testing.expectError(WatchdogArgumentsError.CommandMissing, parseConfig(args));

    const args_with_flags: []const []const u8 = &.{ "watchdog", "-d", "--" };
    try std.testing.expectError(
        WatchdogArgumentsError.CommandMissing,
        parseConfig(args_with_flags),
    );
}

test "parseConfig returns TimeoutRequiresValue when timeout flag has no argument" {
    const args_short: []const []const u8 = &.{ "watchdog", "-t" };
    try std.testing.expectError(
        WatchdogArgumentsError.TimeoutRequiresValue,
        parseConfig(args_short),
    );
    try std.testing.expectEqualStrings("-t", argOrValue.?);

    const args_long: []const []const u8 = &.{ "watchdog", "--timeout" };
    try std.testing.expectError(
        WatchdogArgumentsError.TimeoutRequiresValue,
        parseConfig(args_long),
    );
    try std.testing.expectEqualStrings("--timeout", argOrValue.?);
}

test "parseConfig returns InvalidTimeout when timeout value is not a valid integer" {
    const args_non_numeric: []const []const u8 = &.{ "watchdog", "-t", "abc", "--", "cmd" };
    try std.testing.expectError(
        WatchdogArgumentsError.InvalidTimeout,
        parseConfig(args_non_numeric),
    );
    try std.testing.expectEqualStrings("abc", argOrValue.?);

    const args_negative: []const []const u8 = &.{ "watchdog", "--timeout", "-10", "--", "cmd" };
    try std.testing.expectError(
        WatchdogArgumentsError.InvalidTimeout,
        parseConfig(args_negative),
    );
    try std.testing.expectEqualStrings("-10", argOrValue.?);
}

test "parseConfig returns Unknown when an unrecognized flag or argument is passed" {
    const args_flag: []const []const u8 = &.{ "watchdog", "--unknown", "--", "cmd" };
    try std.testing.expectError(WatchdogArgumentsError.Unknown, parseConfig(args_flag));
    try std.testing.expectEqualStrings("--unknown", argOrValue.?);

    const args_no_separator: []const []const u8 = &.{ "watchdog", "cmd" };
    try std.testing.expectError(
        WatchdogArgumentsError.Unknown,
        parseConfig(args_no_separator),
    );
    try std.testing.expectEqualStrings("cmd", argOrValue.?);
}

test "parseConfig handles timeout zero and u64 max" {
    const args_zero: []const []const u8 = &.{ "watchdog", "-t", "0", "--", "echo" };
    const cfg_zero = try parseConfig(args_zero);
    try std.testing.expectEqual(@as(?u64, 0), cfg_zero.timeout_seconds);

    const args_max: []const []const u8 = &.{ "watchdog", "-t", "18446744073709551615", "--", "echo" };
    const cfg_max = try parseConfig(args_max);
    try std.testing.expectEqual(@as(?u64, std.math.maxInt(u64)), cfg_max.timeout_seconds);
}

test "parseConfig returns InvalidTimeout on u64 overflow" {
    const args_overflow: []const []const u8 = &.{ "watchdog", "-t", "18446744073709551616", "--", "cmd" };
    try std.testing.expectError(
        WatchdogArgumentsError.InvalidTimeout,
        parseConfig(args_overflow),
    );
    try std.testing.expectEqualStrings("18446744073709551616", argOrValue.?);
}

test "parseConfig handles flags in different orders and multiple occurrences" {
    const args_order1: []const []const u8 = &.{ "watchdog", "-d", "-t", "10", "--", "cmd" };
    const cfg1 = try parseConfig(args_order1);
    try std.testing.expect(cfg1.debug);
    try std.testing.expectEqual(@as(?u64, 10), cfg1.timeout_seconds);

    const args_order2: []const []const u8 = &.{ "watchdog", "-t", "10", "-d", "--", "cmd" };
    const cfg2 = try parseConfig(args_order2);
    try std.testing.expect(cfg2.debug);
    try std.testing.expectEqual(@as(?u64, 10), cfg2.timeout_seconds);

    // Duplicate flags: last timeout overwrites earlier
    const args_dup: []const []const u8 = &.{ "watchdog", "-t", "5", "-t", "20", "--", "cmd" };
    const cfg_dup = try parseConfig(args_dup);
    try std.testing.expectEqual(@as(?u64, 20), cfg_dup.timeout_seconds);
}

test "parseConfig handles timeout flag followed by separator" {
    const args: []const []const u8 = &.{ "watchdog", "-t", "--", "cmd" };
    try std.testing.expectError(
        WatchdogArgumentsError.InvalidTimeout,
        parseConfig(args),
    );
    try std.testing.expectEqualStrings("--", argOrValue.?);
}

test "parseConfig preserves empty target argument and inner separator" {
    const args_empty_arg: []const []const u8 = &.{ "watchdog", "--", "echo", "" };
    const cfg_empty = try parseConfig(args_empty_arg);
    try std.testing.expectEqual(@as(usize, 2), cfg_empty.target_argv.len);
    try std.testing.expectEqualStrings("echo", cfg_empty.target_argv[0]);
    try std.testing.expectEqualStrings("", cfg_empty.target_argv[1]);

    const args_inner_sep: []const []const u8 = &.{ "watchdog", "--", "grep", "--", "pattern", "file" };
    const cfg_inner = try parseConfig(args_inner_sep);
    try std.testing.expectEqual(@as(usize, 4), cfg_inner.target_argv.len);
    try std.testing.expectEqualStrings("grep", cfg_inner.target_argv[0]);
    try std.testing.expectEqualStrings("--", cfg_inner.target_argv[1]);
    try std.testing.expectEqualStrings("pattern", cfg_inner.target_argv[2]);
    try std.testing.expectEqualStrings("file", cfg_inner.target_argv[3]);
}

test "parseConfig argOrValue state resets correctly across calls" {
    // 1. Unsuccessful call setting argOrValue
    _ = parseConfig(&.{ "watchdog", "-t", "invalid", "--", "cmd" }) catch {};
    try std.testing.expectEqualStrings("invalid", argOrValue.?);

    // 2. Successful call
    const cfg = try parseConfig(&.{ "watchdog", "-t", "10", "--", "cmd" });
    try std.testing.expectEqual(@as(?u64, 10), cfg.timeout_seconds);

    // 3. Another unsuccessful call
    _ = parseConfig(&.{ "watchdog", "--bad-flag", "--", "cmd" }) catch {};
    try std.testing.expectEqualStrings("--bad-flag", argOrValue.?);
}
