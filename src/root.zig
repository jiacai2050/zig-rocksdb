const std = @import("std");
const testing = std.testing;
pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

pub const Options = struct {
    create_if_missing: bool,

    fn toC(self: Options) *c.rocksdb_options_t {
        const opt = c.rocksdb_options_create();

        c.rocksdb_options_set_create_if_missing(opt, @intFromBool(self.create_if_missing));
        return opt.?;
    }
};

pub const DB = struct {
    core: *c.rocksdb_t,

    pub fn init(path: [:0]const u8, options: Options) !DB {
        const c_options = options.toC();

        var err: ?[*:0]u8 = null;
        const c_db = c.rocksdb_open(
            c_options,
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
        c.rocksdb_put(self.core, c.rocksdb_writeoptions_create(), key.ptr, key.len, value.ptr, value.len, &err);
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
        const read_opts = c.rocksdb_readoptions_create();
        const value = c.rocksdb_get(
            self.core,
            read_opts,
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
