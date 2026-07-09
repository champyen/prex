// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the author nor the names of any co-contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.

// boot.zig - bootstrap server
//
// A bootstrap server works to setup the POSIX environment for
// 'init' process. It sends a setup message to other servers in
// order to let them know that this task becomes 'init' process.
// The bootstrap server is gone after it launches (exec) the
// 'init' process.

const std = @import("std");
const posix = @import("posix");

const unistd = posix.unistd;
const stdlib = posix.stdlib;
const stdio = posix.stdio;
const errno = posix.errno;
const fcntl = posix.fcntl;
const string = posix.string;
const prex = posix.prex;
const sys = posix.sys;
const ipc = posix.ipc;

const dprintf = if (@hasDecl(std.debug, "builtin") and std.debug.builtin.optimization == .Debug)
    struct {
        fn log(comptime fmt: []const u8, args: anytype) void {
            posix.print(fmt ++ "\n", args);
        }
    }.log
else
    struct {
        fn log(comptime fmt: []const u8, args: anytype) void {
            _ = fmt;
            _ = args;
        }
    }.log;

fn wait_server(name: [*:0]const u8, pobj: *prex.object_t) void {
    _ = prex.thread_yield();
    var i: c_int = 0;
    var err: c_int = 0;
    while (i < 100) : (i += 1) {
        err = prex.object_lookup(@constCast(@ptrCast(name)), pobj);
        if (err == 0) break;
        _ = prex.timer_sleep(10, 0);
        _ = prex.thread_yield();
    }
    if (err != 0) prex.sys_panic("boot: server not found");
}

fn send_bootmsg(obj: prex.object_t) void {
    var m: ipc.ipc.struct_msg = std.mem.zeroes(ipc.ipc.struct_msg);
    m.hdr.code = ipc.ipc.STD_BOOT;
    const err = prex.msg_send(obj, &m, @sizeOf(ipc.ipc.struct_msg));
    if (err != 0) prex.sys_panic("boot: server error");
}

fn mount_fs() void {
    dprintf("boot: mounting file systems\n", .{});

    var base_dir: [7][*:0]const u8 = undefined;
    base_dir[0] = "/bin";
    base_dir[1] = "/boot";
    base_dir[2] = "/dev";
    base_dir[3] = "/etc";
    base_dir[4] = "/mnt";
    base_dir[5] = "/usr";
    base_dir[6] = "/tmp";

    if (sys.mount.mount("", "/", "ramfs", 0, null) < 0)
        prex.sys_panic("boot: mount failed");

    for (base_dir) |dir| {
        if (sys.stat.mkdir(dir, 0) == -1)
            prex.sys_panic("boot: mkdir failed");
    }

    if (sys.mount.mount("/dev/ram0", "/boot", "arfs", 0, null) < 0)
        prex.sys_panic("boot: mount failed");

    const fp = stdio.fopen("/boot/fstab", "r") orelse {
        prex.sys_panic("boot: no fstab");
        unreachable;
    };

    var line: [128]u8 = undefined;
    while (stdio.fgets(&line, @intCast(line.len), fp) != null) {
        const p: [*:0]u8 = @ptrCast(&line);
        const spec: ?[*:0]u8 = @ptrCast(string.strtok(p, " \t\n"));
        if (spec == null or spec.?[0] == '#')
            continue;
        const file: ?[*:0]u8 = @ptrCast(string.strtok(null, " \t\n"));
        const fstype: ?[*:0]u8 = @ptrCast(string.strtok(null, " \t\n"));
        if (string.strcmp(file.?, "/") == 0 or string.strcmp(file.?, "/boot") == 0)
            continue;
        var spec_ptr = spec.?;
        if (string.strcmp(spec.?, "none") == 0)
            spec_ptr = @constCast("");

        _ = sys.stat.mkdir(file.?, 0);
        _ = sys.mount.mount(spec_ptr, file.?, fstype.?, 0, null);
    }
    _ = stdio.fclose(fp);
}

