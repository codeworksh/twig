//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

// =============================================================
// CoreFoundation & CoreGraphics extern declarations
// =============================================================
// Declare only the exact C types and functions we need.
// This is idiomatic Zig — explicit and minimal.
// Opaque pointer types — we never look inside these,
// we just pass them to C functions.
// In Zig, `*anyopaque` means "pointer to something, I don't care what".
pub const CFArrayRef = *anyopaque;
pub const CFDictionaryRef = *anyopaque;
pub const CFStringRef = *anyopaque;
pub const CFNumberRef = *anyopaque;
pub const CFTypeRef = *anyopaque;

//
// CGWindowListCopyWindowInfo types
pub const CGWindowID = u32;
pub const CGWindowListOption = u32;

//
// Constants — these match the values from Apple's headers.
// In Zig, `const` at file scope = comptime-known immutable value.
pub const kCGWindowListOptionAll: CGWindowListOption = 0;
pub const kCGWindowListOptionOnScreenOnly: CGWindowListOption = 1 << 0;
pub const kCGWindowListExcludeDesktopElements: CGWindowListOption = 1 << 4;
pub const kCGNullWindowID: CGWindowID = 0;

//
// CFNumber type enum — we only need kCFNumberIntType (= 9)
pub const CFNumberType = i64;
pub const kCFNumberIntType: CFNumberType = 9;

//
// CFString encoding — we only need UTF-8 (= 0x08000100)
pub const CFStringEncoding = u32;
pub const kCFStringEncodingUTF8: CFStringEncoding = 0x08000100;

// --- The C functions we will call ---
// CoreGraphics: get a list of all windows
pub extern "c" fn CGWindowListCopyWindowInfo(
    option: CGWindowListOption,
    relativeToWindow: CGWindowID,
) ?CFArrayRef;

// CoreGraphics: CGRect geometry types
pub const CGFloat = f64; // On 64-bit macOS, CGFloat is double
pub const CGPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};
pub const CGSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};
pub const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,
};
// Helper to parse kCGWindowBounds into a CGRect
pub extern "c" fn CGRectMakeWithDictionaryRepresentation(dict: CFDictionaryRef, rect: *CGRect) bool;

// CoreFoundation: work with CFArray
pub extern "c" fn CFArrayGetCount(theArray: CFArrayRef) isize;
pub extern "c" fn CFArrayGetValueAtIndex(theArray: CFArrayRef, idx: isize) ?*const anyopaque;
// CoreFoundation: work with CFDictionary
// This is like Python's dict.get(key) — returns null if key not found.
pub extern "c" fn CFDictionaryGetValue(
    theDict: CFDictionaryRef,
    key: ?*const anyopaque,
) ?*const anyopaque;
// CoreFoundation: work with CFString
// Converts a CFString to a C string (null-terminated bytes).
pub extern "c" fn CFStringGetCString(
    theString: CFStringRef,
    buffer: [*]u8,
    bufferSize: isize,
    encoding: CFStringEncoding,
) bool;
// CoreFoundation: work with CFNumber
// Extracts the numeric value from a CFNumber into a C variable.
pub extern "c" fn CFNumberGetValue(
    number: CFNumberRef,
    theType: CFNumberType,
    valuePtr: *anyopaque,
) bool;
// CoreFoundation: memory management
// CFRelease decrements the reference count. When it hits 0, the object is freed.
// We must call this on any CF object we "own" (any function with "Copy" or "Create" in its name).
pub extern "c" fn CFRelease(cf: *anyopaque) void;
// CoreFoundation: create a CFString from a C string literal.
// We need this to create dictionary keys like "kCGWindowOwnerName".
pub extern "c" fn CFStringCreateWithCString(
    alloc: ?*anyopaque, // pass null to use the default allocator
    cStr: [*:0]const u8, // Zig's type for a null-terminated string pointer
    encoding: CFStringEncoding,
) ?CFStringRef;

///
/// Making sure we can run
/// Clean this up when not required
pub fn allIsWell(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("All Is Well ;).\n", .{});
}

/// Exclude specific system apps
const AppExcludes = [_][]const u8{
    "Window Server",
    "Dock",
    "Control Center",
    "Notification Center",
    "loginwindow",
    "Spotlight",
    "ScreensaverEngine",
};

// We use i32 for bounds, even though macOS natively returns f64 (CGFloat) for these values.
// Logical screen coordinates are almost always whole numbers.
pub const AppBounds = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const App = struct {
    pid: i32,
    owner: [512]u8,
    owner_len: usize,
    name: [512]u8,
    name_len: usize,
    window_id: u32,
    bounds: AppBounds = .{
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 0,
    },

    pub fn getName(self: *const App) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getOwner(self: *const App) []const u8 {
        return self.owner[0..self.owner_len];
    }
};

pub const TwigError = error{
    FailedToGetWindowList,
    FailedToCreateKey,
};

