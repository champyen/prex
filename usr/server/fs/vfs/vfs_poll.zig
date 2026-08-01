const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn get_poll_list() callconv(.c) *c.struct_list;

pub export fn sys_poll_register(
    t: ?*c.struct_task,
    sem: ffi.task.prex.sem_t,
    nfds: c_int,
    fds: [*c]c.struct_poll_entry,
) callconv(.c) c_int {
    const list_head: *ffi.List = @ptrCast(get_poll_list());
    const raw_poll_list = get_poll_list();
    if (raw_poll_list.next == null) {
        list_head.init();
    }

    var i: c_int = 0;
    while (i < nfds) : (i += 1) {
        const fp_raw = c.task_getfp(t, fds[@intCast(i)].fd);
        if (fp_raw == null) return ffi.prog.errno.EBADF;
        const fp: *c.struct_file = @ptrCast(fp_raw);

        const pl = ffi.prog.stdlib.malloc(@sizeOf(c.struct_poll_listener)) orelse return ffi.prog.errno.ENOMEM;
        const listener: *c.struct_poll_listener = @ptrCast(@alignCast(pl));

        listener.sem = sem;
        listener.events = fds[@intCast(i)].events;
        listener.vp = fp.f_vnode;

        // Initialize list links
        const link: *ffi.List = @ptrCast(&listener.link);
        const g_link: *ffi.List = @ptrCast(&listener.g_link);
        link.init();
        g_link.init();

        const vp = fp.f_vnode;
        c.vnode_poll_register(vp, listener);

        // Add to global poll list
        list_head.insert(g_link);
    }
    return 0;
}

pub export fn sys_poll_deregister(
    t: ?*c.struct_task,
    sem: ffi.task.prex.sem_t,
) callconv(.c) c_int {
    _ = t;
    const list_head: *ffi.List = @ptrCast(get_poll_list());
    const raw_poll_list = get_poll_list();
    if (raw_poll_list.next == null) {
        list_head.init();
    }

    var n = list_head.next;
    while (n != list_head) {
        const next_node = n.?.next;
        const pl = n.?.entry(c.struct_poll_listener, "g_link");
        if (pl.sem == sem) {
            c.vnode_poll_deregister(pl.vp, pl);
            const g_link: *ffi.List = @ptrCast(&pl.g_link);
            g_link.remove();
            ffi.prog.stdlib.free(pl);
        }
        n = next_node;
    }
    return 0;
}

pub export fn sys_poll_query(
    t: ?*c.struct_task,
    nfds: c_int,
    fds: [*c]c.struct_poll_entry,
) callconv(.c) c_int {
    var ready: c_int = 0;
    var i: c_int = 0;
    while (i < nfds) : (i += 1) {
        const fp_raw = c.task_getfp(t, fds[@intCast(i)].fd);
        if (fp_raw == null) {
            fds[@intCast(i)].revents = c.POLLNVAL;
            ready += 1;
            continue;
        }
        const fp: *c.struct_file = @ptrCast(fp_raw);
        const vp = fp.f_vnode;
        const revents = ffi.VOP_POLL(vp, fp, fds[@intCast(i)].events);
        if (revents != 0) {
            fds[@intCast(i)].revents = @intCast(revents);
            ready += 1;
        } else {
            fds[@intCast(i)].revents = 0;
        }
    }
    return ready;
}