fn exec_init(execobj: prex.object_t) void {
    dprintf("boot: execute init\n", .{});

    var initargs: [1][*:0]const u8 = undefined;
    initargs[0] = "1";
    var initenvs: [2][*:0]const u8 = undefined;
    initenvs[0] = "TERM=vt100";
    initenvs[1] = "USER=root";

    var msg: ipc.exec.struct_exec_msg = std.mem.zeroes(ipc.exec.struct_exec_msg);
    var bufsz: usize = 0;
    var argc: c_int = 0;

    for (initargs) |arg| {
        bufsz += std.mem.len(arg) + 1;
        argc += 1;
    }

    var envc: c_int = 0;
    for (initenvs) |env| {
        bufsz += std.mem.len(env) + 1;
        envc += 1;
    }

    if (bufsz >= ipc.exec.ARG_MAX)
        prex.sys_panic("boot: args too long");

    var dest: [*]u8 = @ptrCast(&msg.buf);
    for (initargs) |arg| {
        for (std.mem.sliceTo(arg, 0)) |ch| {
            dest[0] = ch;
            dest += 1;
        }
        dest[0] = 0;
        dest += 1;
    }
    for (initenvs) |env| {
        for (std.mem.sliceTo(env, 0)) |ch| {
            dest[0] = ch;
            dest += 1;
        }
        dest[0] = 0;
        dest += 1;
    }

    msg.hdr.code = ipc.exec.EXEC_EXECVE;
    msg.argc = argc;
    msg.envc = envc;
    msg.bufsz = @intCast(bufsz);
    _ = string.strlcpy(&msg.cwd, "/", @sizeOf(@TypeOf(msg.cwd)));
    _ = string.strlcpy(&msg.path, "/boot/init", @sizeOf(@TypeOf(msg.path)));

    while (true) {
        const err = prex.msg_send(execobj, &msg, @sizeOf(ipc.exec.struct_exec_msg));
        if (err != errno.EINTR) break;
    }
}

fn copy_file(src: [*:0]const u8, dest_path: [*:0]const u8) void {
    var iobuf: [1024]u8 = undefined;
    const fold = fcntl.open(@constCast(@ptrCast(src)), fcntl.O_RDONLY);
    if (fold == -1) return;

    var stbuf: sys.stat.struct_stat = std.mem.zeroes(sys.stat.struct_stat);
    _ = sys.stat.fstat(fold, &stbuf);
    const mode = stbuf.st_mode;

    const fnew = fcntl.creat(@constCast(@ptrCast(dest_path)), mode);
    if (fnew == -1) {
        _ = unistd.close(fold);
        return;
    }

    while (true) {
        const n = unistd.read(fold, &iobuf, iobuf.len);
        if (n <= 0) break;
        if (unistd.write(fnew, &iobuf, @intCast(n)) != n) {
            _ = unistd.close(fold);
            _ = unistd.close(fnew);
            return;
        }
    }
    _ = unistd.close(fold);
    _ = unistd.close(fnew);
}

export fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    _ = argv;
    _ = argc;

    var execobj: prex.object_t = undefined;
    var procobj: prex.object_t = undefined;
    var fsobj: prex.object_t = undefined;

    _ = prex.sys_log("Starting bootstrap server\n");

    _ = prex.thread_setpri(prex.thread_self(), prex.PRI_DEFAULT);

    wait_server("!proc", &procobj);
    wait_server("!fs", &fsobj);
    wait_server("!exec", &execobj);

    send_bootmsg(execobj);
    send_bootmsg(procobj);
    send_bootmsg(fsobj);

    var bm: ipc.exec.struct_bind_msg = std.mem.zeroes(ipc.exec.struct_bind_msg);
    bm.hdr.code = ipc.exec.EXEC_BINDCAP;
    _ = string.strlcpy(&bm.path, "/boot/boot", @sizeOf(@TypeOf(bm.path)));
    _ = prex.msg_send(execobj, &bm, @sizeOf(ipc.exec.struct_bind_msg));

    var m: ipc.ipc.struct_msg = std.mem.zeroes(ipc.ipc.struct_msg);
    m.hdr.code = ipc.proc.PS_SETINIT;
    _ = prex.msg_send(procobj, &m, @sizeOf(ipc.ipc.struct_msg));

    unistd.fslib_init();

    mount_fs();

    copy_file("/boot/rc", "/etc/rc");
    copy_file("/boot/fstab", "/etc/fstab");

    const fd = fcntl.open("/dev/console", fcntl.O_RDWR);
    if (fd == 0) {
        _ = unistd.dup(0);
        _ = unistd.dup(0);
    }

    exec_init(execobj);

    prex.sys_panic("boot: failed to exec init");

    return 0;
}
