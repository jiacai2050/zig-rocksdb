const std = @import("std");
const rocksdb = @import("rocksdb");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = try rocksdb.Database(.Multiple).openColumnFamilies(
        allocator,
        "/tmp/zig-rocksdb-cf",
        .{ .create_if_missing = true },
        .{},
    );
    defer db.deinit();

    const cf_name = "metadata";
    if (!db.cfs.contains(cf_name)) {
        _ = try db.createColumnFamily(cf_name, .{});
    }

    try db.putCf(cf_name, "key", "value", .{});
    const value = try db.getCf(cf_name, "key", .{});
    if (value) |v| {
        defer rocksdb.free(v);
        std.debug.print("key is {s}\n", .{v});
    } else {
        std.debug.print("Not found\n", .{});
    }

    _ = try db.createColumnFamily("test-cf", .{});
    try db.dropColumnFamily("test-cf");
}
