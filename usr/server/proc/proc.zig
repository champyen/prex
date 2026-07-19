const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("sys/param.h");
    @cInclude("ipc/proc.h");
    @cInclude("ipc/ipc.h");
    @cInclude("ipc/exec.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_proc0() *c.struct_proc;
extern fn get_pgrp0() *c.struct_pgrp;
extern fn get_session0() *c.struct_session;
extern fn get_curproc() *c.struct_proc;
extern fn set_curproc(?*c.struct_proc) void;
extern fn get_initproc() *c.struct_proc;
extern fn get_allproc() *c.struct_list;

extern fn get_boot_msg() [*c]const u8;
extern fn get_create_obj_fail_msg() [*c]const u8;
extern fn get_proc_obj_name() [*c]const u8;
extern fn get_exec_obj_name() [*c]const u8;
extern fn get_proc_path() [*c]const u8;
extern fn get_no_exec_msg() [*c]const u8;
extern fn get_fail_register_msg() [*c]const u8;

extern fn task_to_proc(c.task_t) ?*c.struct_proc;
extern fn p_add(*c.struct_proc) void;
extern fn p_remove(*c.struct_proc) void;
extern fn pg_add(*c.struct_pgrp) void;
extern fn newproc(*c.struct_proc, c.pid_t, c.task_t) c_int;
extern fn vfork_end(*c.struct_proc) void;

extern fn sys_getpid() c.pid_t;
extern fn sys_getppid() c.pid_t;
extern fn sys_getpgid(c.pid_t, *c.pid_t) c_int;
extern fn sys_setpgid(c.pid_t, c.pid_t) c_int;
extern fn sys_getsid(c.pid_t, *c.pid_t) c_int;
extern fn sys_setsid(*c.pid_t) c_int;
extern fn sys_fork(c.task_t, c_int, *c.pid_t) c_int;
extern fn sys_exit(c_int) c_int;
extern fn stop(c_int) c_int;
extern fn sys_waitpid(c.pid_t, *c_int, c_int, *c.pid_t) c_int;
extern fn sys_kill(c.pid_t, c_int) c_int;
extern fn dispatch_msg(c_int, *c.struct_msg) c_int;

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

fn proc_getpid(msg: *c.struct_msg) callconv(.c) c_int {
    msg.data[0] = @intCast(sys_getpid());
    return 0;
}

fn proc_getppid(msg: *c.struct_msg) callconv(.c) c_int {
    msg.data[0] = @intCast(sys_getppid());
    return 0;
}

fn proc_getpgid(msg: *c.struct_msg) callconv(.c) c_int {
    const pid = @as(c.pid_t, @bitCast(msg.data[0]));
    var pgid: c.pid_t = 0;
    const err = sys_getpgid(pid, &pgid);
    if (err != 0) {
        return err;
    }
    msg.data[0] = @intCast(pgid);
    return 0;
}

fn proc_setpgid(msg: *c.struct_msg) callconv(.c) c_int {
    const pid = @as(c.pid_t, @bitCast(msg.data[0]));
    const pgid = @as(c.pid_t, @bitCast(msg.data[1]));
    return sys_setpgid(pid, pgid);
}

fn proc_getsid(msg: *c.struct_msg) callconv(.c) c_int {
    const pid = @as(c.pid_t, @bitCast(msg.data[0]));
    var sid: c.pid_t = 0;
    const err = sys_getsid(pid, &sid);
    if (err != 0) {
        return err;
    }
    msg.data[0] = @intCast(sid);
    return 0;
}

fn proc_setsid(msg: *c.struct_msg) callconv(.c) c_int {
    var sid: c.pid_t = 0;
    const err = sys_setsid(&sid);
    if (err != 0) {
        return err;
    }
    msg.data[0] = @intCast(sid);
    return 0;
}

fn proc_fork(msg: *c.struct_msg) callconv(.c) c_int {
    const child = @as(c.task_t, @bitCast(msg.data[0]));
    const vfork = msg.data[1];
    var pid: c.pid_t = 0;
    const err = sys_fork(child, vfork, &pid);
    if (err != 0) {
        return err;
    }
    msg.data[0] = @intCast(pid);
    return 0;
}

fn proc_exit(msg: *c.struct_msg) callconv(.c) c_int {
    const exitcode = msg.data[0];
    return sys_exit(exitcode);
}

fn proc_stop(msg: *c.struct_msg) callconv(.c) c_int {
    const exitcode = msg.data[0];
    return stop(exitcode);
}

fn proc_waitpid(msg: *c.struct_msg) callconv(.c) c_int {
    const pid = @as(c.pid_t, @bitCast(msg.data[0]));
    const options = msg.data[1];
    var status: c_int = 0;
    var pid_child: c.pid_t = 0;
    const err = sys_waitpid(pid, &status, options, &pid_child);
    if (err != 0) {
        return err;
    }
    msg.data[0] = @intCast(pid_child);
    msg.data[1] = status;
    return 0;
}

fn proc_kill(msg: *c.struct_msg) callconv(.c) c_int {
    const pid = @as(c.pid_t, @bitCast(msg.data[0]));
    const sig = msg.data[1];
    return sys_kill(pid, sig);
}

fn proc_exec(msg: *c.struct_msg) callconv(.c) c_int {
    const orgtask = @as(c.task_t, @bitCast(msg.data[0]));
    const newtask = @as(c.task_t, @bitCast(msg.data[1]));
    const p = task_to_proc(orgtask) orelse return c.EINVAL;

    p_remove(p);
    p.p_task = newtask;
    p_add(p);
    p.p_invfork = 0;
    p.p_stackbase = @as(? *anyopaque, @ptrFromInt(@as(usize, @bitCast(msg.data[2]))));

    const parent = p.p_parent;
    if (parent != null and parent.*.p_vforked != 0) {
        vfork_end(parent.?);
    }
    return 0;
}

fn proc_pstat(msg: *c.struct_msg) callconv(.c) c_int {
    const task = @as(c.task_t, @bitCast(msg.data[0]));
    const p = task_to_proc(task) orelse return c.EINVAL;

    msg.data[0] = @intCast(p.p_pid);
    msg.data[2] = @intCast(p.p_stat);
    if (p.p_parent == null) {
        msg.data[1] = 0;
    } else {
        msg.data[1] = @intCast(p.p_parent.*.p_pid);
    }
    return 0;
}

fn proc_register(msg: *c.struct_msg) callconv(.c) c_int {
    // Check client's capability.
    if (c.task_chkcap(msg.hdr.task, c.CAP_PROTSERV) != 0) {
        return c.EPERM;
    }

    const mem = c.malloc(@sizeOf(c.struct_proc)) orelse return c.ENOMEM;
    const p: *c.struct_proc = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(c.struct_proc)], 0);

    set_curproc(get_proc0());
    if (newproc(p, 0, msg.hdr.task) != 0) {
        c.sys_panic(get_fail_register_msg());
    }
    return 0;
}

