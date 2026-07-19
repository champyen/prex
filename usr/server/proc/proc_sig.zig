const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("sys/capability.h");
    @cInclude("ipc/proc.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("signal.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_curproc() *c.struct_proc;
extern fn get_allproc() *c.struct_list;

extern fn p_find(c.pid_t) ?*c.struct_proc;
extern fn pg_find(c.pid_t) ?*c.struct_pgrp;

const list_t = ?*c.struct_list;

inline fn list_first(head: list_t) list_t {
    return head.?.next;
}

inline fn list_next(node: list_t) list_t {
    return node.?.next;
}

inline fn list_entry(node: list_t, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
    return @fieldParentPtr(field_name, node.?);
}

fn kill_capable() bool {
    const cur = get_curproc();
    if (c.task_chkcap(cur.p_task, c.CAP_KILL) == 0) {
        return true;
    }
    return false;
}

fn sendsig(p: *c.struct_proc, sig: c_int) c_int {
    if (p.p_pid == 0) {
        return c.EPERM;
    }

    if (p.p_pid == 1 and sig != c.SIGCHLD) {
        return c.EPERM;
    }

    return c.exception_raise(p.p_task, sig);
}

fn kill_one(pid: c.pid_t, sig: c_int) c_int {
    const p = p_find(pid) orelse return c.ESRCH;
    return sendsig(p, sig);
}

pub fn kill_pg(pgid: c.pid_t, sig: c_int) callconv(.c) c_int {
    const pgrp = pg_find(pgid) orelse return c.ESRCH;
    var error_code: c_int = 0;

    const head = &pgrp.pg_members;
    var n = list_first(head);
    while (n != head) {
        const p = list_entry(n, c.struct_proc, "p_pgrp_link");
        n = list_next(n);
        error_code = sendsig(p, sig);
        if (error_code != 0) {
            break;
        }
    }
    return error_code;
}

pub fn sys_kill(pid: c.pid_t, sig: c_int) callconv(.c) c_int {
    const cur = get_curproc();
    const all = get_allproc();

    switch (sig) {
        c.SIGFPE, c.SIGILL, c.SIGSEGV => return c.EINVAL,
        else => {},
    }

    var error_code: c_int = 0;

    if (pid > 0) {
        if (pid != cur.p_pid and !kill_capable()) {
            return c.EPERM;
        }
        error_code = kill_one(pid, sig);
    } else if (pid == -1) {
        if (!kill_capable()) {
            return c.EPERM;
        }

        var n = list_first(all);
        while (n != all) {
            const p = list_entry(n, c.struct_proc, "p_link");
            n = list_next(n);

            if (p.p_pid != 0 and p.p_pid != 1 and p.p_pid != cur.p_pid) {
                error_code = kill_one(p.p_pid, sig);
                if (error_code != 0) {
                    break;
                }
            }
        }
    } else if (pid == 0) {
        error_code = kill_pg(cur.p_pgrp.*.pg_pgid, sig);
    } else {
        if (cur.p_pgrp.*.pg_pgid != -pid and !kill_capable()) {
            return c.EPERM;
        }
        error_code = kill_pg(-pid, sig);
    }
    return error_code;
}

comptime {
    @export(&kill_pg, .{ .name = "kill_pg", .linkage = .strong });
    @export(&sys_kill, .{ .name = "sys_kill", .linkage = .strong });
}
