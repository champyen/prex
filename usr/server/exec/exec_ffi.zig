const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("usr/server/exec/exec.h");
    @cInclude("ipc/exec.h");
    @cInclude("ipc/proc.h");
    @cInclude("ipc/fs.h");
    @cInclude("sys/capability.h");
    @cInclude("sys/param.h");
    @cInclude("sys/stat.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("limits.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("errno.h");
    @cInclude("libgen.h");
    @cInclude("sys/elf.h");
    @cInclude("sys/dbgctl.h");
    @cInclude("stdio.h");
});

pub const raw = c;

pub const Exec = c.struct_exec;
pub const ExecMsg = c.struct_exec_msg;
pub const BindMsg = c.struct_bind_msg;
pub const ExecLoader = c.struct_exec_loader;
pub const CapMap = c.struct_cap_map;
pub const Msg = c.struct_msg;

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

pub fn allocZeroed(comptime T: type) ?*T {
    const mem = c.malloc(@sizeOf(T)) orelse return null;
    const p: *T = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(T)], 0);
    return p;
}

pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => @intCast(c.ENOMEM),
        error.InvalidArgument => @intCast(c.EINVAL),
        error.NotFound => @intCast(c.ENOENT),
        error.PermissionDenied => @intCast(c.EPERM),
        else => @intCast(c.EIO),
    };
}

pub fn catchToCError(result: anytype) c_int {
    return if (result) |_| 0 else |err| toCError(err);
}

pub inline fn msgData(comptime T: type, val: c_int) T {
    return @as(T, @bitCast(val));
}

pub inline fn dataToPtr(comptime T: type, val: anytype) T {
    return @as(T, @ptrFromInt(@as(usize, @intCast(val))));
}

/// PIC-safe getter/setter wrappers and C helpers from exec_globals.c
pub const global = struct {
    pub extern fn hdrbuf_get() [*]u8;
    pub extern fn hdrbuf_zero() void;
    pub extern fn sect_addr_get() *[*]u8;
    pub extern fn get_elf_type() c.Elf32_Half;
    pub extern fn get_text_vma() c.Elf32_Addr;
    pub extern fn get_data_vma() c.Elf32_Addr;
    pub extern fn get_text_runtime() c.Elf32_Addr;
    pub extern fn get_data_runtime() c.Elf32_Addr;
    pub extern fn set_elf_type(val: c.Elf32_Half) void;
    pub extern fn set_text_vma(val: c.Elf32_Addr) void;
    pub extern fn set_data_vma(val: c.Elf32_Addr) void;
    pub extern fn set_text_runtime(val: c.Elf32_Addr) void;
    pub extern fn set_data_runtime(val: c.Elf32_Addr) void;
    pub extern fn set_sram_got_base(val: c.Elf32_Addr) void;
    pub extern fn set_current_symtab(symtab: [*c]c.Elf32_Sym) void;
    pub extern fn get_script_interp() [*]u8;
    pub extern fn get_script_intarg() [*]u8;
    pub extern fn get_script_name() [*]u8;
    pub extern fn loader_table_get() [*]ExecLoader;
    pub extern fn nloader_get() c_int;
    pub extern fn cap_table_get() [*]const CapMap;

    pub extern fn get_boot_msg() [*c]const u8;
    pub extern fn get_no_proc_msg() [*c]const u8;
    pub extern fn get_create_obj_fail_msg() [*c]const u8;
    pub extern fn get_exec_obj_name() [*c]const u8;
    pub extern fn get_proc_obj_name() [*c]const u8;
    pub extern fn get_exec_path() [*c]const u8;
    pub extern fn get_fs_obj_name() [*c]const u8;
    pub extern fn get_cmdbox_path() [*c]const u8;
    pub extern fn get_sh_bin() [*c]const u8;

    pub extern fn setup_exec_exception() void;
    pub extern fn dispatch_msg(c_int, *Msg) c_int;
    pub extern fn build_args(
        task: c.task_t,
        stack: ?*anyopaque,
        path: [*c]u8,
        msg: *c.struct_exec_msg,
        xarg1: [*c]u8,
        xarg2: [*c]u8,
        new_sp: *?*anyopaque,
    ) c_int;
};

pub const Errno = struct {
    pub const EPERM: c_int = 1;
    pub const ENOENT: c_int = 2;
    pub const ESRCH: c_int = 3;
    pub const EINTR: c_int = 4;
    pub const EIO: c_int = 5;
    pub const ENXIO: c_int = 6;
    pub const EBADF: c_int = 9;
    pub const ENOMEM: c_int = 12;
    pub const EACCES: c_int = 13;
    pub const EFAULT: c_int = 14;
    pub const EEXIST: c_int = 17;
    pub const ENODEV: c_int = 19;
    pub const ENOTDIR: c_int = 20;
    pub const EISDIR: c_int = 21;
    pub const EINVAL: c_int = 22;
    pub const EMFILE: c_int = 24;
    pub const ENOSPC: c_int = 28;
    pub const EROFS: c_int = 30;
    pub const ENAMETOOLONG: c_int = 36;
    pub const ENOSYS: c_int = 38;
    pub const ENOEXEC: c_int = 45;
    pub const ECHILD: c_int = 10;
};
