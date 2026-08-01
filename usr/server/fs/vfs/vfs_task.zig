const ffi = @import("fs_ffi.zig");
const c = ffi.raw;
const std = @import("std");

const TASK_MAXBUCKETS = 32;

fn TASKHASH(x: c.task_t) usize {
    return @intCast(x & (TASK_MAXBUCKETS - 1));
}

// FFI getters for global tables/locks to avoid NOMMU XIP relocation mismatch
extern fn get_task_table() callconv(.c) [*]c.struct_list;
extern fn get_task_lock() callconv(.c) *c.mutex_t;

const has_threads = @hasDecl(c, "CONFIG_FS_THREADS") and c.CONFIG_FS_THREADS > 1;

fn lockTaskTable() void {
    if (has_threads) {
        _ = c.mutex_lock(get_task_lock());
    }
}

fn unlockTaskTable() void {
    if (has_threads) {
        _ = c.mutex_unlock(get_task_lock());
    }
}

extern fn sec_file_permission(task: c.task_t, path: [*c]const u8, acc: c_int) callconv(.c) c_int;

pub export fn task_lookup(task: c.task_t) callconv(.c) ?*c.struct_task {
    if (task == 0) return null;

    lockTaskTable();
    const task_table = get_task_table();
    const bucket = TASKHASH(task);
    const list_head: *ffi.List = @ptrCast(&task_table[bucket]);
    var n = list_head.next;
    while (n != list_head) {
        const next_node = n.?.next;
        const t = n.?.entry(c.struct_task, "t_link");
        if (t.t_taskid == task) {
            unlockTaskTable();
            _ = c.mutex_lock(&t.t_lock);
            return t;
        }
        n = next_node;
    }
    unlockTaskTable();
    return null;
}

pub export fn task_alloc(task: c.task_t, pt: [*c]?*c.struct_task) callconv(.c) c_int {
    if (task_lookup(task) != null) return ffi.prog.errno.EINVAL;

    const mem = ffi.prog.stdlib.malloc(@sizeOf(c.struct_task)) orelse return ffi.prog.errno.ENOMEM;
    const t: *c.struct_task = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(t))[0..@sizeOf(c.struct_task)], 0);

    t.t_taskid = task;
    _ = ffi.prog.string.strlcpy(@ptrCast(&t.t_cwd), "/", @sizeOf(@TypeOf(t.t_cwd)));

    if (has_threads) {
        _ = c.mutex_init(&t.t_lock);
    }

    const link: *ffi.List = @ptrCast(&t.t_link);
    link.init();

    lockTaskTable();
    const task_table = get_task_table();
    const bucket = TASKHASH(task);
    const list_head: *ffi.List = @ptrCast(&task_table[bucket]);
    list_head.insert(link);
    unlockTaskTable();

    pt.* = t;
    return 0;
}

pub export fn task_free(t: ?*c.struct_task) callconv(.c) void {
    if (t) |task_ptr| {
        lockTaskTable();
        const link: *ffi.List = @ptrCast(&task_ptr.t_link);
        link.remove();
        _ = c.mutex_unlock(&task_ptr.t_lock);
        if (has_threads) {
            _ = c.mutex_destroy(&task_ptr.t_lock);
        }
        ffi.prog.stdlib.free(task_ptr);
        unlockTaskTable();
    }
}

pub export fn task_setid(t: ?*c.struct_task, task: c.task_t) callconv(.c) void {
    if (t) |task_ptr| {
        lockTaskTable();
        const link: *ffi.List = @ptrCast(&task_ptr.t_link);
        link.remove();
        task_ptr.t_taskid = task;
        const task_table = get_task_table();
        const bucket = TASKHASH(task);
        const list_head: *ffi.List = @ptrCast(&task_table[bucket]);
        list_head.insert(link);
        unlockTaskTable();
    }
}

pub export fn task_unlock(t: ?*c.struct_task) callconv(.c) void {
    if (t) |task_ptr| {
        _ = c.mutex_unlock(&task_ptr.t_lock);
    }
}

pub export fn task_getfp(t: ?*c.struct_task, fd: c_int) callconv(.c) c.file_t {
    if (t) |task_ptr| {
        if (fd < 0 or fd >= c.OPEN_MAX) return null;
        return task_ptr.t_ofile[@intCast(fd)];
    }
    return null;
}

