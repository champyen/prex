const ffi = @import("exec_ffi.zig");

/// Error set for the ELF loader, mapped to POSIX errnos at the C-ABI boundary.
pub const ExecError = error{
    OutOfMemory,       // ENOMEM
    InvalidExecutable, // ENOEXEC
    NotFound,          // ENOENT
    PermissionDenied,  // EACCES
    NameTooLong,       // ENAMETOOLONG
    IOError,           // EIO
};

/// Wrap a vm_allocate syscall failure as an OutOfMemory error.
fn vmAllocate(task: ffi.task.prex.task_t, addr: *?*anyopaque, size: usize, anywhere: c_int) ExecError!void {
    if (ffi.task.prex.vm_allocate(task, addr, size, anywhere) != 0) return error.OutOfMemory;
}

/// Wrap a vm_map syscall failure as an InvalidExecutable error.
fn vmMap(task: ffi.task.prex.task_t, addr: ?*anyopaque, size: usize, mapped: *?*anyopaque) ExecError!void {
    if (ffi.task.prex.vm_map(task, addr, size, mapped) != 0) return error.InvalidExecutable;
}

/// Wrap a vm_attribute syscall failure as an InvalidExecutable error.
fn vmAttribute(task: ffi.task.prex.task_t, addr: ?*anyopaque, prot: c_int) ExecError!void {
    if (ffi.task.prex.vm_attribute(task, addr, prot) != 0) return error.InvalidExecutable;
}

/// Wrap an lseek failure as an IOError.
fn seekSet(fd: c_int, offset: c_long) ExecError!void {
    if (ffi.prog.unistd.lseek(fd, offset, ffi.prog.stdio.SEEK_SET) == @as(c_int, -1)) {
        return error.IOError;
    }
}

/// Wrap a read failure as an IOError.
fn readFile(fd: c_int, buf: ?*anyopaque, len: usize) ExecError!void {
    if (ffi.prog.unistd.read(fd, buf, len) < 0) return error.IOError;
}

/// Wrap a malloc failure as an OutOfMemory error.
fn mallocBytes(size: usize) ExecError!*anyopaque {
    return ffi.prog.stdlib.malloc(size) orelse error.OutOfMemory;
}

