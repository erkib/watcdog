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
        }
        else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--timeout")) {
            // Check if there is a following argument to parse as an integer
            if (i + 1 < args.len) {
                i += 1;
                timeout_seconds = std.fmt.parseInt(u64, args[i], 10) catch {
                    argOrValue = args[i][0..args[i].len];
                    return WatchdogArgumentsError.InvalidTimeout;
                };
            }
            else {
                argOrValue = arg[0..arg.len];
                return WatchdogArgumentsError.TimeoutRequiresValue;
            }
        }
        else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            is_debug = true;
        }
        else {
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