pub fn listRunningApps(allocator: std.mem.Allocator) ![]App {
    var apps = std.ArrayList(App).empty;
    errdefer apps.deinit(allocator);

    const options = kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements;
    const wins = CGWindowListCopyWindowInfo(options, kCGNullWindowID);

    const wl = wins orelse return TwigError.FailedToGetWindowList;

    defer CFRelease(wl);

    const key_owner_pid = CFStringCreateWithCString(null, "kCGWindowOwnerPID", kCFStringEncodingUTF8) orelse return TwigError.FailedToCreateKey;
    defer CFRelease(key_owner_pid);

    const key_owner_name = CFStringCreateWithCString(null, "kCGWindowOwnerName", kCFStringEncodingUTF8) orelse return TwigError.FailedToCreateKey;
    defer CFRelease(key_owner_name);

    const key_window_name = CFStringCreateWithCString(null, "kCGWindowName", kCFStringEncodingUTF8) orelse return TwigError.FailedToCreateKey;
    defer CFRelease(key_window_name);

    const key_window_id = CFStringCreateWithCString(null, "kCGWindowNumber", kCFStringEncodingUTF8) orelse return TwigError.FailedToCreateKey;
    defer CFRelease(key_window_id);

    const key_window_bounds = CFStringCreateWithCString(null, "kCGWindowBounds", kCFStringEncodingUTF8) orelse return TwigError.FailedToCreateKey;
    defer CFRelease(key_window_bounds);

    const count = CFArrayGetCount(wl);
    var i: isize = 0;

    apps_loop: while (i < count) : (i += 1) {
        const dict_ptr = CFArrayGetValueAtIndex(wl, i) orelse continue;
        const dict: CFDictionaryRef = @ptrCast(@constCast(dict_ptr));

        var pid: i32 = 0;
        const pid_val = CFDictionaryGetValue(dict, key_owner_pid);
        // Make sure `pid_val` is not null; unwrap and set the value if exists
        if (pid_val) |pv| {
            _ = CFNumberGetValue(
                @ptrCast(@constCast(pv)),
                kCFNumberIntType,
                @ptrCast(&pid),
            );
        }

        var window_id: u32 = 0;
        const window_id_val = CFDictionaryGetValue(dict, key_window_id);
        if (window_id_val) |wv| {
            _ = CFNumberGetValue(
                @ptrCast(@constCast(wv)),
                kCFNumberIntType,
                @ptrCast(&window_id),
            );
        }

        var bounds = AppBounds{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const bounds_val = CFDictionaryGetValue(dict, key_window_bounds);
        if (bounds_val) |bv| {
            var rect: CGRect = undefined;
            if (CGRectMakeWithDictionaryRepresentation(@ptrCast(@constCast(bv)), &rect)) {
                bounds.x = @intFromFloat(rect.origin.x);
                bounds.y = @intFromFloat(rect.origin.y);
                bounds.width = @intFromFloat(rect.size.width);
                bounds.height = @intFromFloat(rect.size.height);
            }
        }

        var owner_buf: [512]u8 = undefined;
        var owner_len: usize = 0;

        const owner_val = CFDictionaryGetValue(dict, key_owner_name);
        if (owner_val) |nv| {
            if (CFStringGetCString(
                @ptrCast(@constCast(nv)),
                &owner_buf,
                @intCast(owner_buf.len),
                kCFStringEncodingUTF8,
            )) {
                // Find the actual string length (position of null terminator)
                owner_len = std.mem.indexOfScalar(u8, &owner_buf, 0) orelse 0;
            }
        }

        var name_buf: [512]u8 = undefined;
        var name_len: usize = 0;

        // fallback to `Unknown` when not known.
        // window names are specific to running applications which can be unknown
        const name_val = CFDictionaryGetValue(dict, key_window_name);
        if (name_val) |nv| {
            if (CFStringGetCString(
                @ptrCast(@constCast(nv)),
                &name_buf,
                @intCast(name_buf.len),
                kCFStringEncodingUTF8,
            )) {
                // Find the actual string length (position of null terminator)
                name_len = std.mem.indexOfScalar(u8, &name_buf, 0) orelse 0;
            }
        } else {
            const default = "Unknown";
            @memcpy(name_buf[0..default.len], default);
            name_len = default.len;
        }

        // skip unknowns; have no value
        if (pid == 0) continue :apps_loop;
        if (owner_len == 0) continue :apps_loop;

        // skip MacOS excludes
        for (AppExcludes) |excluded| {
            if (std.mem.eql(u8, excluded, owner_buf[0..owner_len])) {
                continue :apps_loop;
            }
        }

        var already_seen = false;
        for (apps.items) |app| {
            if (app.pid == pid) {
                already_seen = true;
                break;
            }
        }
        if (already_seen) continue :apps_loop;

        try apps.append(allocator, App{
            .pid = pid,
            .window_id = window_id,
            .owner = owner_buf,
            .owner_len = owner_len,
            .name = name_buf,
            .name_len = name_len,
            .bounds = bounds,
        });
    }

    return apps.toOwnedSlice(allocator);
}
