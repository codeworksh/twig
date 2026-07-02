const std = @import("std");
const Io = std.Io;

const twig = @import("twig");

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try twig.allIsWell(stdout_writer);
    try stdout_writer.flush(); // Don't forget to flush!

    std.debug.print("twig — listing running macOS apps...\n\n", .{});

    const apps = try twig.listRunningApps(arena);
    for (apps) |app| {
        std.debug.print("PID: {d: >6} | WinID: {d: >6} | Layer: {d: >3} | Alpha: {d:.2} | Owner: {s: <15} | Bounds(x:{d} y:{d} w:{d} h:{d}) | Name: {s}\n", 
            .{ app.pid, app.window_id, app.layer, app.alpha, app.getOwner(), app.bounds.x, app.bounds.y, app.bounds.width, app.bounds.height, app.getName() });
    }
    std.debug.print("\nFound {d} visible apps.\n", .{apps.len});
}
