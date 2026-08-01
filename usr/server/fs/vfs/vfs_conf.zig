const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

// Declare extern functions and variables from C filesystems
extern fn ramfs_init() callconv(.c) c_int;
extern fn devfs_init() callconv(.c) c_int;
extern fn arfs_init() callconv(.c) c_int;
extern fn fifofs_init() callconv(.c) c_int;
extern fn fatfs_init() callconv(.c) c_int;

extern var ramfs_vfsops: c.struct_vfsops;
extern var devfs_vfsops: c.struct_vfsops;
extern var arfs_vfsops: c.struct_vfsops;
extern var fifofs_vfsops: c.struct_vfsops;
extern var fatfs_vfsops: c.struct_vfsops;

// Compute vfssw length at compile time
fn countEntries() usize {
    var count: usize = 0;
    if (@hasDecl(c, "CONFIG_RAMFS")) count += 1;
    if (@hasDecl(c, "CONFIG_DEVFS")) count += 1;
    if (@hasDecl(c, "CONFIG_ARFS")) count += 1;
    if (@hasDecl(c, "CONFIG_FIFOFS")) count += 1;
    if (@hasDecl(c, "CONFIG_FATFS")) count += 1;
    return count + 1; // plus sentinel
}

// Build the array table at compile time
fn buildVfsSwTable(comptime len: usize) [len]c.struct_vfssw {
    var table: [len]c.struct_vfssw = undefined;
    var idx: usize = 0;
    if (@hasDecl(c, "CONFIG_RAMFS")) {
        table[idx] = .{
            .vs_name = @constCast("ramfs"),
            .vs_init = ramfs_init,
            .vs_op = &ramfs_vfsops,
        };
        idx += 1;
    }
    if (@hasDecl(c, "CONFIG_DEVFS")) {
        table[idx] = .{
            .vs_name = @constCast("devfs"),
            .vs_init = devfs_init,
            .vs_op = &devfs_vfsops,
        };
        idx += 1;
    }
    if (@hasDecl(c, "CONFIG_ARFS")) {
        table[idx] = .{
            .vs_name = @constCast("arfs"),
            .vs_init = arfs_init,
            .vs_op = &arfs_vfsops,
        };
        idx += 1;
    }
    if (@hasDecl(c, "CONFIG_FIFOFS")) {
        table[idx] = .{
            .vs_name = @constCast("fifofs"),
            .vs_init = fifofs_init,
            .vs_op = &fifofs_vfsops,
        };
        idx += 1;
    }
    if (@hasDecl(c, "CONFIG_FATFS")) {
        table[idx] = .{
            .vs_name = @constCast("fatfs"),
            .vs_init = fatfs_init,
            .vs_op = &fatfs_vfsops,
        };
        idx += 1;
    }
    table[idx] = .{
        .vs_name = null,
        .vs_init = c.fs_noop,
        .vs_op = null,
    };
    return table;
}

const table_len = countEntries();
pub export var vfssw: [table_len]c.struct_vfssw = buildVfsSwTable(table_len);