fn proc_setinit(msg: *c.struct_msg) callconv(.c) c_int {
    // Check client's capability.
    if (c.task_chkcap(msg.hdr.task, c.CAP_PROTSERV) != 0) {
        return c.EPERM;
    }

    if (get_initproc().p_stat == c.SRUN) {
        return c.EPERM;
    }

    set_curproc(get_proc0());
    if (newproc(get_initproc(), 1, msg.hdr.task) != 0) {
        c.sys_panic(get_fail_register_msg());
    }
    return 0;
}

fn proc_trace(msg: *c.struct_msg) callconv(.c) c_int {
    const task = msg.hdr.task;
    const p = task_to_proc(task) orelse return c.EINVAL;
    _ = p;
    return 0;
}

fn proc_boot(msg: *c.struct_msg) callconv(.c) c_int {
    var obj: c.object_t = 0;
    var m: c.struct_bind_msg = undefined;

    if (c.task_chkcap(msg.hdr.task, c.CAP_PROTSERV) != 0) {
        return c.EPERM;
    }

    if (c.object_lookup(get_exec_obj_name(), &obj) != 0) {
        c.sys_panic(get_no_exec_msg());
    }

    m.hdr.code = c.EXEC_BINDCAP;
    _ = c.strlcpy(&m.path, get_proc_path(), @sizeOf(@TypeOf(m.path)));
    _ = c.msg_send(obj, &m, @sizeOf(c.struct_bind_msg));

    return 0;
}

