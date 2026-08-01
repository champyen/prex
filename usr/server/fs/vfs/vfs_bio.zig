const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn get_buffers(idx: c_int) callconv(.c) [*c]u8;
extern fn get_buf_table() callconv(.c) [*]c.struct_buf;
extern fn get_bio_free_list() callconv(.c) *c.struct_list;
extern fn get_bio_free_sem() callconv(.c) *c.sem_t;
extern fn get_bio_lock() callconv(.c) *c.mutex_t;
extern fn get_nbufs() callconv(.c) c_int;

const has_threads = @hasDecl(c, "CONFIG_FS_THREADS") and c.CONFIG_FS_THREADS > 1;

fn bioLock() void {
    if (has_threads) {
        _ = c.mutex_lock(get_bio_lock());
    }
}

fn bioUnlock() void {
    if (has_threads) {
        _ = c.mutex_unlock(get_bio_lock());
    }
}

fn bioInsertHead(bp: *c.struct_buf) void {
    const free_list_ptr: *ffi.List = @ptrCast(get_bio_free_list());
    const bp_link: *ffi.List = @ptrCast(&bp.b_link);
    free_list_ptr.insert(bp_link);
    _ = c.sem_post(get_bio_free_sem());
}

fn bioInsertTail(bp: *c.struct_buf) void {
    const free_list_ptr: *ffi.List = @ptrCast(get_bio_free_list());
    const bp_link: *ffi.List = @ptrCast(&bp.b_link);
    const prev_node = free_list_ptr.prev.?;
    prev_node.insert(bp_link);
    _ = c.sem_post(get_bio_free_sem());
}

fn bioRemove(bp: *c.struct_buf) void {
    _ = c.sem_wait(get_bio_free_sem(), 0);
    const bp_link: *ffi.List = @ptrCast(&bp.b_link);
    bp_link.remove();
}

fn bioRemoveHead() *c.struct_buf {
    _ = c.sem_wait(get_bio_free_sem(), 0);
    const free_list_ptr: *ffi.List = @ptrCast(get_bio_free_list());
    const first_node = free_list_ptr.first().?;
    const bp: *c.struct_buf = first_node.entry(c.struct_buf, "b_link");
    const bp_link: *ffi.List = @ptrCast(&bp.b_link);
    bp_link.remove();
    return bp;
}

fn incore(dev: c.dev_t, blkno: c_int) ?*c.struct_buf {
    const nbufs = get_nbufs();
    const buf_table_ptr = get_buf_table();
    var i: c_int = 0;
    while (i < nbufs) : (i += 1) {
        const bp: *c.struct_buf = &buf_table_ptr[@intCast(i)];
        if (bp.b_blkno == blkno and bp.b_dev == dev and (bp.b_flags & c.B_INVAL) == 0) {
            return bp;
        }
    }
    return null;
}

pub export fn getblk(dev: c.dev_t, blkno: c_int) callconv(.c) ?*c.struct_buf {
    while (true) {
        bioLock();
        const core_bp = incore(dev, blkno);
        if (core_bp) |bp| {
            if ((bp.b_flags & c.B_BUSY) != 0) {
                bioUnlock();
                _ = c.mutex_lock(&bp.b_lock);
                _ = c.mutex_unlock(&bp.b_lock);
                continue;
            }
            bioRemove(bp);
            bp.b_flags |= c.B_BUSY;
            _ = c.mutex_lock(&bp.b_lock);
            bioUnlock();
            return bp;
        } else {
            const bp = bioRemoveHead();
            if ((bp.b_flags & c.B_DELWRI) != 0) {
                bioUnlock();
                _ = bwrite(bp);
                continue;
            }
            bp.b_flags = c.B_BUSY;
            bp.b_dev = dev;
            bp.b_blkno = blkno;
            _ = c.mutex_lock(&bp.b_lock);
            bioUnlock();
            return bp;
        }
    }
}

pub export fn brelse(bp: *c.struct_buf) callconv(.c) void {
    bioLock();
    bp.b_flags &= ~c.B_BUSY;
    _ = c.mutex_unlock(&bp.b_lock);
    if ((bp.b_flags & c.B_INVAL) != 0) {
        bioInsertHead(bp);
    } else {
        bioInsertTail(bp);
    }
    bioUnlock();
}

