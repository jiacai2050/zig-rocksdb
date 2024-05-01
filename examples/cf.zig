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
    inline for ([_][:0]const u8{ "key", "key2" }) |key| {
        const value = try db.getCf(cf_name, key, .{});
        if (value) |v| {
            defer rocksdb.free(v);
            std.debug.print("{s} is {s}\n", .{ key, v });
        } else {
            std.debug.print("{s} not found\n", .{key});
        }
    }

    _ = db.createColumnFamily(cf_name, .{}) catch |e| {
        std.log.err("err:{any}", .{e});
        return;
    };
    try db.dropColumnFamily(cf_name);
}
