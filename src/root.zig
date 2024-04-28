const std = @import("std");
const Options = @import("options.zig").Options;
const ReadOptions = @import("options.zig").ReadOptions;
const WriteOptions = @import("options.zig").WriteOptions;
const testing = std.testing;
pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

/// Free slice generated by the RocksDB C API.
pub fn free(v: []const u8) void {
    c.rocksdb_free(@constCast(@ptrCast(v.ptr)));
}

pub const DB = struct {
    core: *c.rocksdb_t,

    pub fn init(path: [:0]const u8, opts: Options) !DB {
        const c_opts = opts.toC();
        defer c.rocksdb_options_destroy(c_opts);

        return DB.open(path, c_opts);
    }

    pub fn open(path: [:0]const u8, c_opts: *c.rocksdb_options_t) !DB {
        var err: ?[*:0]u8 = null;
        const c_db = c.rocksdb_open(
            c_opts,
            path.ptr,
            &err,
        );

        if (err) |e| {
            std.log.err("Error opening database: {s}", .{e});
            c.rocksdb_free(err);
            return error.UnexpectedError;
        }

        return DB{ .core = c_db.? };
    }

    pub fn deinit(self: DB) void {
        c.rocksdb_close(self.core);
    }

    pub fn put(self: DB, key: []const u8, value: []const u8, opts: WriteOptions) !void {
        var err: ?[*:0]u8 = null;
        const c_opts = opts.toC();
        defer c.rocksdb_writeoptions_destroy(c_opts);
        c.rocksdb_put(
            self.core,
            c_opts,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &err,
        );
        if (err) |e| {
            std.log.err("Error reading database: {s}", .{e});
            c.rocksdb_free(e);
            return;
        }

        return;
    }

    pub fn get(self: DB, key: []const u8, opts: ReadOptions) !?[]const u8 {
        var value_len: usize = 0;
        var err: ?[*:0]u8 = null;
        const c_opts = opts.toC();
        defer c.rocksdb_readoptions_destroy(c_opts);
        const value = c.rocksdb_get(
            self.core,
            c_opts,
            key.ptr,
            key.len,
            &value_len,
            &err,
        );
        if (err) |e| {
            std.log.err("Error reading from database: {s}", .{e});
            c.rocksdb_free(err);
            return error.UnexpectedError;
        }

        return if (value) |v|
            v[0..value_len]
        else
            null;
    }
};
