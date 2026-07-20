const c = @cImport({
    @cInclude("usr/server/proc/proc.h");
});
const prog = @import("prog");

pub const raw = c;

pub const Proc = c.struct_proc;
pub const Pgrp = c.struct_pgrp;
pub const Session = c.struct_session;
pub const Msg = c.struct_msg;
pub const BindMsg = c.struct_bind_msg;

pub const List = extern struct {
    next: ?*List,
    prev: ?*List,

    pub inline fn init(self: *List) void {
        self.next = self;
        self.prev = self;
    }

    pub inline fn first(self: *List) ?*List {
        return self.next;
    }

    pub inline fn nextNode(self: *List) ?*List {
        return self.next;
    }

    pub inline fn insert(self: *List, node: *List) void {
        node.next = self.next;
        node.prev = self;
        self.next.?.*.prev = node;
        self.next = node;
    }

    pub inline fn remove(self: *List) void {
        self.prev.?.*.next = self.next;
        self.next.?.*.prev = self.prev;
    }

    pub inline fn entry(self: *List, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const raw_self: *c.struct_list = @ptrCast(self);
        return @fieldParentPtr(field_name, raw_self);
    }

    pub inline fn empty(self: *List) bool {
        return self.next == self;
    }
};

pub inline fn idHash(x: anytype) usize {
    const uval: u32 = @bitCast(x);
    return @as(usize, uval) & (c.ID_MAXBUCKETS - 1);
}

pub fn allocZeroed(comptime T: type) ?*T {
    const mem = prog.stdlib.malloc(@sizeOf(T)) orelse return null;
    const p: *T = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(T)], 0);
    return p;
}

pub inline fn msgData(comptime T: type, val: c_int) T {
    return @as(T, @bitCast(val));
}

pub inline fn dataToPtr(comptime T: type, val: anytype) T {
    return @as(T, @ptrFromInt(@as(usize, @intCast(val))));
}

pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => prog.errno.ENOMEM,
        error.InvalidArgument => prog.errno.EINVAL,
        error.NotFound => prog.errno.ESRCH,
        error.PermissionDenied => prog.errno.EPERM,
        error.ResourceLimit => prog.errno.EAGAIN,
        error.NoChildProcesses => prog.errno.ECHILD,
        else => prog.errno.EIO,
    };
}

pub fn catchToCError(result: anytype) c_int {
    return if (result) |_| 0 else |err| toCError(err);
}

/// GCC PIC getter/setter wrappers and C helpers from proc_hash_tables.c
pub const global = struct {
    pub extern fn get_proc0() *Proc;
    pub extern fn get_pgrp0() *Pgrp;
    pub extern fn get_session0() *Session;
    pub extern fn get_curproc() *Proc;
    pub extern fn set_curproc(?*Proc) void;
    pub extern fn get_initproc() *Proc;
    pub extern fn get_allproc() *List;
    pub extern fn get_last_pid() c.pid_t;
    pub extern fn set_last_pid(c.pid_t) void;
    pub extern fn get_ttydev() c.device_t;
    pub extern fn set_ttydev(c.device_t) void;
    pub extern fn setup_tty_exception() void;
    pub extern fn get_tty_name() [*c]const u8;
    pub extern fn get_panic_msg() [*c]const u8;
    pub extern fn get_boot_msg() [*c]const u8;
    pub extern fn get_create_obj_fail_msg() [*c]const u8;
    pub extern fn get_proc_obj_name() [*c]const u8;
    pub extern fn get_exec_obj_name() [*c]const u8;
    pub extern fn get_proc_path() [*c]const u8;
    pub extern fn get_no_exec_msg() [*c]const u8;
    pub extern fn get_fail_register_msg() [*c]const u8;
    pub extern fn get_pid_table() *[@as(usize, c.ID_MAXBUCKETS)]List;
    pub extern fn get_task_table() *[@as(usize, c.ID_MAXBUCKETS)]List;
    pub extern fn get_pgid_table() *[@as(usize, c.ID_MAXBUCKETS)]List;
    pub extern fn table_init() void;
    pub extern fn dispatch_msg(c_int, *Msg) c_int;
};
