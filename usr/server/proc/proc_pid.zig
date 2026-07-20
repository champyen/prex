const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");
const hash = @import("proc_hash.zig");

pub fn sys_getpid() task.prex.pid_t {
    return ffi.global.get_curproc().p_pid;
}

pub fn sys_getppid() !task.prex.pid_t {
    const p = ffi.global.get_curproc();
    if (p.p_parent == null) return error.InvalidArgument;
    return p.p_parent.*.p_pid;
}

pub fn sys_getpgid(pid: task.prex.pid_t, retval: *task.prex.pid_t) !void {
    const p = if (pid == 0) ffi.global.get_curproc() else (hash.p_find(pid) orelse return error.NotFound);
    retval.* = p.p_pgrp.*.pg_pgid;
}

pub fn sys_getsid(pid: task.prex.pid_t, retval: *task.prex.pid_t) !void {
    const p = if (pid == 0) ffi.global.get_curproc() else (hash.p_find(pid) orelse return error.NotFound);
    const leader = p.p_pgrp.*.pg_session.*.s_leader;
    retval.* = leader.*.p_pid;
}

pub fn enterpgrp(p: *ffi.Proc, pgid: task.prex.pid_t) !void {
    const pgrp = if (hash.pg_find(pgid)) |found| found else blk: {
        const new = ffi.allocZeroed(ffi.Pgrp) orelse return error.OutOfMemory;
        const members: *ffi.List = @ptrCast(&new.pg_members);
        members.init();
        new.pg_pgid = pgid;
        hash.pg_add(new);
        break :blk new;
    };
    const pgrp_link: *ffi.List = @ptrCast(&p.p_pgrp_link);
    const members: *ffi.List = @ptrCast(&pgrp.pg_members);
    pgrp_link.remove();
    members.insert(pgrp_link);
    pgrp.pg_session = ffi.global.get_curproc().p_pgrp.*.pg_session;
    p.p_pgrp = pgrp;
}

pub fn leavepgrp(p: *ffi.Proc) void {
    const pgrp = p.p_pgrp orelse return;
    const pgrp_link: *ffi.List = @ptrCast(&p.p_pgrp_link);
    const members: *ffi.List = @ptrCast(&pgrp.pg_members);
    pgrp_link.remove();
    if (members.empty()) {
        hash.pg_remove(pgrp);
        prog.stdlib.free(pgrp);
    }
    p.p_pgrp = null;
}

pub fn sys_setpgid(pid: task.prex.pid_t, pgid_in: task.prex.pid_t) !void {
    var pgid = pgid_in;
    const p = if (pid == 0) ffi.global.get_curproc() else (hash.p_find(pid) orelse return error.NotFound);
    if (pgid < 0) return error.InvalidArgument;
    if (pgid == 0) pgid = p.p_pid;
    if (p.p_pgrp.*.pg_pgid == pgid) return;
    try enterpgrp(p, pgid);
}

pub fn sys_setsid(retval: *task.prex.pid_t) !void {
    const p = ffi.global.get_curproc();
    if (p.p_pid == p.p_pgrp.*.pg_pgid) return error.PermissionDenied;

    const sess = ffi.allocZeroed(ffi.Session) orelse return error.OutOfMemory;
    errdefer prog.stdlib.free(sess);

    try enterpgrp(p, p.p_pid);
    const pgrp = p.p_pgrp.?;
    sess.s_refcnt = 1;
    sess.s_leader = p;
    sess.s_ttyhold = 0;
    pgrp.*.pg_session = sess;

    retval.* = p.p_pid;
}
