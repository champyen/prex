/// Structured library namespaces (see zig_from_c_refactor.md):
/// - `prog`  : libc functions/constants and IPC message codes
/// - `task`  : Prex microkernel types and syscalls (under `task.prex`)
pub const prog = @import("prog");
pub const task = @import("task");

/// Module-private C headers. Only exec-specific glue lives here; libc and
/// kernel declarations are accessed via `prog`/`task` instead.
const c = @cImport({
    @cInclude("usr/server/exec/exec.h");
    @cInclude("sys/elf.h");
    @cInclude("libgen.h");
});

/// Compile-time configuration flags derived from conf/config.h.
pub const config = struct {
    pub const MMU = @hasDecl(c, "CONFIG_MMU");
    pub const ARMV8M = @hasDecl(c, "CONFIG_ARMV8M");
};

/// ARM target detection, mirroring the C `#if defined(__arm__)` guard in
/// struct exec (which conditionally embeds the `gp` field).
pub const is_arm = @hasDecl(c, "__arm__");

/// Size of the executable header buffer read by Exec.readHeader().
pub const HEADER_SIZE: c_int = c.HEADER_SIZE;

/// Structured ELF ABI namespace (from <sys/elf.h>).
pub const elf = struct {
    pub const Ehdr = c.Elf32_Ehdr;
    pub const Phdr = c.Elf32_Phdr;
    pub const Shdr = c.Elf32_Shdr;
    pub const Sym = c.Elf32_Sym;
    pub const Rel = c.Elf32_Rel;
    pub const Rela = c.Elf32_Rela;
    pub const Addr = c.Elf32_Addr;
    pub const Half = c.Elf32_Half;
    pub const Word = c.Elf32_Word;
    pub const Off = c.Elf32_Off;
    pub const Sword = c.Elf32_Sword;

    /// Relocation info field (r_info): low 8 bits = type, high 24 bits = sym.
    pub const RelInfo = packed struct(u32) {
        type: u8,
        sym: u24,
    };

    /// Symbol info byte (st_info): low 4 bits = type, high 4 bits = bind.
    pub const Elf32_SymInfo = packed struct(u8) {
        type: u4,
        bind: u4,
    };

    pub const EI_MAG0 = c.EI_MAG0;
    pub const EI_MAG1 = c.EI_MAG1;
    pub const EI_MAG2 = c.EI_MAG2;
    pub const EI_MAG3 = c.EI_MAG3;
    pub const ELFMAG0 = c.ELFMAG0;
    pub const ELFMAG1 = c.ELFMAG1;
    pub const ELFMAG2 = c.ELFMAG2;
    pub const ELFMAG3 = c.ELFMAG3;

    pub const ET_EXEC = c.ET_EXEC;
    pub const ET_REL = c.ET_REL;

    pub const SHT_SYMTAB = c.SHT_SYMTAB;
    pub const SHT_RELA = c.SHT_RELA;
    pub const SHT_REL = c.SHT_REL;
    pub const SHT_NOBITS = c.SHT_NOBITS;
    pub const SHT_PROGBITS = c.SHT_PROGBITS;

    pub const SHF_WRITE = c.SHF_WRITE;
    pub const SHF_ALLOC = c.SHF_ALLOC;
    pub const SHF_EXECINSTR = c.SHF_EXECINSTR;

    pub const PT_LOAD = c.PT_LOAD;
    pub const PF_W = c.PF_W;

    pub const SHN_UNDEF = c.SHN_UNDEF;
    pub const STN_UNDEF = c.STN_UNDEF;
    pub const STB_WEAK = c.STB_WEAK;

    /// Architecture-specific relocation routines (usr/arch/$(ARCH)/elf_reloc.c)
    pub extern fn relocate_rel(rel: [*c]Rel, sym_val: Addr, target: [*c]u8) c_int;
    pub extern fn relocate_rela(rela: [*c]Rela, sym_val: Addr, target: [*c]u8) c_int;
};

pub const ExecMsg = c.struct_exec_msg;
pub const BindMsg = c.struct_bind_msg;
pub const CapMap = c.struct_cap_map;
pub const Msg = c.struct_msg;

/// Exec loader table entry, layout-compatible with `struct exec_loader`
/// (exec.h). The probe/load hooks receive the layout-compatible Exec.
pub const ExecLoader = extern struct {
    el_name: [*c]const u8,
    el_init: ?*const fn () callconv(.c) void,
    el_probe: ?*const fn (*Exec) callconv(.c) c_int,
    el_load: ?*const fn (*Exec) callconv(.c) c_int,
};

/// Probe result constants (from exec.h)
pub const PROBE_ERROR = c.PROBE_ERROR;
pub const PROBE_MATCH = c.PROBE_MATCH;
pub const PROBE_INDIRECT = c.PROBE_INDIRECT;

/// libc string helper from <libgen.h>
pub const libgen = struct {
    pub extern fn basename(path: [*c]const u8) [*c]u8;
};