pub export fn task_setfp(t: ?*c.struct_task, fd: c_int, fp: c.file_t) callconv(.c) void {
    if (t) |task_ptr| {
        if (fd >= 0 and fd < c.OPEN_MAX) {
            task_ptr.t_ofile[@intCast(fd)] = fp;
        }
    }
}

pub export fn task_newfd(t: ?*c.struct_task) callconv(.c) c_int {
    if (t) |task_ptr| {
        var fd: c_int = 0;
        while (fd < c.OPEN_MAX) : (fd += 1) {
            if (task_ptr.t_ofile[@intCast(fd)] == null) return fd;
        }
    }
    return -1;
}

pub export fn task_delfd(t: ?*c.struct_task, fd: c_int) callconv(.c) void {
    if (t) |task_ptr| {
        if (fd >= 0 and fd < c.OPEN_MAX) {
            task_ptr.t_ofile[@intCast(fd)] = null;
        }
    }
}

pub export fn task_conv(t: ?*c.struct_task, path: [*c]u8, acc: c_int, full: [*c]u8) callconv(.c) c_int {
    const task_ptr = t orelse return ffi.prog.errno.EINVAL;
    const cwd: [*c]u8 = @ptrCast(&task_ptr.t_cwd);

    path[c.PATH_MAX - 1] = 0;
    const path_len = ffi.prog.string.strlen(path);
    if (path_len >= c.PATH_MAX) return ffi.prog.errno.ENAMETOOLONG;

    const cwd_len = ffi.prog.string.strlen(cwd);
    if (cwd_len + path_len >= c.PATH_MAX) return ffi.prog.errno.ENAMETOOLONG;

    var src = path;
    var tgt = full;
    const end = path + path_len;

    if (path[0] == '/') {
        tgt[0] = src[0];
        tgt += 1;
        src += 1;
    } else {
        _ = ffi.prog.string.strlcpy(full, cwd, c.PATH_MAX);
        tgt += cwd_len;
        if (cwd_len > 1 and path[0] != '.') {
            tgt[0] = '/';
            tgt += 1;
        }
    }

    while (src[0] != 0) {
        var p = src;
        while (p[0] != '/' and p[0] != 0) : (p += 1) {}
        const is_end = (p == end);
        p[0] = 0;

        if (ffi.prog.string.strcmp(src, "..") == 0) {
            const full_addr = @intFromPtr(full);
            if (@intFromPtr(tgt) > full_addr + 1) {
                tgt -= 1;
                while (@intFromPtr(tgt) > full_addr and (tgt - 1)[0] != '/') : (tgt -= 1) {}
            }
        } else if (ffi.prog.string.strcmp(src, ".") == 0) {
            // Ignore "."
        } else {
            while (src[0] != 0) : (src += 1) {
                tgt[0] = src[0];
                tgt += 1;
            }
        }

        if (is_end) break;

        const full_addr = @intFromPtr(full);
        if (@intFromPtr(tgt) > full_addr and (tgt - 1)[0] != '/') {
            tgt[0] = '/';
            tgt += 1;
        }
        src = p + 1;
    }
    tgt[0] = 0;

    return sec_file_permission(task_ptr.t_taskid, full, acc);
}

pub export fn task_dump() callconv(.c) void {
    lockTaskTable();
    c.dprintf("Dump file data\n");
    c.dprintf(" task     opens   cwd\n");
    c.dprintf(" -------- ------- ------------------------------\n");
    var i: usize = 0;
    const task_table = get_task_table();
    while (i < TASK_MAXBUCKETS) : (i += 1) {
        const list_head: *ffi.List = @ptrCast(&task_table[i]);
        var n = list_head.next;
        while (n != list_head) {
            const next_node = n.?.next;
            const t = n.?.entry(c.struct_task, "t_link");
            c.dprintf(" %08x %7x %s\n", @as(c_int, @intCast(t.t_taskid)), t.t_nopens, @as([*c]const u8, @ptrCast(&t.t_cwd)));
            n = next_node;
        }
    }
    c.dprintf("\n");
    unlockTaskTable();
}

pub export fn task_init() callconv(.c) void {
    var i: usize = 0;
    const task_table = get_task_table();
    while (i < TASK_MAXBUCKETS) : (i += 1) {
        const head: *ffi.List = @ptrCast(&task_table[i]);
        head.init();
    }
}
