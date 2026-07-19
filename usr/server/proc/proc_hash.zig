const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("sys/list.h");
    @cInclude("ipc/ipc.h");
    @cInclude("unistd.h");
    @cInclude("usr/server/proc/proc.h");
});

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

inline fn list_entry(node: list_t, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
    return @fieldParentPtr(field_name, node.?);
}

const ID_MAXBUCKETS = 32;
inline fn IDHASH(x: anytype) usize {
    const uval: u32 = @bitCast(x);
    return @as(usize, uval) & (ID_MAXBUCKETS - 1);
}

extern fn get_pid_table() *[ID_MAXBUCKETS]c.struct_list;
extern fn get_task_table() *[ID_MAXBUCKETS]c.struct_list;
extern fn get_pgid_table() *[ID_MAXBUCKETS]c.struct_list;

pub fn p_find(pid: c.pid_t) callconv(.c) ?*c.struct_proc {
    const head = &get_pid_table()[IDHASH(pid)];
    var n = list_first(head);
    while (n != head) {
        const p = list_entry(n, c.struct_proc, "p_pid_link");
        if (p.p_pid == pid) return p;
        n = list_next(n);
    }
    return null;
}

pub fn pg_find(pgid: c.pid_t) callconv(.c) ?*c.struct_pgrp {
    const head = &get_pgid_table()[IDHASH(pgid)];
    var n = list_first(head);
    while (n != head) {
        const g = list_entry(n, c.struct_pgrp, "pg_link");
        if (g.pg_pgid == pgid) return g;
        n = list_next(n);
    }
    return null;
}

pub fn task_to_proc(task: c.task_t) callconv(.c) ?*c.struct_proc {
    const head = &get_task_table()[IDHASH(task)];
    var n = list_first(head);
    while (n != head) {
        const p = list_entry(n, c.struct_proc, "p_task_link");
        if (p.p_task == task) return p;
        n = list_next(n);
    }
    return null;
}

pub fn p_add(p: *c.struct_proc) callconv(.c) void {
    list_insert(&get_pid_table()[IDHASH(p.p_pid)], &p.p_pid_link);
    list_insert(&get_task_table()[IDHASH(p.p_task)], &p.p_task_link);
}

pub fn p_remove(p: *c.struct_proc) callconv(.c) void {
    list_remove(&p.p_pid_link);
    list_remove(&p.p_task_link);
}

pub fn pg_add(pgrp: *c.struct_pgrp) callconv(.c) void {
    list_insert(&get_pgid_table()[IDHASH(pgrp.pg_pgid)], &pgrp.pg_link);
}

pub fn pg_remove(pgrp: *c.struct_pgrp) callconv(.c) void {
    list_remove(&pgrp.pg_link);
}

comptime {
    @export(&p_find, .{ .name = "p_find", .linkage = .strong });
    @export(&pg_find, .{ .name = "pg_find", .linkage = .strong });
    @export(&task_to_proc, .{ .name = "task_to_proc", .linkage = .strong });
    @export(&p_add, .{ .name = "p_add", .linkage = .strong });
    @export(&p_remove, .{ .name = "p_remove", .linkage = .strong });
    @export(&pg_add, .{ .name = "pg_add", .linkage = .strong });
    @export(&pg_remove, .{ .name = "pg_remove", .linkage = .strong });
}
