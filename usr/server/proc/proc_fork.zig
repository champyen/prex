const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");
const hash = @import("proc_hash.zig");

fn pid_alloc() !task.prex.pid_t {
    var pid = ffi.global.get_last_pid() +% 1;
    if (pid >= ffi.raw.PID_MAX) pid = 1;
    const orig_last = ffi.global.get_last_pid();
    while (pid != orig_last) {
        if (hash.p_find(pid) == null) break;
        pid = pid +% 1;
        if (pid >= ffi.raw.PID_MAX) pid = 1;
    }
    if (pid == orig_last) return error.ResourceLimit;
    ffi.global.set_last_pid(pid);
    return pid;
}

pub fn newproc(p: *ffi.Proc, pid_in: task.prex.pid_t, t: task.prex.task_t) !void {
    var pid = pid_in;
    const pg = ffi.global.get_curproc().p_pgrp.?;

    if (pid == 0) {
        pid = try pid_alloc();
    }

    p.p_parent = ffi.global.get_curproc();
    p.p_pgrp = pg;
    p.p_stat = ffi.raw.SRUN;
    p.p_exitcode = 0;
    p.p_pid = pid;
    p.p_task = t;
    p.p_vforked = 0;
    p.p_invfork = 0;

    const children: *ffi.List = @ptrCast(&p.p_children);
    children.init();
    hash.p_add(p);
    const parent_children: *ffi.List = @ptrCast(&ffi.global.get_curproc().p_children);
    const sibling: *ffi.List = @ptrCast(&p.p_sibling);
    parent_children.insert(sibling);
    const pg_members: *ffi.List = @ptrCast(&pg.*.pg_members);
    const pgrp_link: *ffi.List = @ptrCast(&p.p_pgrp_link);
    pg_members.insert(pgrp_link);
    const allproc: *ffi.List = @ptrCast(ffi.global.get_allproc());
    const p_link: *ffi.List = @ptrCast(&p.p_link);
    allproc.insert(p_link);
}

pub fn sys_fork(child: task.prex.task_t, vfork: c_int) !task.prex.pid_t {
    if (vfork != 0 and ffi.global.get_curproc().p_invfork != 0) return error.InvalidArgument;
    if (hash.task_to_proc(child) != null) return error.InvalidArgument;

    const p = ffi.allocZeroed(ffi.Proc) orelse return error.OutOfMemory;
    errdefer prog.stdlib.free(p);

    try newproc(p, 0, child);

    if (vfork != 0) {
        vfork_start(ffi.global.get_curproc());
        p.p_invfork = 1;
    }

    return p.p_pid;
}

pub fn cleanup(p: *ffi.Proc) void {
    const sibling: *ffi.List = @ptrCast(&p.p_sibling);
    const pgrp_link: *ffi.List = @ptrCast(&p.p_pgrp_link);
    const p_link: *ffi.List = @ptrCast(&p.p_link);
    sibling.remove();
    pgrp_link.remove();
    p_link.remove();
    prog.stdlib.free(p);
}

fn vfork_start(p: *ffi.Proc) void {
    if (!@hasDecl(task.prex, "CONFIG_MMU")) {
        p.p_stacksaved = null;
    }
    p.p_vforked = 1;
}

pub fn vfork_end(p: *ffi.Proc) void {
    if (!@hasDecl(task.prex, "CONFIG_MMU")) {
        if (p.p_stacksaved != null) {
            _ = prog.string.memcpy(p.p_stackbase, p.p_stacksaved, ffi.raw.DFLSTKSZ);
            _ = task.prex.vm_free(p.p_task, p.p_stacksaved);
        }
    }
    p.p_vforked = 0;
    _ = task.prex.task_resume(p.p_task);
}
