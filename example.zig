const std = @import("std");
const rocksdb = @import("rocksdb");
const c = rocksdb.c;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const db = try rocksdb.DB.init("/tmp/zig-rocksdb-example", .{
        .create_if_missing = true,
    });
    defer db.deinit();

    for (0..10) |i| {
        const key = try std.fmt.allocPrint(allocator, "key-{d}", .{i});
        defer allocator.free(key);
        const value = try std.fmt.allocPrint(allocator, "{d}", .{i * i});
        defer allocator.free(value);
        try db.put(key, value);
    }

    for (0..10) |i| {
        const key = try std.fmt.allocPrint(allocator, "key-{d}", .{i});
        defer allocator.free(key);
        const value = try db.get(key);
        if (value) |v| {
            defer rocksdb.free(v);
            std.debug.print("{s} = {s}\n", .{ key, v });
        }
    }
}
