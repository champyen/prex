const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("ipc/proc.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("signal.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_curproc() *c.struct_proc;
extern fn get_initproc() *c.struct_proc;
extern fn get_panic_msg() [*c]const u8;

extern fn p_remove(*c.struct_proc) void;
extern fn cleanup(*c.struct_proc) void;
extern fn vfork_end(*c.struct_proc) void;

const list_t = ?*c.struct_list;

inline fn list_init(head: list_t) void {
    head.?.next = head;
    head.?.prev = head;
}

inline fn list_first(head: list_t) list_t {
    return head.?.next;
}

inline fn list_next(node: list_t) list_t {
    return node.?.next;
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

inline fn list_entry(node: list_t, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
    return @fieldParentPtr(field_name, node.?);
}

pub fn sys_exit(exitcode: c_int) callconv(.c) c_int {
    const cur = get_curproc();
    const init = get_initproc();

    if (cur.p_stat == c.SZOMB) {
        return c.EBUSY;
    }

    cur.p_stat = c.SZOMB;
    cur.p_exitcode = exitcode;
    p_remove(cur);

    const head = &cur.p_children;
    var n = list_first(head);
    while (n != head) {
        const child = list_entry(n, c.struct_proc, "p_sibling");
        n = list_next(n);

        child.p_parent = init;
        list_remove(&child.p_sibling);
        list_insert(&init.p_children, &child.p_sibling);
    }

    const parent = cur.p_parent;
    if (parent != null and parent.*.p_vforked != 0) {
        vfork_end(parent.?);
        const err = c.task_terminate(cur.p_task);
        if (err != 0) {
            c.sys_panic(get_panic_msg());
        }
    }

    _ = c.exception_raise(cur.p_parent.*.p_task, c.SIGCHLD);

    return 0;
}

pub fn stop(exitcode: c_int) callconv(.c) c_int {
    const cur = get_curproc();

    if (cur.p_stat == c.SZOMB) {
        return c.EBUSY;
    }

    cur.p_stat = c.SSTOP;
    cur.p_exitcode = exitcode;

    _ = c.exception_raise(cur.p_parent.*.p_task, c.SIGCHLD);

    return 0;
}

pub fn sys_waitpid(pid: c.pid_t, status: *c_int, options: c_int, retval: *c.pid_t) callconv(.c) c_int {
    _ = options;
    const cur = get_curproc();

    if (list_empty(&cur.p_children)) {
        return c.ECHILD;
    }

    var pid_child: c.pid_t = 0;
    var code: c_int = 0;

    var p: ?*c.struct_proc = null;
    const head = &cur.p_children;
    var n = list_first(head);
    while (n != head) {
        p = list_entry(n, c.struct_proc, "p_sibling");
        n = list_next(n);

        var match = false;
        if (pid > 0) {
            if (p.?.p_pid == pid) {
                match = true;
            }
        } else if (pid == 0) {
            if (p.?.p_pgrp.*.pg_pgid == cur.p_pgrp.*.pg_pgid) {
                match = true;
            }
        } else if (pid != -1) {
            if (p.?.p_pgrp.*.pg_pgid == -pid) {
                match = true;
            }
        } else {
            match = true;
        }

        if (match) {
            if (p.?.p_stat == c.SSTOP) {
                pid_child = p.?.p_pid;
                code = p.?.p_exitcode;
                break;
            } else if (p.?.p_stat == c.SZOMB) {
                pid_child = p.?.p_pid;
                code = p.?.p_exitcode;
                cleanup(p.?);
                break;
            }
        }
    }

    status.* = code;
    retval.* = pid_child;
    return 0;
}

comptime {
    @export(&sys_exit, .{ .name = "sys_exit", .linkage = .strong });
    @export(&stop, .{ .name = "stop", .linkage = .strong });
    @export(&sys_waitpid, .{ .name = "sys_waitpid", .linkage = .strong });
}