fn proc_shutdown(msg: *c.struct_msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc_noop(msg: *c.struct_msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc_debug(msg: *c.struct_msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc0_init() void {
    const p = get_proc0();
    const pg = get_pgrp0();
    const sess = get_session0();

    pg.pg_pgid = 0;
    list_init(&pg.pg_members);
    pg_add(pg);

    pg.pg_session = sess;
    sess.s_refcnt = 1;
    sess.s_leader = p;
    sess.s_ttyhold = 0;

    p.p_parent = null;
    p.p_pgrp = pg;
    p.p_stat = c.SRUN;
    p.p_exitcode = 0;
    p.p_pid = 0;
    p.p_task = c.task_self();
    p.p_vforked = 0;
    p.p_invfork = 0;

    list_init(&p.p_children);
    p_add(p);
    list_insert(&pg.pg_members, &p.p_pgrp_link);
}

pub fn main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    var msg: c.struct_msg = undefined;
    var obj: c.object_t = 0;

    _ = c.sys_log(get_boot_msg());

    // Boost thread priority.
    _ = c.thread_setpri(c.thread_self(), c.PRI_PROC);

    // Initialize process and pgrp structures.
    list_init(get_allproc());
    c.tty_init();
    c.table_init();

    // Create process 0 (process server).
    proc0_init();

    // Create an object to expose our service.
    if (c.object_create(get_proc_obj_name(), &obj) != 0) {
        c.sys_panic(get_create_obj_fail_msg());
    }

    while (true) {
        var error_code = c.msg_receive(obj, &msg, @sizeOf(c.struct_msg));
        if (error_code != 0) {
            continue;
        }

        set_curproc(task_to_proc(msg.hdr.task));

        error_code = dispatch_msg(msg.hdr.code, &msg);

        msg.hdr.status = error_code;
        _ = c.msg_reply(obj, &msg, @sizeOf(c.struct_msg));
    }
}

comptime {
    @export(&main, .{ .name = "main", .linkage = .strong });
    @export(&proc_getpid, .{ .name = "proc_getpid", .linkage = .strong });
    @export(&proc_getppid, .{ .name = "proc_getppid", .linkage = .strong });
    @export(&proc_getpgid, .{ .name = "proc_getpgid", .linkage = .strong });
    @export(&proc_setpgid, .{ .name = "proc_setpgid", .linkage = .strong });
    @export(&proc_setsid, .{ .name = "proc_setsid", .linkage = .strong });
    @export(&proc_getsid, .{ .name = "proc_getsid", .linkage = .strong });
    @export(&proc_fork, .{ .name = "proc_fork", .linkage = .strong });
    @export(&proc_exit, .{ .name = "proc_exit", .linkage = .strong });
    @export(&proc_stop, .{ .name = "proc_stop", .linkage = .strong });
    @export(&proc_waitpid, .{ .name = "proc_waitpid", .linkage = .strong });
    @export(&proc_kill, .{ .name = "proc_kill", .linkage = .strong });
    @export(&proc_exec, .{ .name = "proc_exec", .linkage = .strong });
    @export(&proc_pstat, .{ .name = "proc_pstat", .linkage = .strong });
    @export(&proc_register, .{ .name = "proc_register", .linkage = .strong });
    @export(&proc_setinit, .{ .name = "proc_setinit", .linkage = .strong });
    @export(&proc_trace, .{ .name = "proc_trace", .linkage = .strong });
    @export(&proc_boot, .{ .name = "proc_boot", .linkage = .strong });
    @export(&proc_shutdown, .{ .name = "proc_shutdown", .linkage = .strong });
    @export(&proc_debug, .{ .name = "proc_debug", .linkage = .strong });
    @export(&proc_noop, .{ .name = "proc_noop", .linkage = .strong });
}
