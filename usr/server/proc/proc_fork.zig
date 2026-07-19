const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("ipc/proc.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_curproc() *c.struct_proc;
extern fn get_allproc() *c.struct_list;
extern fn get_last_pid() c.pid_t;
extern fn set_last_pid(c.pid_t) void;

extern fn p_find(c.pid_t) ?*c.struct_proc;
extern fn task_to_proc(c.task_t) ?*c.struct_proc;
extern fn p_add(*c.struct_proc) void;

const list_t = ?*c.struct_list;

inline fn list_init(head: list_t) void {
    head.?.next = head;
    head.?.prev = head;
}

inline fn list_insert(prev: list_t, node: list_t) void {
    const n = node.?;
    const p = prev.?;
    n.next = p.next;
    n.prev = p;
    p.next.*.prev = node.?;
    p.next = node.?;
}

inline fn list_remove(node: list_t) void {
    const n = node.?;
    n.prev.*.next = n.next;
    n.next.*.prev = n.prev;
}

fn pid_alloc() c.pid_t {
    var pid = get_last_pid() +% 1;
    if (pid >= c.PID_MAX) {
        pid = 1;
    }
    const orig_last = get_last_pid();
    while (pid != orig_last) {
        if (p_find(pid) == null) {
            break;
        }
        pid = pid +% 1;
        if (pid >= c.PID_MAX) {
            pid = 1;
        }
    }
    if (pid == orig_last) {
        return 0;
    }
    set_last_pid(pid);
    return pid;
}

pub fn newproc(p: *c.struct_proc, pid_in: c.pid_t, task: c.task_t) callconv(.c) c_int {
    var pid = pid_in;
    const pg = get_curproc().p_pgrp.?;

    if (pid == 0) {
        pid = pid_alloc();
        if (pid == 0) {
            return c.EAGAIN;
        }
    }

    p.p_parent = get_curproc();
    p.p_pgrp = pg;
    p.p_stat = c.SRUN;
    p.p_exitcode = 0;
    p.p_pid = pid;
    p.p_task = task;
    p.p_vforked = 0;
    p.p_invfork = 0;

    list_init(&p.p_children);
    p_add(p);
    list_insert(&get_curproc().p_children, &p.p_sibling);
    list_insert(&pg.*.pg_members, &p.p_pgrp_link);
    list_insert(get_allproc(), &p.p_link);

    return 0;
}

pub fn sys_fork(child: c.task_t, vfork: c_int, retval: *c.pid_t) callconv(.c) c_int {
    if (vfork != 0 and get_curproc().p_invfork != 0) {
        return c.EINVAL;
    }

    if (task_to_proc(child) != null) {
        return c.EINVAL;
    }

    const mem = c.malloc(@sizeOf(c.struct_proc)) orelse return c.ENOMEM;
    const p: *c.struct_proc = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(c.struct_proc)], 0);

    const err = newproc(p, 0, child);
    if (err != 0) {
        c.free(p);
        return err;
    }

    if (vfork != 0) {
        _ = vfork_start(get_curproc());
        p.p_invfork = 1;
    }

    retval.* = p.p_pid;
    return 0;
}

pub fn cleanup(p: *c.struct_proc) callconv(.c) void {
    list_remove(&p.p_sibling);
    list_remove(&p.p_pgrp_link);
    list_remove(&p.p_link);
    c.free(p);
}

fn vfork_start(p: *c.struct_proc) c_int {
    if (!@hasDecl(c, "CONFIG_MMU")) {
        p.p_stacksaved = null;
    }
    p.p_vforked = 1;
    return 0;
}

pub fn vfork_end(p: *c.struct_proc) callconv(.c) void {
    if (!@hasDecl(c, "CONFIG_MMU")) {
        if (p.p_stacksaved != null) {
            _ = c.memcpy(p.p_stackbase, p.p_stacksaved, c.DFLSTKSZ);
            _ = c.vm_free(p.p_task, p.p_stacksaved);
        }
    }
    p.p_vforked = 0;
    _ = c.task_resume(p.p_task);
}

comptime {
    @export(&newproc, .{ .name = "newproc", .linkage = .strong });
    @export(&sys_fork, .{ .name = "sys_fork", .linkage = .strong });
    @export(&cleanup, .{ .name = "cleanup", .linkage = .strong });
    @export(&vfork_end, .{ .name = "vfork_end", .linkage = .strong });
}
