const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("ipc/proc.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_curproc() *c.struct_proc;
extern fn p_find(c.pid_t) ?*c.struct_proc;
extern fn pg_find(c.pid_t) ?*c.struct_pgrp;
extern fn pg_add(*c.struct_pgrp) void;
extern fn pg_remove(*c.struct_pgrp) void;

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

inline fn list_empty(head: list_t) bool {
    return head.?.next == head;
}

pub fn sys_getpid() callconv(.c) c.pid_t {
    return get_curproc().p_pid;
}

pub fn sys_getppid() callconv(.c) c.pid_t {
    return get_curproc().p_parent.*.p_pid;
}

pub fn sys_getpgid(pid: c.pid_t, retval: *c.pid_t) callconv(.c) c_int {
    var p: *c.struct_proc = undefined;
    if (pid == 0) {
        p = get_curproc();
    } else {
        if (p_find(pid)) |found| {
            p = found;
        } else {
            return c.ESRCH;
        }
    }
    retval.* = p.p_pgrp.*.pg_pgid;
    return 0;
}

pub fn sys_getsid(pid: c.pid_t, retval: *c.pid_t) callconv(.c) c_int {
    var p: *c.struct_proc = undefined;
    if (pid == 0) {
        p = get_curproc();
    } else {
        if (p_find(pid)) |found| {
            p = found;
        } else {
            return c.ESRCH;
        }
    }
    const leader = p.p_pgrp.*.pg_session.*.s_leader;
    retval.* = leader.*.p_pid;
    return 0;
}

pub fn enterpgrp(p: *c.struct_proc, pgid: c.pid_t) callconv(.c) c_int {
    var pgrp: *c.struct_pgrp = undefined;
    if (pg_find(pgid)) |found| {
        pgrp = found;
    } else {
        const mem = c.malloc(@sizeOf(c.struct_pgrp)) orelse return c.ENOMEM;
        pgrp = @ptrCast(@alignCast(mem));
        @memset(@as([*]u8, @ptrCast(pgrp))[0..@sizeOf(c.struct_pgrp)], 0);
        list_init(&pgrp.pg_members);
        pgrp.pg_pgid = pgid;
        pg_add(pgrp);
    }
    list_remove(&p.p_pgrp_link);
    list_insert(&pgrp.pg_members, &p.p_pgrp_link);
    pgrp.pg_session = get_curproc().p_pgrp.*.pg_session;
    p.p_pgrp = pgrp;
    return 0;
}

pub fn leavepgrp(p: *c.struct_proc) callconv(.c) c_int {
    const pgrp = p.p_pgrp.?;
    list_remove(&p.p_pgrp_link);
    if (list_empty(&pgrp.*.pg_members)) {
        pg_remove(pgrp);
        c.free(pgrp);
    }
    p.p_pgrp = null;
    return 0;
}

pub fn sys_setpgid(pid: c.pid_t, pgid_in: c.pid_t) callconv(.c) c_int {
    var p: *c.struct_proc = undefined;
    var pgid = pgid_in;
    if (pid == 0) {
        p = get_curproc();
    } else {
        if (p_find(pid)) |found| {
            p = found;
        } else {
            return c.ESRCH;
        }
    }
    if (pgid < 0) {
        return c.EINVAL;
    }
    if (pgid == 0) {
        pgid = p.p_pid;
    }
    if (p.p_pgrp.*.pg_pgid == pgid) {
        return 0;
    }
    return enterpgrp(p, pgid);
}

pub fn sys_setsid(retval: *c.pid_t) callconv(.c) c_int {
    const p = get_curproc();
    if (p.p_pid == p.p_pgrp.*.pg_pgid) {
        return c.EPERM;
    }
    const mem = c.malloc(@sizeOf(c.struct_session)) orelse return c.ENOMEM;
    const sess: *c.struct_session = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(sess))[0..@sizeOf(c.struct_session)], 0);

    const err = enterpgrp(p, p.p_pid);
    if (err != 0) {
        c.free(sess);
        return err;
    }
    const pgrp = p.p_pgrp.?;
    sess.s_refcnt = 1;
    sess.s_leader = p;
    sess.s_ttyhold = 0;
    pgrp.*.pg_session = sess;

    retval.* = p.p_pid;
    return 0;
}

comptime {
    @export(&sys_getpid, .{ .name = "sys_getpid", .linkage = .strong });
    @export(&sys_getppid, .{ .name = "sys_getppid", .linkage = .strong });
    @export(&sys_getpgid, .{ .name = "sys_getpgid", .linkage = .strong });
    @export(&sys_getsid, .{ .name = "sys_getsid", .linkage = .strong });
    @export(&enterpgrp, .{ .name = "enterpgrp", .linkage = .strong });
    @export(&leavepgrp, .{ .name = "leavepgrp", .linkage = .strong });
    @export(&sys_setpgid, .{ .name = "sys_setpgid", .linkage = .strong });
    @export(&sys_setsid, .{ .name = "sys_setsid", .linkage = .strong });
}
