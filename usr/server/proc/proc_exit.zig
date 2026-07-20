const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");
const hash = @import("proc_hash.zig");
const fork = @import("proc_fork.zig");

pub fn sys_exit(exitcode: c_int) !void {
    const cur = ffi.global.get_curproc();
    const init = ffi.global.get_initproc();

    if (cur.p_stat == ffi.raw.SZOMB) return error.InvalidArgument;

    cur.p_stat = ffi.raw.SZOMB;
    cur.p_exitcode = exitcode;
    hash.p_remove(cur);

    const head: *ffi.List = @ptrCast(&cur.p_children);
    var n = head.first();
    while (n != head) {
        const child = n.?.entry(ffi.Proc, "p_sibling");
        n = n.?.nextNode();

        child.p_parent = init;
        const child_sibling: *ffi.List = @ptrCast(&child.p_sibling);
        const init_children: *ffi.List = @ptrCast(&init.p_children);
        child_sibling.remove();
        init_children.insert(child_sibling);
    }

    const parent = cur.p_parent;
    if (parent != null and parent.*.p_vforked != 0) {
        fork.vfork_end(parent.?);
        const err = task.prex.task_terminate(cur.p_task);
        if (err != 0) {
            task.prex.sys_panic(ffi.global.get_panic_msg());
        }
    }

    _ = task.prex.exception_raise(cur.p_parent.*.p_task, prog.signal.SIGCHLD);
}

pub fn stop(exitcode: c_int) !void {
    const cur = ffi.global.get_curproc();

    if (cur.p_stat == ffi.raw.SZOMB) return error.InvalidArgument;

    cur.p_stat = ffi.raw.SSTOP;
    cur.p_exitcode = exitcode;

    _ = task.prex.exception_raise(cur.p_parent.*.p_task, prog.signal.SIGCHLD);
}

pub fn sys_waitpid(pid: task.prex.pid_t, status: *c_int, options: c_int, retval: *task.prex.pid_t) !void {
    _ = options;
    const cur = ffi.global.get_curproc();

    const cur_children: *ffi.List = @ptrCast(&cur.p_children);
    if (cur_children.empty()) return error.NoChildProcesses;

    var pid_child: task.prex.pid_t = 0;
    var code: c_int = 0;

    const head: *ffi.List = @ptrCast(&cur.p_children);
    var n = head.first();
    while (n != head) {
        const p = n.?.entry(ffi.Proc, "p_sibling");
        n = n.?.nextNode();

        var match = false;
        if (pid > 0) {
            if (p.p_pid == pid) match = true;
        } else if (pid == 0) {
            if (p.p_pgrp.*.pg_pgid == cur.p_pgrp.*.pg_pgid) match = true;
        } else if (pid != -1) {
            if (p.p_pgrp.*.pg_pgid == -pid) match = true;
        } else {
            match = true;
        }

        if (match) {
            if (p.p_stat == ffi.raw.SSTOP) {
                pid_child = p.p_pid;
                code = p.p_exitcode;
                break;
            } else if (p.p_stat == ffi.raw.SZOMB) {
                pid_child = p.p_pid;
                code = p.p_exitcode;
                fork.cleanup(p);
                break;
            }
        }
    }

    status.* = code;
    retval.* = pid_child;
}
