const std = @import("std");
const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");

const hash = @import("proc_hash.zig");
const pid = @import("proc_pid.zig");
const fork = @import("proc_fork.zig");
const exit_mod = @import("proc_exit.zig");
const sig = @import("proc_sig.zig");
const tty = @import("proc_tty.zig");

fn proc_getpid(msg: *ffi.Msg) callconv(.c) c_int {
    msg.data[0] = @intCast(pid.sys_getpid());
    return 0;
}

fn proc_getppid(msg: *ffi.Msg) callconv(.c) c_int {
    const result = pid.sys_getppid();
    if (result) |ppid| {
        msg.data[0] = @intCast(ppid);
        return 0;
    } else |err| {
        return ffi.toCError(err);
    }
}

fn proc_getpgid(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = @as(task.prex.pid_t, @bitCast(msg.data[0]));
    var pgid: task.prex.pid_t = 0;
    pid.sys_getpgid(pid_val, &pgid) catch |err| return ffi.toCError(err);
    msg.data[0] = @intCast(pgid);
    return 0;
}

fn proc_setpgid(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = @as(task.prex.pid_t, @bitCast(msg.data[0]));
    const pgid = @as(task.prex.pid_t, @bitCast(msg.data[1]));
    return ffi.catchToCError(pid.sys_setpgid(pid_val, pgid));
}

fn proc_getsid(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = @as(task.prex.pid_t, @bitCast(msg.data[0]));
    var sid: task.prex.pid_t = 0;
    pid.sys_getsid(pid_val, &sid) catch |err| return ffi.toCError(err);
    msg.data[0] = @intCast(sid);
    return 0;
}

fn proc_setsid(msg: *ffi.Msg) callconv(.c) c_int {
    var sid: task.prex.pid_t = 0;
    pid.sys_setsid(&sid) catch |err| return ffi.toCError(err);
    msg.data[0] = @intCast(sid);
    return 0;
}

fn proc_fork(msg: *ffi.Msg) callconv(.c) c_int {
    const child = @as(task.prex.task_t, @bitCast(msg.data[0]));
    const vfork = msg.data[1];
    const result = fork.sys_fork(child, vfork);
    if (result) |ret_pid| {
        msg.data[0] = @intCast(ret_pid);
        return 0;
    } else |err| {
        return ffi.toCError(err);
    }
}

fn proc_exit(msg: *ffi.Msg) callconv(.c) c_int {
    const exitcode = msg.data[0];
    return ffi.catchToCError(exit_mod.sys_exit(exitcode));
}

fn proc_stop(msg: *ffi.Msg) callconv(.c) c_int {
    const exitcode = msg.data[0];
    return ffi.catchToCError(exit_mod.stop(exitcode));
}

fn proc_waitpid(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = @as(task.prex.pid_t, @bitCast(msg.data[0]));
    const options = msg.data[1];
    var status: c_int = 0;
    var pid_child: task.prex.pid_t = 0;
    exit_mod.sys_waitpid(pid_val, &status, options, &pid_child) catch |err| return ffi.toCError(err);
    msg.data[0] = @intCast(pid_child);
    msg.data[1] = status;
    return 0;
}

fn proc_kill(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = @as(task.prex.pid_t, @bitCast(msg.data[0]));
    const sig_val = msg.data[1];
    return ffi.catchToCError(sig.sys_kill(pid_val, sig_val));
}

fn proc_exec(msg: *ffi.Msg) callconv(.c) c_int {
    const orgtask = @as(task.prex.task_t, @bitCast(msg.data[0]));
    const newtask = @as(task.prex.task_t, @bitCast(msg.data[1]));
    const p = hash.task_to_proc(orgtask) orelse return prog.errno.EINVAL;

    hash.p_remove(p);
    p.p_task = newtask;
    hash.p_add(p);
    p.p_invfork = 0;
    p.p_stackbase = @as(?*anyopaque, @ptrFromInt(@as(usize, @bitCast(msg.data[2]))));

    const parent = p.p_parent;
    if (parent != null and parent.*.p_vforked != 0) {
        fork.vfork_end(parent.?);
    }
    return 0;
}

fn proc_pstat(msg: *ffi.Msg) callconv(.c) c_int {
    const t = @as(task.prex.task_t, @bitCast(msg.data[0]));
    const p = hash.task_to_proc(t) orelse return prog.errno.EINVAL;

    msg.data[0] = @intCast(p.p_pid);
    msg.data[2] = @intCast(p.p_stat);
    if (p.p_parent == null) {
        msg.data[1] = 0;
    } else {
        msg.data[1] = @intCast(p.p_parent.*.p_pid);
    }
    return 0;
}