fn load_exec(ehdr: *ffi.elf.Ehdr, task: ffi.task.prex.task_t, fd: c_int, entry: *ffi.task.prex.vaddr_t) ExecError!void {
    var phdr: *ffi.elf.Phdr = @ptrFromInt(@intFromPtr(ehdr) + @as(usize, @intCast(ehdr.e_phoff)));
    if (@intFromPtr(phdr) == 0) {
        return error.InvalidExecutable;
    }

    var text_start: ffi.task.prex.vaddr_t = @bitCast(@as(isize, -1));
    var text_end: ffi.task.prex.vaddr_t = 0;
    var data_start: ffi.task.prex.vaddr_t = @bitCast(@as(isize, -1));
    var data_end: ffi.task.prex.vaddr_t = 0;

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_phnum))) : (i += 1) {
        if (phdr.p_type != ffi.elf.PT_LOAD or phdr.p_memsz == 0) {
            phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(ffi.elf.Phdr));
            continue;
        }

        if ((phdr.p_flags & ffi.elf.PF_W) == 0) {
            if (phdr.p_vaddr < text_start) text_start = phdr.p_vaddr;
            if (phdr.p_vaddr + phdr.p_memsz > text_end) text_end = phdr.p_vaddr + phdr.p_memsz;
        } else {
            if (phdr.p_vaddr < data_start) data_start = phdr.p_vaddr;
            if (phdr.p_vaddr + phdr.p_memsz > data_end) data_end = phdr.p_vaddr + phdr.p_memsz;
        }
        phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(ffi.elf.Phdr));
    }

    var addr: ?*anyopaque = undefined;
    var size: usize = 0;

    if (text_end > text_start) {
        addr = @ptrFromInt(text_start & ~@as(ffi.task.prex.vaddr_t, @intCast(ffi.task.prex.PAGE_SIZE - 1)));
        size = @intCast((round_page(text_end)) - @intFromPtr(addr));
        try vmAllocate(task, &addr, size, 0);
    }

    if (data_end > data_start) {
        addr = @ptrFromInt(data_start & ~@as(ffi.task.prex.vaddr_t, @intCast(ffi.task.prex.PAGE_SIZE - 1)));
        size = @intCast((round_page(data_end)) - @intFromPtr(addr));
        if (@intFromPtr(addr) < round_page(text_end)) {
            addr = @ptrFromInt(round_page(text_end));
            size = @intCast((round_page(data_end)) - @intFromPtr(addr));
        }
        if (size > 0) {
            try vmAllocate(task, &addr, size, 0);
        }
    }

    phdr = @ptrFromInt(@intFromPtr(ehdr) + @as(usize, @intCast(ehdr.e_phoff)));
    i = 0;
    while (i < @as(c_int, @intCast(ehdr.e_phnum))) : (i += 1) {
        if (phdr.p_type != ffi.elf.PT_LOAD or phdr.p_memsz == 0) {
            phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(ffi.elf.Phdr));
            continue;
        }

        var mapped: ?*anyopaque = @ptrFromInt(phdr.p_vaddr);
        try vmMap(task, @ptrFromInt(phdr.p_vaddr), phdr.p_memsz, &mapped);
        errdefer _ = ffi.task.prex.vm_free(ffi.task.prex.task_self(), mapped);

        if (phdr.p_filesz > 0) {
            try seekSet(fd, @intCast(phdr.p_offset));
            try readFile(fd, mapped, phdr.p_filesz);
        }
        _ = ffi.task.prex.vm_free(ffi.task.prex.task_self(), mapped);
        phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(ffi.elf.Phdr));
    }

    if (text_end > text_start) {
        try vmAttribute(task, @ptrFromInt(text_start & ~@as(ffi.task.prex.vaddr_t, @intCast(ffi.task.prex.PAGE_SIZE - 1))), ffi.task.prex.PROT_READ);
    }

    entry.* = @intCast(ehdr.e_entry);
    _ = ffi.task.prex.sys_debug(ffi.task.prex.DBGC_FLUSHCACHE, null);
}

fn freeRelocTables(ehdr: *ffi.elf.Ehdr, buf: [*c]u8) void {
    const shdr: [*c]ffi.elf.Shdr = @ptrCast(@alignCast(buf));
    const sect_addr_ptr: [*]?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        if (shdr[@intCast(i)].sh_type == ffi.elf.SHT_SYMTAB or
            shdr[@intCast(i)].sh_type == ffi.elf.SHT_RELA or
            shdr[@intCast(i)].sh_type == ffi.elf.SHT_REL)
        {
            if (sect_addr_ptr[@intCast(i)]) |p| {
                ffi.prog.stdlib.free(@ptrCast(p));
            }
        }
    }
}

