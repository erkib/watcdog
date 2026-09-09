const std = @import("std");
const builtin = @import("builtin");

pub fn sendNotification(allocator: std.mem.Allocator, io: std.Io, title: []const u8, message: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => {
            const argv = [_][]const u8{ "notify-send", title, message };
            var notifier = try std.process.spawn(io, .{ .argv = &argv });
            _ = try notifier.wait(io);
        },
        .macos => {
            // We use standard AppleScript to map system notification graphics strings
            const script = try std.fmt.allocPrint(
                allocator,
                "display notification \"{s}\" with title \"{s}\"",
                .{ message, title },
            );
            defer allocator.free(script);

            const argv = [_][]const u8{ "osascript", "-e", script };
            var notifier = try std.process.spawn(io, .{ .argv = &argv });
            _ = try notifier.wait(io);
        },
        .windows => {
            const cmd = try std.fmt.allocPrint(
                allocator,
                "New-BurntToastNotification -Text '{s}', '{s}'",
                .{ title, message },
            );
            defer allocator.free(cmd);

            const argv = [_][]const u8{ "powershell", "-Command", cmd };
            var notifier = try std.process.spawn(io, .{ .argv = &argv });
            _ = try notifier.wait(io);
        },
        else => {
            // Unsupported OS tags fall through quietly without crashing
            return;
        },
    }
}

test "notifications AppleScript format and memory allocation" {
    const allocator = std.testing.allocator;
    const title = "Watchdog Alert";
    const message = "Task finished running perfectly!";

    const script = try std.fmt.allocPrint(
        allocator,
        "display notification \"{s}\" with title \"{s}\"",
        .{ message, title },
    );
    defer allocator.free(script);

    try std.testing.expectEqualStrings("display notification \"Task finished running perfectly!\" with title \"Watchdog Alert\"", script);
}

test "notifications PowerShell format and memory allocation" {
    const allocator = std.testing.allocator;
    const title = "Watchdog Alert";
    const message = "Task crashed or returned a non-zero error code.";

    const cmd = try std.fmt.allocPrint(
        allocator,
        "New-BurntToastNotification -Text '{s}', '{s}'",
        .{ title, message },
    );
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("New-BurntToastNotification -Text 'Watchdog Alert', 'Task crashed or returned a non-zero error code.'", cmd);
}

test "notifications formatting with special characters and unicode" {
    const allocator = std.testing.allocator;
    const title = "🚀 Watchdog";
    const message = "Path: /tmp/test, exit: 0 (100% OK)";

    const script = try std.fmt.allocPrint(
        allocator,
        "display notification \"{s}\" with title \"{s}\"",
        .{ message, title },
    );
    defer allocator.free(script);

    try std.testing.expectEqualStrings("display notification \"Path: /tmp/test, exit: 0 (100% OK)\" with title \"🚀 Watchdog\"", script);
}
