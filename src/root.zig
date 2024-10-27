const std = @import("std");
const Options = @import("options.zig").Options;
const ReadOptions = @import("options.zig").ReadOptions;
const WriteOptions = @import("options.zig").WriteOptions;
const ColumnFamily = @import("ColumnFamily.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const is_latest_zig = @import("builtin").zig_version.minor > 13;

const testing = std.testing;
pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

/// Free slice generated by the RocksDB C API.
pub fn free(v: []const u8) void {
    c.rocksdb_free(@constCast(@ptrCast(v.ptr)));
}

pub const ThreadMode = enum {
    Single,
    Multiple,
};

/// A RocksDB database, wrapper around `c.rocksdb_t`.
///
/// `ThreadMode` controls how column families are managed.
pub fn Database(comptime tm: ThreadMode) type {
    return struct {
        c_handle: *c.rocksdb_t,
        allocator: Allocator,
        cfs: std.StringHashMap(ColumnFamily),
        cfs_lock: switch (tm) {
            .Multiple => std.Thread.Mutex,
            .Single => void,
        },

        const Self = @This();
        pub fn open(allocator: Allocator, path: [:0]const u8, opts: Options) !Self {
            const c_opts = opts.toC();
            defer c.rocksdb_options_destroy(c_opts);

            return Self.openRaw(allocator, path, c_opts);
        }

        pub fn openColumnFamilies(allocator: Allocator, path: [:0]const u8, db_opts: Options, cf_opts: Options) !Self {
            const c_db_opts = db_opts.toC();
            defer c.rocksdb_options_destroy(c_db_opts);
            const cf_names = try Self.listColumnFamilyRaw(path, c_db_opts) orelse return Self.openRaw(allocator, path, c_db_opts);
            defer c.rocksdb_list_column_families_destroy(cf_names.ptr, cf_names.len);

            const c_cf_opt = cf_opts.toC();
            defer c.rocksdb_options_destroy(c_cf_opt);
            var c_cf_opts = std.ArrayList(*c.rocksdb_options_t).init(allocator);
            defer c_cf_opts.deinit();
            for (0..cf_names.len) |_| {
                try c_cf_opts.append(c_cf_opt);
            }

            var cf_handles = std.ArrayList(?*c.rocksdb_column_family_handle_t).init(allocator);
            for (0..cf_names.len) |_| {
                try cf_handles.append(null);
            }

            var err: ?[*:0]u8 = null;
            const c_handle = c.rocksdb_open_column_families(
                c_db_opts,
                path,
                @intCast(cf_names.len),
                cf_names.ptr,
                c_cf_opts.items.ptr,
                cf_handles.items.ptr,
                &err,
            );
            if (err) |e| {
                std.log.err("Error open column families: {s}", .{e});
                c.rocksdb_free(err);
                return error.OpenDatabase;
            }

            var cfs = std.StringHashMap(ColumnFamily).init(allocator);
            for (cf_names, cf_handles.items) |name, handle| {
                if (handle) |h| {
                    const n = try allocator.dupe(u8, std.mem.span(name));
                    try cfs.put(n, ColumnFamily.init(h));
                } else {
                    return error.ColumnFamilyNull;
                }
            }

            return Self{
                .allocator = allocator,
                .c_handle = c_handle.?,
                .cfs = cfs,
                .cfs_lock = switch (tm) {
                    .Single => {},
                    .Multiple => std.Thread.Mutex{},
                },
            };
        }

        pub fn openRaw(allocator: Allocator, path: [:0]const u8, c_opts: *c.rocksdb_options_t) !Self {
            var err: ?[*:0]u8 = null;
            const c_handle = c.rocksdb_open(
                c_opts,
                path.ptr,
                &err,
            );

            if (err) |e| {
                std.log.err("Error opening database: {s}", .{e});
                c.rocksdb_free(err);
                return error.OpenDatabase;
            }

            return Self{
                .c_handle = c_handle.?,
                .allocator = allocator,
                .cfs = std.StringHashMap(ColumnFamily).init(allocator),
                .cfs_lock = switch (tm) {
                    .Single => {},
                    .Multiple => std.Thread.Mutex{},
                },
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.cfs.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.*.deinit();
            }
            self.cfs.deinit();

            c.rocksdb_close(self.c_handle);
        }

        pub fn put(self: Self, key: []const u8, value: []const u8, opts: WriteOptions) !void {
            const c_opts = opts.toC();
            defer c.rocksdb_writeoptions_destroy(c_opts);

            try self.ffi(c.rocksdb_put, .{
                c_opts,
                key.ptr,
                key.len,
                value.ptr,
                value.len,
            });
        }

        pub fn putCf(self: Self, cf_name: []const u8, key: []const u8, value: []const u8, opts: WriteOptions) !void {
            const cf =
                self.cfs.get(cf_name) orelse return error.NoSuchColumnFamily;

            const c_opts = opts.toC();
            defer c.rocksdb_writeoptions_destroy(c_opts);
            try self.ffi(c.rocksdb_put_cf, .{
                c_opts,
                cf.c_handle,
                key.ptr,
                key.len,
                value.ptr,
                value.len,
            });
        }

        pub fn get(self: Self, key: []const u8, opts: ReadOptions) !?[]const u8 {
            var value_len: usize = 0;
            const c_opts = opts.toC();
            defer c.rocksdb_readoptions_destroy(c_opts);
            const value = try self.ffi(c.rocksdb_get, .{
                c_opts,
                key.ptr,
                key.len,
                &value_len,
            });

            return if (value) |v|
                v[0..value_len]
            else
                null;
        }

        pub fn getCf(self: Self, cf_name: []const u8, key: []const u8, opts: ReadOptions) !?[]const u8 {
            const cf = self.cfs.get(cf_name) orelse return error.NoSuchColumnFamily;

            var value_len: usize = 0;
            const c_opts = opts.toC();
            defer c.rocksdb_readoptions_destroy(c_opts);
            const value = try self.ffi(c.rocksdb_get_cf, .{
                c_opts,
                cf.c_handle,
                key.ptr,
                key.len,
                &value_len,
            });

            return if (value) |v|
                v[0..value_len]
            else
                null;
        }

        pub fn listColumnFamilyRaw(path: [:0]const u8, c_opts: *c.rocksdb_options_t) !?[][*c]u8 {
            var err: ?[*:0]u8 = null;
            var len: usize = 0;
            const cf_list = c.rocksdb_list_column_families(c_opts, path.ptr, &len, &err);

            if (err) |e| {
                const err_msg = std.mem.span(e);
                if (std.mem.containsAtLeast(u8, err_msg, 1, "No such file or directory")) {
                    return null;
                }
                std.log.err("Error list column families: {s}", .{e});
                c.rocksdb_free(err);
                return error.ListColumnFamilies;
            }

            return cf_list[0..len];
        }

        pub fn createColumnFamily(
            self: *Self,
            name: [:0]const u8,
            opts: Options,
        ) !ColumnFamily {
            if (comptime @TypeOf(self.cfs_lock) != void)
                self.cfs_lock.lock();

            defer if (comptime @TypeOf(self.cfs_lock) != void)
                self.cfs_lock.unlock();

            if (self.cfs.contains(name)) {
                return error.CFAlreadyExists;
            }
            const c_opts = opts.toC();
            defer c.rocksdb_options_destroy(c_opts);

            const c_cf = try self.ffi(c.rocksdb_create_column_family, .{
                c_opts,
                name.ptr,
            });
            errdefer c.rocksdb_column_family_handle_destroy(c_cf);

            const cf = ColumnFamily{ .c_handle = c_cf.? };
            try self.cfs.put(try self.allocator.dupe(u8, name), cf);
            return cf;
        }

        pub fn dropColumnFamily(
            self: *Self,
            name: [:0]const u8,
        ) !void {
            if (comptime @TypeOf(self.cfs_lock) != void)
                self.cfs_lock.lock();

            defer if (comptime @TypeOf(self.cfs_lock) != void)
                self.cfs_lock.unlock();

            const cf = self.cfs.get(name) orelse return error.CFNotExists;

            try self.ffi(c.rocksdb_drop_column_family, .{
                cf.c_handle,
            });

            cf.deinit();
            std.debug.assert(self.cfs.remove(name));
        }

        /// Call RocksDB c API, automatically fill follow params:
        /// - The first, `?*c.rocksdb_t`
        /// - The last, `[*c][*c]errptr`
        fn ffi(self: Self, c_func: anytype, args: anytype) !FFIReturnType(@TypeOf(c_func)) {
            var ffi_args: std.meta.ArgsTuple(@TypeOf(c_func)) = undefined;
            ffi_args[0] = self.c_handle;
            inline for (args, 1..) |arg, i| {
                ffi_args[i] = arg;
            }
            var err: ?[*:0]u8 = null;
            ffi_args[ffi_args.len - 1] = &err;
            const v = @call(.auto, c_func, ffi_args);
            if (err) |e| {
                std.log.err("Error when call rocksdb, msg:{s}", .{e});
                c.rocksdb_free(err);
                return error.DBError;
            }

            return v;
        }
    };
}

fn FFIReturnType(Func: type) type {
    const info = @typeInfo(Func);
    const fn_info = switch (info) {
        if (is_latest_zig) .@"fn" else .Fn => |fn_info| fn_info,
        else => @compileError("expecting a function"),
    };

    return fn_info.return_type.?;
}