fn load_reloc(ehdr: *ffi.elf.Ehdr, exec: *ffi.Exec, fd: c_int) ExecError!void {
    const task = exec.task;
    var shdr: [*c]ffi.elf.Shdr = undefined;
    var base: ?*anyopaque = undefined;
    var mapped: ?*anyopaque = undefined;
    var total_size: usize = undefined;
    var load_off: c_ulong = 0;
    var first_text_off: c_ulong = 0xffffffff;
    var first_text_addr: c_ulong = 0;
    var first_data_addr: c_ulong = 0;

    ffi.global.set_elf_type(ehdr.e_type);
    ffi.global.set_text_vma(0);
    ffi.global.set_data_vma(0);
    ffi.global.set_text_runtime(0);
    ffi.global.set_data_runtime(0);

    // Read section header.
    const shdr_size: usize = @as(usize, ehdr.e_shentsize) * @as(usize, ehdr.e_shnum);
    const buf: [*c]u8 = @ptrCast(try mallocBytes(shdr_size));
    defer ffi.prog.stdlib.free(@ptrCast(buf));

    try seekSet(fd, @intCast(ehdr.e_shoff));
    try readFile(fd, @ptrCast(buf), shdr_size);

    // Compute total size and locate the first text/data addresses.
    shdr = @ptrCast(@alignCast(buf));
    total_size = 0;
    var max_addr: c_ulong = 0;
    first_text_addr = 0xffffffff;
    first_data_addr = 0xffffffff;
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        if (shdr.*.sh_flags & ffi.elf.SHF_ALLOC != 0) {
            if (ehdr.e_type == ffi.elf.ET_EXEC) {
                if (shdr.*.sh_flags & ffi.elf.SHF_EXECINSTR != 0) {
                    if (first_text_addr == 0xffffffff)
                        first_text_addr = shdr.*.sh_addr;
                }
                if (shdr.*.sh_flags & ffi.elf.SHF_WRITE != 0) {
                    if (first_data_addr == 0xffffffff)
                        first_data_addr = shdr.*.sh_addr;
                }
                const sect_end = @as(c_ulong, shdr.*.sh_addr) + @as(c_ulong, shdr.*.sh_size);
                if (sect_end > max_addr)
                    max_addr = sect_end;
            } else {
                if (shdr.*.sh_addralign > 0) {
                    const align_mask = @as(usize, shdr.*.sh_addralign) - 1;
                    total_size = (total_size + align_mask) & ~align_mask;
                }
                total_size += @as(usize, shdr.*.sh_size);
            }
        }
        shdr += 1;
    }

    if (ehdr.e_type == ffi.elf.ET_EXEC) {
        if (first_text_addr == 0xffffffff or max_addr == 0) {
            return error.InvalidExecutable;
        }
        total_size = @intCast(max_addr - first_text_addr);
    } else {
        if (total_size == 0) {
            return error.InvalidExecutable;
        }
        first_text_addr = 0;
    }

    try vmAllocate(task, &base, total_size, 1);
    vmMap(task, base, total_size, &mapped) catch return error.OutOfMemory;
    defer _ = ffi.task.prex.vm_free(ffi.task.prex.task_self(), mapped);
    defer freeRelocTables(ehdr, buf);

    const sect_addr_ptr: [*]?[*]u8 = @ptrCast(ffi.global.sect_addr_get());

    // Copy sections
    shdr = @ptrCast(@alignCast(buf));
    load_off = 0;
    i = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        sect_addr_ptr[@intCast(i)] = null;
        if (shdr.*.sh_flags & ffi.elf.SHF_ALLOC != 0) {
            if (ehdr.e_type == ffi.elf.ET_EXEC) {
                load_off = @as(c_ulong, shdr.*.sh_addr) -% first_text_addr;
            } else {
                // Align the current load offset
                if (shdr.*.sh_addralign > 0) {
                    const align_mask = @as(c_ulong, shdr.*.sh_addralign) - 1;
                    load_off = (load_off + align_mask) & ~align_mask;
                }
                if (shdr.*.sh_flags & ffi.elf.SHF_EXECINSTR != 0) {
                    if (first_text_off == 0xffffffff) {
                        first_text_off = load_off;
                        first_text_addr = shdr.*.sh_addr;
                    }
                }
            }
            const addr: [*c]u8 = @ptrFromInt(@intFromPtr(mapped) +% @as(usize, @intCast(load_off)));

            if (shdr.*.sh_type != ffi.elf.SHT_NOBITS) {
                if (shdr.*.sh_size > 0) {
                    try seekSet(fd, @intCast(shdr.*.sh_offset));
                    try readFile(fd, @ptrCast(addr), shdr.*.sh_size);
                }
                sect_addr_ptr[@intCast(i)] = addr;
                if (ehdr.e_type != ffi.elf.ET_EXEC)
                    load_off += shdr.*.sh_size;
            } else { // SHT_NOBITS
                if (shdr.*.sh_size > 0)
                    @memset(addr[0..shdr.*.sh_size], 0);
                sect_addr_ptr[@intCast(i)] = addr;
                if (ehdr.e_type != ffi.elf.ET_EXEC)
                    load_off += shdr.*.sh_size;
            }
        } else if (shdr.*.sh_type == ffi.elf.SHT_SYMTAB or shdr.*.sh_type == ffi.elf.SHT_RELA or shdr.*.sh_type == ffi.elf.SHT_REL) {
            if (shdr.*.sh_size > 0) {
                const taddr: [*c]u8 = @ptrCast(try mallocBytes(shdr.*.sh_size));
                errdefer ffi.prog.stdlib.free(@ptrCast(taddr));
                try seekSet(fd, @intCast(shdr.*.sh_offset));
                try readFile(fd, @ptrCast(taddr), shdr.*.sh_size);
                sect_addr_ptr[@intCast(i)] = taddr;
            }
        }
        shdr += 1;
    }

    if (comptime ffi.is_arm) {
        // Locate GOT base
        ffi.global.set_sram_got_base(0);
        exec.gp = null;
        shdr = @ptrCast(@alignCast(buf));
        if (ehdr.e_shstrndx != ffi.elf.SHN_UNDEF) {
            const shstr_hdr: *ffi.elf.Shdr = @ptrCast(shdr + @as(usize, @intCast(ehdr.e_shstrndx)));
            if (ffi.prog.stdlib.malloc(shstr_hdr.sh_size)) |mem| {
                const shstrtab: [*c]u8 = @ptrCast(mem);
                if (ffi.prog.unistd.lseek(fd, @intCast(shstr_hdr.sh_offset), ffi.prog.stdio.SEEK_SET) >= 0 and
                    ffi.prog.unistd.read(fd, @ptrCast(shstrtab), shstr_hdr.sh_size) >= 0)
                {
                    i = 0;
                    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
                        const name_ptr = shstrtab + @as(usize, @intCast(shdr[@intCast(i)].sh_name));
                        if (shdr[@intCast(i)].sh_type == ffi.elf.SHT_PROGBITS and
                            name_ptr[0] == '.' and name_ptr[1] == 'g' and name_ptr[2] == 'o' and
                            name_ptr[3] == 't' and name_ptr[4] == 0)
                        {
                            const got_addr: ffi.elf.Addr = @intCast(@intFromPtr(sect_addr_ptr[@intCast(i)].?));
                            ffi.global.set_sram_got_base(got_addr);
                            exec.gp = @ptrFromInt(@intFromPtr(base) +% (@as(usize, got_addr) -% @intFromPtr(mapped)));
                            break;
                        }
                    }
                }
                ffi.prog.stdlib.free(@ptrCast(shstrtab));
            }
        }
    }

    if (ehdr.e_type == ffi.elf.ET_EXEC) {
        ffi.global.set_text_vma(first_text_addr);
        ffi.global.set_data_vma(first_data_addr);
        ffi.global.set_text_runtime(@intCast(@intFromPtr(mapped)));
        shdr = @ptrCast(@alignCast(buf));
        i = 0;
        while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
            if (shdr.*.sh_flags & ffi.elf.SHF_ALLOC != 0) {
                if (shdr.*.sh_flags & ffi.elf.SHF_WRITE != 0) {
                    if (ffi.global.get_data_runtime() == 0)
                        ffi.global.set_data_runtime(@intCast(@intFromPtr(sect_addr_ptr[@intCast(i)].?)));
                }
            }
            shdr += 1;
        }
    }

    // Process relocation
    shdr = @ptrCast(@alignCast(buf));
    i = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        if (shdr.*.sh_type == ffi.elf.SHT_REL or shdr.*.sh_type == ffi.elf.SHT_RELA) {
            const rel_data: [*c]u8 = if (sect_addr_ptr[@intCast(i)]) |p| @ptrCast(p) else @ptrFromInt(0);
            if (relocate_section(shdr, rel_data) != 0)
                return error.IOError;
        }
        shdr += 1;
    }

    if (ehdr.e_type == ffi.elf.ET_EXEC) {
        exec.entry = @intCast(@intFromPtr(base) +% (@as(usize, ehdr.e_entry) -% @as(usize, @intCast(first_text_addr))));
    } else {
        if (first_text_off == 0xffffffff) {
            first_text_off = 0;
            first_text_addr = 0;
        }
        exec.entry = @intCast(@intFromPtr(base) +% first_text_off +% (@as(usize, ehdr.e_entry) -% @as(usize, @intCast(first_text_addr))));
    }

    _ = ffi.task.prex.sys_debug(ffi.task.prex.DBGC_FLUSHCACHE, null);
}

