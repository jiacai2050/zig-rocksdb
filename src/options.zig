const std = @import("std");
pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

/// The default values mentioned here, describe the values of the C++ library only.
/// This wrapper does not set any default value itself. So as soon as the rocksdb
/// developers change a default value this document could be outdated. So if you
/// really depend on a default value, double check it with the according version of the C++ library.
/// Most recent default values should be here
/// https://github.com/facebook/rocksdb/blob/v9.1.1/include/rocksdb/options.h#L489
pub const Options = struct {
    /// If true, the database will be created if it is missing.
    /// Default: false
    create_if_missing: ?bool = null,
    /// If true, missing column families will be automatically created on `DB::Open()`
    /// Default: false
    create_missing_column_families: ?bool = null,
    /// If true, an error is raised if the database already exists.
    /// Default: false
    error_if_exists: ?bool = null,
    /// If true, RocksDB will aggressively check consistency of the data.
    /// Also, if any of the  writes to the database fails (Put, Delete, Merge,
    /// Write), the database will switch to read-only mode and fail all other
    /// Write operations.
    /// In most cases you want this to be set to true.
    /// Default: true
    paranoid_checks: ?bool = null,
    /// Default: -1
    max_open_files: ?i32 = null,
    /// Default: 16
    max_file_opening_threads: ?i32 = null,
    /// Once write-ahead logs exceed this size, we will start forcing the flush of
    /// column families whose memtables are backed by the oldest live WAL file
    /// (i.e. the ones that are causing all the space amplification). If set to 0
    /// (default), we will dynamically choose the WAL size limit to be
    /// [sum of all write_buffer_size * max_write_buffer_number] * 4
    ///
    /// For example, with 15 column families, each with
    /// write_buffer_size = 128 MB
    /// max_write_buffer_number = 6
    /// max_total_wal_size will be calculated to be [15 * 128MB * 6] * 4 = 45GB
    ///
    /// Default: 0
    ///
    /// Dynamically changeable through SetDBOptions() API.
    max_total_wal_size: ?u64 = null,
    /// Maximum number of concurrent background jobs (compactions and flushes).
    ///
    /// Default: 2
    ///
    /// Dynamically changeable through SetDBOptions() API.
    max_background_jobs: ?i32 = null,

    /// Default: false
    use_adaptive_mutex: ?bool = null,

    /// Default: false
    enable_pipelined_write: ?bool = null,

    /// Convert this options to `*c.rocksdb_options_t`.
    pub fn toC(self: Options) *c.rocksdb_options_t {
        const opts = c.rocksdb_options_create();
        errdefer comptime unreachable;

        // For option `create_if_missing`, its setter function name
        // is `rocksdb_options_set_create_if_missing`.
        // All options follow this pattern, so we can generate those at comptime.
        inline for (std.meta.fields(Options)) |fld| {
            if (@field(self, fld.name)) |value| {
                const v = if (fld.type == ?bool)
                    @intFromBool(value)
                else
                    value;

                const setter = std.fmt.comptimePrint("rocksdb_options_set_{s}", .{fld.name});
                @call(.auto, @field(c, setter), .{ opts, v });
            }
        }

        return opts.?;
    }
};

/// Options that control read operations
/// https://github.com/facebook/rocksdb/blob/v9.1.1/include/rocksdb/options.h#L1550
pub const ReadOptions = struct {
    /// If true, all data read from underlying storage will be
    /// verified against corresponding checksums.
    /// Default: true
    verify_checksums: ?bool = null,
    /// Defaut: true
    fill_cache: ?bool = null,
    /// Default: false
    ignore_range_deletions: ?bool = null,
    /// Default: false
    total_order_seek: ?bool = null,
    /// Default: false
    prefix_same_as_start: ?bool = null,
    /// Default: false
    pin_data: ?bool = null,
    /// Default: false
    background_purge_on_iterator_cleanup: ?bool = null,

    pub fn toC(self: ReadOptions) *c.rocksdb_readoptions_t {
        const opts = c.rocksdb_readoptions_create();
        errdefer comptime unreachable;

        inline for (std.meta.fields(ReadOptions)) |fld| {
            if (@field(self, fld.name)) |value| {
                const v = if (fld.type == ?bool)
                    @intFromBool(value)
                else
                    value;

                const setter = std.fmt.comptimePrint("rocksdb_readoptions_set_{s}", .{fld.name});
                @call(.auto, @field(c, setter), .{ opts, v });
            }
        }
        return opts.?;
    }
};

/// Options that control write operations
/// https://github.com/facebook/rocksdb/blob/v9.1.1/include/rocksdb/options.h#L1800
pub const WriteOptions = struct {
    /// Default: false
    sync: ?bool = null,
    /// Default: false
    disable_wal: ?bool = null,
    /// Default: false
    ignore_missing_column_families: ?bool = null,
    /// Default: false
    no_slowdown: ?bool = null,
    /// Default: false
    low_pri: ?bool = null,
    /// Default: false
    memtable_insert_hint_per_batch: ?bool = null,

    pub fn toC(self: WriteOptions) *c.rocksdb_writeoptions_t {
        const opts = c.rocksdb_writeoptions_create();
        errdefer comptime unreachable;

        inline for (std.meta.fields(WriteOptions)) |fld| {
            if (@field(self, fld.name)) |value| {
                const v = if (fld.type == ?bool)
                    @intFromBool(value)
                else
                    value;

                if (comptime std.mem.eql(u8, "disable_wal", fld.name)) {
                    c.rocksdb_writeoptions_disable_WAL(opts, v);
                } else {
                    const setter = std.fmt.comptimePrint("rocksdb_writeoptions_set_{s}", .{fld.name});
                    @call(.auto, @field(c, setter), .{ opts, v });
                }
            }
        }
        return opts.?;
    }
};
