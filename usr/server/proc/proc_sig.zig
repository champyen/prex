const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");
const hash = @import("proc_hash.zig");

fn kill_capable() bool {
    const cur = ffi.global.get_curproc();
    return task.prex.task_chkcap(cur.p_task, prog.capsys.CAP_KILL) == 0;
}

fn sendsig(p: *ffi.Proc, sig: c_int) !void {
    if (p.p_pid == 0) return error.PermissionDenied;
    if (p.p_pid == 1 and sig != prog.signal.SIGCHLD) return error.PermissionDenied;

    const rc = task.prex.exception_raise(p.p_task, sig);
    if (rc != 0) return error.Unexpected;
}

fn kill_one(pid: task.prex.pid_t, sig: c_int) !void {
    const p = hash.p_find(pid) orelse return error.NotFound;
    try sendsig(p, sig);
}

pub fn kill_pg(pgid: task.prex.pid_t, sig: c_int) !void {
    const pgrp = hash.pg_find(pgid) orelse return error.NotFound;

    const head: *ffi.List = @ptrCast(&pgrp.pg_members);
    var n = head.first();
    while (n != head) {
        const p = n.?.entry(ffi.Proc, "p_pgrp_link");
        n = n.?.nextNode();
        try sendsig(p, sig);
    }
}

pub fn sys_kill(pid: task.prex.pid_t, sig: c_int) !void {
    const cur = ffi.global.get_curproc();
    const all = ffi.global.get_allproc();

    switch (sig) {
        prog.signal.SIGFPE, prog.signal.SIGILL, prog.signal.SIGSEGV => return error.InvalidArgument,
        else => {},
    }

    if (pid > 0) {
        if (pid != cur.p_pid and !kill_capable()) return error.PermissionDenied;
        try kill_one(pid, sig);
    } else if (pid == -1) {
        if (!kill_capable()) return error.PermissionDenied;

        const all_list: *ffi.List = @ptrCast(all);
        var n = all_list.first();
        while (n != all_list) {
            const p = n.?.entry(ffi.Proc, "p_link");
            n = n.?.nextNode();

            if (p.p_pid != 0 and p.p_pid != 1 and p.p_pid != cur.p_pid) {
                try kill_one(p.p_pid, sig);
            }
        }
    } else if (pid == 0) {
        try kill_pg(cur.p_pgrp.*.pg_pgid, sig);
    } else {
        if (cur.p_pgrp.*.pg_pgid != -pid and !kill_capable()) return error.PermissionDenied;
        try kill_pg(-pid, sig);
    }
}