inline fn round_page(x: anytype) usize {
    return (@as(usize, @intCast(x)) + ffi.task.prex.PAGE_SIZE - 1) & ~@as(usize, ffi.task.prex.PAGE_SIZE - 1);
}

fn relocate_section_rela(sym_table: [*c]ffi.elf.Sym, rela: [*c]ffi.elf.Rela, target_sect: [*c]u8, nr_reloc: c_int) c_int {
    const is_exec = ffi.global.get_elf_type() == ffi.elf.ET_EXEC;
    const text_vma = ffi.global.get_text_vma();
    const data_vma = ffi.global.get_data_vma();
    const text_runtime = ffi.global.get_text_runtime();
    const data_runtime = ffi.global.get_data_runtime();

    var r = rela;
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const info: ffi.elf.RelInfo = @bitCast(r[0].r_info);
        const sym = &sym_table[@intCast(info.sym)];
        if (info.sym == ffi.elf.STN_UNDEF) {
            // Empty symbol used for R_ARM_V4BX, etc
        } else if (sym.st_shndx != ffi.elf.STN_UNDEF) {
            var sym_val: ffi.elf.Addr = sym.st_value;
            if (is_exec) {
                if (sym_val < data_vma) {
                    sym_val = text_runtime +% (sym_val -% text_vma);
                } else {
                    sym_val = data_runtime +% (sym_val -% data_vma);
                }
            } else {
                const sect_addr_ptr: [*]const ?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
                const base: usize = if (sect_addr_ptr[@intCast(sym.st_shndx)]) |p| @intFromPtr(p) else 0;
                sym_val = @intCast(base +% sym.st_value);
            }
            if (ffi.elf.relocate_rela(r, sym_val, target_sect) != 0) {
                return -1;
            }
        } else if (@as(ffi.elf.Elf32_SymInfo, @bitCast(sym.st_info)).bind == ffi.elf.STB_WEAK) {
            // undefined weak symbol for rela[i]
        }
        r += 1;
    }
    return 0;
}

