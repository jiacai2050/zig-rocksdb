pub const c = @cImport({
    @cInclude("rocksdb/c.h");
});

const Self = @This();

c_handle: *c.rocksdb_column_family_handle_t,

pub fn init(c_handle: *c.rocksdb_column_family_handle_t) Self {
    return Self{
        .c_handle = c_handle,
    };
}

pub fn deinit(self: Self) void {
    c.rocksdb_column_family_handle_destroy(self.c_handle);
}