fn proc_register(msg: *ffi.Msg) callconv(.c) c_int {
    if (task.prex.task_chkcap(msg.hdr.task, ffi.raw.CAP_PROTSERV) != 0) {
        return prog.errno.EPERM;
    }

    const mem = prog.stdlib.malloc(@sizeOf(ffi.Proc)) orelse return prog.errno.ENOMEM;
    const p: *ffi.Proc = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(ffi.Proc)], 0);

    ffi.global.set_curproc(ffi.global.get_proc0());
    fork.newproc(p, 0, msg.hdr.task) catch {
        task.prex.sys_panic(ffi.global.get_fail_register_msg());
        return 0;
    };
    return 0;
}

fn proc_setinit(msg: *ffi.Msg) callconv(.c) c_int {
    if (task.prex.task_chkcap(msg.hdr.task, ffi.raw.CAP_PROTSERV) != 0) {
        return prog.errno.EPERM;
    }

    if (ffi.global.get_initproc().p_stat == ffi.raw.SRUN) {
        return prog.errno.EPERM;
    }

    ffi.global.set_curproc(ffi.global.get_proc0());
    fork.newproc(ffi.global.get_initproc(), 1, msg.hdr.task) catch {
        task.prex.sys_panic(ffi.global.get_fail_register_msg());
        return 0;
    };
    return 0;
}

fn proc_trace(msg: *ffi.Msg) callconv(.c) c_int {
    const t = msg.hdr.task;
    const p = hash.task_to_proc(t) orelse return prog.errno.EINVAL;
    _ = p;
    return 0;
}

fn proc_boot(msg: *ffi.Msg) callconv(.c) c_int {
    var obj: task.prex.object_t = 0;
    var m: prog.ipc.exec.struct_bind_msg = undefined;

    if (task.prex.task_chkcap(msg.hdr.task, ffi.raw.CAP_PROTSERV) != 0) {
        return prog.errno.EPERM;
    }

    if (task.prex.object_lookup(ffi.global.get_exec_obj_name(), &obj) != 0) {
        task.prex.sys_panic(ffi.global.get_no_exec_msg());
    }

    m.hdr.code = prog.ipc.exec.EXEC_BINDCAP;
    _ = prog.string.strlcpy(&m.path, ffi.global.get_proc_path(), @sizeOf(@TypeOf(m.path)));
    _ = task.prex.msg_send(obj, &m, @sizeOf(prog.ipc.exec.struct_bind_msg));

    return 0;
}

fn proc_shutdown(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc_noop(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc_debug(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn proc0_init() void {
    const p = ffi.global.get_proc0();
    const pg = ffi.global.get_pgrp0();
    const sess = ffi.global.get_session0();

    pg.pg_pgid = 0;
    const pg_members: *ffi.List = @ptrCast(&pg.pg_members);
    pg_members.init();
    hash.pg_add(pg);

    pg.pg_session = sess;
    sess.s_refcnt = 1;
    sess.s_leader = p;
    sess.s_ttyhold = 0;

    p.p_parent = null;
    p.p_pgrp = pg;
    p.p_stat = ffi.raw.SRUN;
    p.p_exitcode = 0;
    p.p_pid = 0;
    p.p_task = task.prex.task_self();
    p.p_vforked = 0;
    p.p_invfork = 0;

    const p_children: *ffi.List = @ptrCast(&p.p_children);
    p_children.init();
    hash.p_add(p);
    const pgrp_link: *ffi.List = @ptrCast(&p.p_pgrp_link);
    pg_members.insert(pgrp_link);
}

pub fn main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    var msg: ffi.Msg = undefined;
    var obj: task.prex.object_t = 0;

    _ = task.prex.sys_log(ffi.global.get_boot_msg());

    _ = task.prex.thread_setpri(task.prex.thread_self(), task.prex.PRI_PROC);

    const allproc: *ffi.List = @ptrCast(ffi.global.get_allproc());
    allproc.init();
    tty.tty_init();
    ffi.global.table_init();

    proc0_init();

    if (task.prex.object_create(ffi.global.get_proc_obj_name(), &obj) != 0) {
        task.prex.sys_panic(ffi.global.get_create_obj_fail_msg());
    }

    while (true) {
        var error_code = task.prex.msg_receive(obj, &msg, @sizeOf(ffi.Msg));
        if (error_code != 0) {
            continue;
        }

        ffi.global.set_curproc(hash.task_to_proc(msg.hdr.task));

        error_code = ffi.global.dispatch_msg(msg.hdr.code, &msg);

        msg.hdr.status = error_code;
        _ = task.prex.msg_reply(obj, &msg, @sizeOf(ffi.Msg));
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