fn relocate_section_rel(sym_table: [*c]ffi.elf.Sym, rel: [*c]ffi.elf.Rel, target_sect: [*c]u8, nr_reloc: c_int) c_int {
    const is_exec = ffi.global.get_elf_type() == ffi.elf.ET_EXEC;
    const text_vma = ffi.global.get_text_vma();
    const data_vma = ffi.global.get_data_vma();
    const text_runtime = ffi.global.get_text_runtime();
    const data_runtime = ffi.global.get_data_runtime();

    var r = rel;
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const info: ffi.elf.RelInfo = @bitCast(r[0].r_info);
        const sym = &sym_table[@intCast(info.sym)];
        if (info.sym == ffi.elf.STN_UNDEF) {
            // Empty symbol used for R_ARM_V4BX, etc
        } else if (sym.st_shndx != ffi.elf.STN_UNDEF) {
            var sym_val: ffi.elf.Addr = sym.st_value;
            if (is_exec) {
                if (sym_val < data_vma) {
                    sym_val = text_runtime +% (sym_val -% text_vma);
                } else {
                    sym_val = data_runtime +% (sym_val -% data_vma);
                }
            } else {
                const sect_addr_ptr: [*]const ?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
                const base: usize = if (sect_addr_ptr[@intCast(sym.st_shndx)]) |p| @intFromPtr(p) else 0;
                sym_val = @intCast(base +% sym.st_value);
            }
            if (ffi.elf.relocate_rel(r, sym_val, target_sect) != 0) {
                return -1;
            }
        } else if (@as(ffi.elf.Elf32_SymInfo, @bitCast(sym.st_info)).bind == ffi.elf.STB_WEAK) {
            // undefined weak symbol for rel[i]
        }
        r += 1;
    }
    return 0;
}