/// Exec descriptor, layout-compatible with `struct exec` from exec.h.
/// The conditional `gp` field mirrors `#if defined(__arm__)` in the C struct.
pub const Exec = extern struct {
    path: [*c]u8,
    header: ?*anyopaque,
    xarg1: [*c]u8,
    xarg2: [*c]u8,
    task: task.prex.task_t,
    entry: task.prex.vaddr_t,
    gp: if (is_arm) ?*anyopaque else void,

    /// Initialize the descriptor. `header` is typically null; the
    /// Exec.readHeader() method fills it in from the shared header buffer.
    pub fn init(self: *Exec, path: [*c]u8, header: ?*anyopaque) void {
        self.path = path;
        self.header = header;
        self.xarg1 = null;
        self.xarg2 = null;
        self.task = undefined;
        self.entry = 0;
        if (is_arm) {
            self.gp = null;
        }
    }

    /// Read the first HEADER_SIZE bytes of the file into the shared header
    /// buffer and point `header` at it.
    pub fn readHeader(self: *Exec) !void {
        const fd = prog.fcntl.open(self.path, prog.fcntl.O_RDONLY);
        if (fd == -1) return error.NotFound;
        defer _ = prog.unistd.close(fd);

        var st: prog.sys.stat.struct_stat = undefined;
        if (prog.sys.stat.fstat(fd, &st) == -1) return error.IOError;
        if ((st.st_mode & 0xF000) != 0x8000) return error.PermissionDenied;

        global.hdrbuf_zero();
        const buf = global.hdrbuf_get();
        if (prog.unistd.read(fd, buf, HEADER_SIZE) == -1) return error.IOError;
        self.header = buf;
    }

    /// Probe the registered loaders against the file header, following `#!`
    /// script interpreters until a matching loader is found.
    pub fn findLoader(self: *Exec) !*const ExecLoader {
        var attempts: u32 = 0;
        while (true) : (attempts += 1) {
            if (attempts > 10) return error.InvalidExecutable;
            try self.readHeader();
            const table = global.loader_table_get();
            const nloader = global.nloader_get();
            var ldr: *const ExecLoader = undefined;
            var rc = PROBE_ERROR;
            var i: c_int = 0;
            while (i < nloader) : (i += 1) {
                ldr = &table[@intCast(i)];
                rc = ldr.el_probe.?(self);
                if (rc != PROBE_ERROR) break;
            }
            if (rc == PROBE_ERROR) return error.InvalidExecutable;
            if (rc == PROBE_INDIRECT) continue;
            return ldr;
        }
    }

    /// Load the executable image via the given loader, recording the task
    /// entry point in `entry`.
    pub fn load(self: *Exec, ldr: *const ExecLoader) !void {
        const err = ldr.el_load.?(self);
        if (err != 0) return fromCError(err);
    }
};

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
    const mem = prog.stdlib.malloc(@sizeOf(T)) orelse return null;
    const p: *T = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(p))[0..@sizeOf(T)], 0);
    return p;
}

pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => prog.errno.ENOMEM,
        error.InvalidArgument => prog.errno.EINVAL,
        error.InvalidExecutable => prog.errno.ENOEXEC,
        error.NotFound => prog.errno.ENOENT,
        error.PermissionDenied => prog.errno.EACCES,
        error.NameTooLong => prog.errno.ENAMETOOLONG,
        error.IOError => prog.errno.EIO,
        else => prog.errno.EIO,
    };
}

pub fn catchToCError(result: anytype) c_int {
    return if (result) |_| 0 else |err| toCError(err);
}

/// Reverse of toCError(): map a POSIX errno produced by a loader back to a
/// Zig error at the Exec.load() boundary.
pub fn fromCError(val: c_int) anyerror {
    return switch (val) {
        prog.errno.ENOMEM => error.OutOfMemory,
        prog.errno.EINVAL => error.InvalidArgument,
        prog.errno.ENOEXEC => error.InvalidExecutable,
        prog.errno.ENOENT => error.NotFound,
        prog.errno.EACCES => error.PermissionDenied,
        else => error.IOError,
    };
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
    pub extern fn get_elf_type() elf.Half;
    pub extern fn get_text_vma() elf.Addr;
    pub extern fn get_data_vma() elf.Addr;
    pub extern fn get_text_runtime() elf.Addr;
    pub extern fn get_data_runtime() elf.Addr;
    pub extern fn set_elf_type(val: elf.Half) void;
    pub extern fn set_text_vma(val: elf.Addr) void;
    pub extern fn set_data_vma(val: elf.Addr) void;
    pub extern fn set_text_runtime(val: elf.Addr) void;
    pub extern fn set_data_runtime(val: elf.Addr) void;
    pub extern fn set_sram_got_base(val: elf.Addr) void;
    pub extern fn set_current_symtab(symtab: [*c]elf.Sym) void;
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
        task: task.prex.task_t,
        stack: ?*anyopaque,
        path: [*c]u8,
        msg: *ExecMsg,
        xarg1: [*c]u8,
        xarg2: [*c]u8,
        new_sp: *?*anyopaque,
    ) c_int;
};
