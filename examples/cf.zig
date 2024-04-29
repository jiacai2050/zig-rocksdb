const std = @import("std");
const rocksdb = @import("rocksdb");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const db = try rocksdb.DB.openColumnFamilies(
        allocator,
        "/tmp/zig-rocksdb-cf",
        .{
            .create_if_missing = true,
        },
    );
    defer db.deinit();

    const cf = db.createColumnFamily("metadata", .{}) catch |e| {
        std.log.err("create cf, {any}", .{e});
        return;
    };
    defer cf.deinit();

    std.debug.print("{any}\n", .{cf});
}