pub export fn bread(dev: c.dev_t, blkno: c_int, bpp: *?*c.struct_buf) callconv(.c) c_int {
    const bp = getblk(dev, blkno) orelse unreachable;

    if ((bp.b_flags & (c.B_DONE | c.B_DELWRI)) == 0) {
        var size: usize = c.BSIZE;
        const err = c.device_read(dev, @ptrCast(bp.b_data), &size, blkno);
        if (err != 0) {
            brelse(bp);
            return err;
        }
    }
    bp.b_flags &= ~c.B_INVAL;
    bp.b_flags |= c.B_READ | c.B_DONE;
    bpp.* = bp;
    return 0;
}

pub export fn bwrite(bp: *c.struct_buf) callconv(.c) c_int {
    bioLock();
    bp.b_flags &= ~(c.B_READ | c.B_DONE | c.B_DELWRI);
    bioUnlock();

    var size: usize = c.BSIZE;
    const err = c.device_write(bp.b_dev, @ptrCast(bp.b_data), &size, bp.b_blkno);
    if (err != 0) return err;

    bioLock();
    bp.b_flags |= c.B_DONE;
    bioUnlock();
    brelse(bp);
    return 0;
}

pub export fn bdwrite(bp: *c.struct_buf) callconv(.c) void {
    bioLock();
    bp.b_flags |= c.B_DELWRI;
    bp.b_flags &= ~c.B_DONE;
    bioUnlock();
    brelse(bp);
}

pub export fn bflush(bp: *c.struct_buf) callconv(.c) void {
    bioLock();
    if ((bp.b_flags & c.B_DELWRI) != 0) {
        _ = bwrite(bp);
    }
    bioUnlock();
}

pub export fn binval(dev: c.dev_t) callconv(.c) void {
    bioLock();
    const nbufs = get_nbufs();
    const buf_table_ptr = get_buf_table();
    var i: c_int = 0;
    while (i < nbufs) : (i += 1) {
        const bp: *c.struct_buf = &buf_table_ptr[@intCast(i)];
        if (bp.b_dev == dev) {
            if ((bp.b_flags & c.B_DELWRI) != 0) {
                _ = bwrite(bp);
            } else if ((bp.b_flags & c.B_BUSY) != 0) {
                brelse(bp);
            }
            bp.b_flags = c.B_INVAL;
        }
    }
    bioUnlock();
}

pub export fn bio_sync() callconv(.c) void {
    while (true) {
        bioLock();
        const nbufs = get_nbufs();
        const buf_table_ptr = get_buf_table();
        var done = true;
        var i: c_int = 0;
        while (i < nbufs) : (i += 1) {
            const bp: *c.struct_buf = &buf_table_ptr[@intCast(i)];
            if ((bp.b_flags & c.B_BUSY) != 0) {
                bioUnlock();
                _ = c.mutex_lock(&bp.b_lock);
                _ = c.mutex_unlock(&bp.b_lock);
                done = false;
                break;
            }
            if ((bp.b_flags & c.B_DELWRI) != 0) {
                _ = bwrite(bp);
            }
        }
        if (done) {
            bioUnlock();
            return;
        }
    }
}

pub export fn bio_init() callconv(.c) void {
    const nbufs = get_nbufs();
    const buf_table_ptr = get_buf_table();
    var i: c_int = 0;
    while (i < nbufs) : (i += 1) {
        const bp: *c.struct_buf = &buf_table_ptr[@intCast(i)];
        bp.b_flags = c.B_INVAL;
        bp.b_data = get_buffers(i);
        _ = c.mutex_init(&bp.b_lock);
        const free_list_ptr: *ffi.List = @ptrCast(get_bio_free_list());
        const bp_link: *ffi.List = @ptrCast(&bp.b_link);
        free_list_ptr.insert(bp_link);
    }
    _ = c.sem_init(get_bio_free_sem(), @as(c_uint, @intCast(nbufs)));
}
