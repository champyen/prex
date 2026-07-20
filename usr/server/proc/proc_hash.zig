const ffi = @import("ffi.zig");
const task = @import("task");

pub fn p_find(pid: task.prex.pid_t) ?*ffi.Proc {
    const head = &ffi.global.get_pid_table()[ffi.idHash(pid)];
    var n = head.first();
    while (n != head) {
        const p = n.?.entry(ffi.Proc, "p_pid_link");
        if (p.p_pid == pid) return p;
        n = n.?.nextNode();
    }
    return null;
}

pub fn pg_find(pgid: task.prex.pid_t) ?*ffi.Pgrp {
    const head = &ffi.global.get_pgid_table()[ffi.idHash(pgid)];
    var n = head.first();
    while (n != head) {
        const g = n.?.entry(ffi.Pgrp, "pg_link");
        if (g.pg_pgid == pgid) return g;
        n = n.?.nextNode();
    }
    return null;
}

pub fn task_to_proc(t: task.prex.task_t) ?*ffi.Proc {
    const head = &ffi.global.get_task_table()[ffi.idHash(t)];
    var n = head.first();
    while (n != head) {
        const p = n.?.entry(ffi.Proc, "p_task_link");
        if (p.p_task == t) return p;
        n = n.?.nextNode();
    }
    return null;
}

pub fn p_add(p: *ffi.Proc) void {
    const pid_head = &ffi.global.get_pid_table()[ffi.idHash(p.p_pid)];
    const task_head = &ffi.global.get_task_table()[ffi.idHash(p.p_task)];
    const pid_link: *ffi.List = @ptrCast(&p.p_pid_link);
    const task_link: *ffi.List = @ptrCast(&p.p_task_link);
    pid_head.insert(pid_link);
    task_head.insert(task_link);
}

pub fn p_remove(p: *ffi.Proc) void {
    const pid_link: *ffi.List = @ptrCast(&p.p_pid_link);
    const task_link: *ffi.List = @ptrCast(&p.p_task_link);
    pid_link.remove();
    task_link.remove();
}

pub fn pg_add(pgrp: *ffi.Pgrp) void {
    const pg_head = &ffi.global.get_pgid_table()[ffi.idHash(pgrp.pg_pgid)];
    const pg_link: *ffi.List = @ptrCast(&pgrp.pg_link);
    pg_head.insert(pg_link);
}

pub fn pg_remove(pgrp: *ffi.Pgrp) void {
    const pg_link: *ffi.List = @ptrCast(&pgrp.pg_link);
    pg_link.remove();
}
