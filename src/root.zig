const std = @import("std");
const testing = std.testing;
pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

pub const Options = struct {
    create_if_missing: bool,

    fn toC(self: Options) *c.rocksdb_options_t {
        const opts = c.rocksdb_options_create();
        errdefer c.rocksdb_options_destroy(opts);

        c.rocksdb_options_set_create_if_missing(opts, @intFromBool(self.create_if_missing));
        return opts.?;
    }
};

pub fn free(v: []const u8) void {
    c.rocksdb_free(@constCast(@ptrCast(v.ptr)));
}

pub const DB = struct {
    core: *c.rocksdb_t,

    pub fn init(path: [:0]const u8, options: Options) !DB {
        const c_opts = options.toC();
        defer c.rocksdb_options_destroy(c_opts);

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

    pub fn put(self: DB, key: []const u8, value: []const u8) !void {
        var err: ?[*:0]u8 = null;
        const opts = c.rocksdb_writeoptions_create();
        defer c.rocksdb_writeoptions_destroy(opts);
        c.rocksdb_put(self.core, opts, key.ptr, key.len, value.ptr, value.len, &err);
        if (err) |e| {
            std.log.err("Error reading database: {s}", .{e});
            c.rocksdb_free(e);
            return;
        }

        return;
    }

    pub fn get(self: DB, key: []const u8) !?[]const u8 {
        var value_len: usize = 0;
        var err: ?[*:0]u8 = null;
        const opts = c.rocksdb_readoptions_create();
        defer c.rocksdb_readoptions_destroy(opts);
        const value = c.rocksdb_get(
            self.core,
            opts,
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