fn relocate_section(shdr: [*c]ffi.elf.Shdr, rel_data: [*c]u8) c_int {
    if (shdr.*.sh_entsize == 0) {
        return 0;
    }

    const sect_addr_ptr: [*]const ?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
    const target_sect: [*c]u8 = sect_addr_ptr[@intCast(shdr.*.sh_info)] orelse return 0;
    const sym_table: [*c]ffi.elf.Sym = @ptrCast(@alignCast(sect_addr_ptr[@intCast(shdr.*.sh_link)] orelse return -1));
    ffi.global.set_current_symtab(sym_table);

    const nr_reloc: c_int = @intCast(shdr.*.sh_size / shdr.*.sh_entsize);
    var error_code: c_int = undefined;
    switch (shdr.*.sh_type) {
        ffi.elf.SHT_REL => error_code = relocate_section_rel(sym_table, @ptrFromInt(@intFromPtr(rel_data)), target_sect, nr_reloc),
        ffi.elf.SHT_RELA => error_code = relocate_section_rela(sym_table, @ptrFromInt(@intFromPtr(rel_data)), target_sect, nr_reloc),
        else => error_code = -1,
    }
    return error_code;
}

pub export fn elf_init() void {}

pub export fn elf_probe(exec: *ffi.Exec) c_int {
    const ehdr: *ffi.elf.Ehdr = @ptrCast(@alignCast(exec.*.header));

    // Check ELF magic
    if (ehdr.e_ident[ffi.elf.EI_MAG0] != ffi.elf.ELFMAG0 or
        ehdr.e_ident[ffi.elf.EI_MAG1] != ffi.elf.ELFMAG1 or
        ehdr.e_ident[ffi.elf.EI_MAG2] != ffi.elf.ELFMAG2 or
        ehdr.e_ident[ffi.elf.EI_MAG3] != ffi.elf.ELFMAG3)
    {
        return ffi.PROBE_ERROR;
    }

    if (comptime ffi.config.MMU) {
        if (ehdr.e_type != ffi.elf.ET_EXEC) {
            return ffi.PROBE_ERROR;
        }
    } else {
        if (comptime ffi.config.ARMV8M) {
            if (ehdr.e_type != ffi.elf.ET_EXEC and ehdr.e_type != ffi.elf.ET_REL) {
                return ffi.PROBE_ERROR;
            }
        } else {
            if (ehdr.e_type != ffi.elf.ET_REL) {
                return ffi.PROBE_ERROR;
            }
        }
    }

    return ffi.PROBE_MATCH;
}

pub export fn elf_load(exec: *ffi.Exec) c_int {
    return ffi.catchToCError(elfLoad(exec));
}

fn elfLoad(exec: *ffi.Exec) ExecError!void {
    // Check permission
    if (ffi.prog.unistd.access(exec.path, ffi.prog.unistd.X_OK) == -1) {
        return error.PermissionDenied;
    }

    const fd = ffi.prog.fcntl.open(exec.path, ffi.prog.fcntl.O_RDONLY);
    if (fd == -1) {
        return error.NotFound;
    }
    defer _ = ffi.prog.unistd.close(fd);

    if (comptime ffi.config.MMU) {
        try load_exec(@ptrCast(@alignCast(exec.header)), exec.task, fd, &exec.entry);
    } else {
        try load_reloc(@ptrCast(@alignCast(exec.header)), exec, fd);
    }
}
