const ffi = @import("exec_ffi.zig");
const c = ffi.raw;

fn load_exec(ehdr: *c.Elf32_Ehdr, task: c.task_t, fd: c_int, entry: *c.vaddr_t) c_int {
    var phdr: *c.Elf32_Phdr = @ptrFromInt(@intFromPtr(ehdr) + @as(usize, @intCast(ehdr.e_phoff)));
    if (@intFromPtr(phdr) == 0) {
        return ffi.Errno.ENOEXEC;
    }

    var text_start: c.vaddr_t = @bitCast(@as(isize, -1));
    var text_end: c.vaddr_t = 0;
    var data_start: c.vaddr_t = @bitCast(@as(isize, -1));
    var data_end: c.vaddr_t = 0;

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_phnum))) : (i += 1) {
        if (phdr.p_type != c.PT_LOAD or phdr.p_memsz == 0) {
            phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(c.Elf32_Phdr));
            continue;
        }

        if ((phdr.p_flags & c.PF_W) == 0) {
            if (phdr.p_vaddr < text_start) text_start = phdr.p_vaddr;
            if (phdr.p_vaddr + phdr.p_memsz > text_end) text_end = phdr.p_vaddr + phdr.p_memsz;
        } else {
            if (phdr.p_vaddr < data_start) data_start = phdr.p_vaddr;
            if (phdr.p_vaddr + phdr.p_memsz > data_end) data_end = phdr.p_vaddr + phdr.p_memsz;
        }
        phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(c.Elf32_Phdr));
    }

    var addr: ?*anyopaque = undefined;
    var size: usize = 0;
    var mapped: ?*anyopaque = undefined;

    if (text_end > text_start) {
        addr = @ptrFromInt(text_start & ~@as(c.vaddr_t, @intCast(c.PAGE_SIZE - 1)));
        size = @intCast((round_page(text_end)) - @intFromPtr(addr));
        if (c.vm_allocate(task, &addr, size, 0) != 0) {
            return ffi.Errno.ENOMEM;
        }
    }

    if (data_end > data_start) {
        addr = @ptrFromInt(data_start & ~@as(c.vaddr_t, @intCast(c.PAGE_SIZE - 1)));
        size = @intCast((round_page(data_end)) - @intFromPtr(addr));
        if (@intFromPtr(addr) < round_page(text_end)) {
            addr = @ptrFromInt(round_page(text_end));
            size = @intCast((round_page(data_end)) - @intFromPtr(addr));
        }
        if (size > 0 and c.vm_allocate(task, &addr, size, 0) != 0) {
            return ffi.Errno.ENOMEM;
        }
    }

    phdr = @ptrFromInt(@intFromPtr(ehdr) + @as(usize, @intCast(ehdr.e_phoff)));
    i = 0;
    while (i < @as(c_int, @intCast(ehdr.e_phnum))) : (i += 1) {
        if (phdr.p_type != c.PT_LOAD or phdr.p_memsz == 0) {
            phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(c.Elf32_Phdr));
            continue;
        }

        mapped = @ptrFromInt(phdr.p_vaddr);
        if (c.vm_map(task, @ptrFromInt(phdr.p_vaddr), phdr.p_memsz, &mapped) != 0) {
            return ffi.Errno.ENOEXEC;
        }

        if (phdr.p_filesz > 0) {
            if (c.lseek(fd, @intCast(phdr.p_offset), c.SEEK_SET) == @as(c_int, -1)) {
                _ = c.vm_free(c.task_self(), mapped);
                return ffi.Errno.EIO;
            }
            if (c.read(fd, mapped, phdr.p_filesz) < 0) {
                _ = c.vm_free(c.task_self(), mapped);
                return ffi.Errno.EIO;
            }
        }
        _ = c.vm_free(c.task_self(), mapped);
        phdr = @ptrFromInt(@intFromPtr(phdr) + @sizeOf(c.Elf32_Phdr));
    }

    if (text_end > text_start) {
        if (c.vm_attribute(task, @ptrFromInt(text_start & ~@as(c.vaddr_t, @intCast(c.PAGE_SIZE - 1))), c.PROT_READ) != 0) {
            return ffi.Errno.ENOEXEC;
        }
    }

    entry.* = @intCast(ehdr.e_entry);
    _ = c.sys_debug(c.DBGC_FLUSHCACHE, null);
    return 0;
}

fn freeRelocTables(ehdr: *c.Elf32_Ehdr, buf: [*c]u8) void {
    const shdr: [*c]c.Elf32_Shdr = @ptrCast(@alignCast(buf));
    const sect_addr_ptr: [*]?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        if (shdr[@intCast(i)].sh_type == c.SHT_SYMTAB or
            shdr[@intCast(i)].sh_type == c.SHT_RELA or
            shdr[@intCast(i)].sh_type == c.SHT_REL)
        {
            if (sect_addr_ptr[@intCast(i)]) |p| {
                c.free(@ptrCast(p));
            }
        }
    }
}

fn finishReloc(ehdr: *c.Elf32_Ehdr, buf: [*c]u8, mapped: ?*anyopaque, error_code: c_int) c_int {
    freeRelocTables(ehdr, buf);
    _ = c.vm_free(c.task_self(), mapped);
    c.free(@ptrCast(buf));
    return error_code;
}

fn load_reloc(ehdr: *c.Elf32_Ehdr, exec: *ffi.Exec, fd: c_int) c_int {
    const task = exec.task;
    var shdr: [*c]c.Elf32_Shdr = undefined;
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
    const buf: [*c]u8 = @ptrCast(c.malloc(shdr_size) orelse return ffi.Errno.ENOMEM);

    if (c.lseek(fd, @intCast(ehdr.e_shoff), c.SEEK_SET) < 0) {
        c.free(@ptrCast(buf));
        return ffi.Errno.EIO;
    }
    if (c.read(fd, @ptrCast(buf), shdr_size) < 0) {
        c.free(@ptrCast(buf));
        return ffi.Errno.EIO;
    }

    // Compute total size and locate the first text/data addresses.
    shdr = @ptrCast(@alignCast(buf));
    total_size = 0;
    var max_addr: c_ulong = 0;
    first_text_addr = 0xffffffff;
    first_data_addr = 0xffffffff;
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        if (shdr.*.sh_flags & c.SHF_ALLOC != 0) {
            if (ehdr.e_type == c.ET_EXEC) {
                if (shdr.*.sh_flags & c.SHF_EXECINSTR != 0) {
                    if (first_text_addr == 0xffffffff)
                        first_text_addr = shdr.*.sh_addr;
                }
                if (shdr.*.sh_flags & c.SHF_WRITE != 0) {
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

    if (ehdr.e_type == c.ET_EXEC) {
        if (first_text_addr == 0xffffffff or max_addr == 0) {
            c.free(@ptrCast(buf));
            return ffi.Errno.ENOEXEC;
        }
        total_size = @intCast(max_addr - first_text_addr);
    } else {
        if (total_size == 0) {
            c.free(@ptrCast(buf));
            return ffi.Errno.ENOEXEC;
        }
        first_text_addr = 0;
    }

    if (c.vm_allocate(task, &base, total_size, 1) != 0) {
        c.free(@ptrCast(buf));
        return ffi.Errno.ENOMEM;
    }
    if (c.vm_map(task, base, total_size, &mapped) != 0) {
        c.free(@ptrCast(buf));
        return ffi.Errno.ENOMEM;
    }

    const sect_addr_ptr: [*]?[*]u8 = @ptrCast(ffi.global.sect_addr_get());

    // Copy sections
    shdr = @ptrCast(@alignCast(buf));
    load_off = 0;
    i = 0;
    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
        sect_addr_ptr[@intCast(i)] = null;
        if (shdr.*.sh_flags & c.SHF_ALLOC != 0) {
            if (ehdr.e_type == c.ET_EXEC) {
                load_off = @as(c_ulong, shdr.*.sh_addr) -% first_text_addr;
            } else {
                // Align the current load offset
                if (shdr.*.sh_addralign > 0) {
                    const align_mask = @as(c_ulong, shdr.*.sh_addralign) - 1;
                    load_off = (load_off + align_mask) & ~align_mask;
                }
                if (shdr.*.sh_flags & c.SHF_EXECINSTR != 0) {
                    if (first_text_off == 0xffffffff) {
                        first_text_off = load_off;
                        first_text_addr = shdr.*.sh_addr;
                    }
                }
            }
            const addr: [*c]u8 = @ptrFromInt(@intFromPtr(mapped) +% @as(usize, @intCast(load_off)));

            if (shdr.*.sh_type != c.SHT_NOBITS) {
                if (shdr.*.sh_size > 0) {
                    if (c.lseek(fd, @intCast(shdr.*.sh_offset), c.SEEK_SET) < 0)
                        return finishReloc(ehdr, buf, mapped, ffi.Errno.EIO);
                    if (c.read(fd, @ptrCast(addr), shdr.*.sh_size) < 0)
                        return finishReloc(ehdr, buf, mapped, ffi.Errno.EIO);
                }
                sect_addr_ptr[@intCast(i)] = addr;
                if (ehdr.e_type != c.ET_EXEC)
                    load_off += shdr.*.sh_size;
            } else { // SHT_NOBITS
                if (shdr.*.sh_size > 0)
                    @memset(addr[0..shdr.*.sh_size], 0);
                sect_addr_ptr[@intCast(i)] = addr;
                if (ehdr.e_type != c.ET_EXEC)
                    load_off += shdr.*.sh_size;
            }
        } else if (shdr.*.sh_type == c.SHT_SYMTAB or shdr.*.sh_type == c.SHT_RELA or shdr.*.sh_type == c.SHT_REL) {
            if (shdr.*.sh_size > 0) {
                const taddr: [*c]u8 = @ptrCast(c.malloc(shdr.*.sh_size) orelse
                    return finishReloc(ehdr, buf, mapped, ffi.Errno.ENOMEM));
                if (c.lseek(fd, @intCast(shdr.*.sh_offset), c.SEEK_SET) < 0)
                    return finishReloc(ehdr, buf, mapped, ffi.Errno.EIO);
                if (c.read(fd, @ptrCast(taddr), shdr.*.sh_size) < 0)
                    return finishReloc(ehdr, buf, mapped, ffi.Errno.EIO);
                sect_addr_ptr[@intCast(i)] = taddr;
            }
        }
        shdr += 1;
    }

    if (comptime @hasDecl(c, "__arm__")) {
        // Locate GOT base
        ffi.global.set_sram_got_base(0);
        exec.gp = null;
        shdr = @ptrCast(@alignCast(buf));
        if (ehdr.e_shstrndx != c.SHN_UNDEF) {
            const shstr_hdr: *c.Elf32_Shdr = @ptrCast(shdr + @as(usize, @intCast(ehdr.e_shstrndx)));
            if (c.malloc(shstr_hdr.sh_size)) |mem| {
                const shstrtab: [*c]u8 = @ptrCast(mem);
                if (c.lseek(fd, @intCast(shstr_hdr.sh_offset), c.SEEK_SET) >= 0 and
                    c.read(fd, @ptrCast(shstrtab), shstr_hdr.sh_size) >= 0)
                {
                    i = 0;
                    while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
                        const name_ptr = shstrtab + @as(usize, @intCast(shdr[@intCast(i)].sh_name));
                        if (shdr[@intCast(i)].sh_type == c.SHT_PROGBITS and
                            name_ptr[0] == '.' and name_ptr[1] == 'g' and name_ptr[2] == 'o' and
                            name_ptr[3] == 't' and name_ptr[4] == 0)
                        {
                            const got_addr: c.Elf32_Addr = @intCast(@intFromPtr(sect_addr_ptr[@intCast(i)].?));
                            ffi.global.set_sram_got_base(got_addr);
                            exec.gp = @ptrFromInt(@intFromPtr(base) +% (@as(usize, got_addr) -% @intFromPtr(mapped)));
                            break;
                        }
                    }
                }
                c.free(@ptrCast(shstrtab));
            }
        }
    }

    if (ehdr.e_type == c.ET_EXEC) {
        ffi.global.set_text_vma(first_text_addr);
        ffi.global.set_data_vma(first_data_addr);
        ffi.global.set_text_runtime(@intCast(@intFromPtr(mapped)));
        shdr = @ptrCast(@alignCast(buf));
        i = 0;
        while (i < @as(c_int, @intCast(ehdr.e_shnum))) : (i += 1) {
            if (shdr.*.sh_flags & c.SHF_ALLOC != 0) {
                if (shdr.*.sh_flags & c.SHF_WRITE != 0) {
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
        if (shdr.*.sh_type == c.SHT_REL or shdr.*.sh_type == c.SHT_RELA) {
            const rel_data: [*c]u8 = if (sect_addr_ptr[@intCast(i)]) |p| @ptrCast(p) else @ptrFromInt(0);
            if (relocate_section(shdr, rel_data) != 0)
                return finishReloc(ehdr, buf, mapped, ffi.Errno.EIO);
        }
        shdr += 1;
    }

    if (ehdr.e_type == c.ET_EXEC) {
        exec.entry = @intCast(@intFromPtr(base) +% (@as(usize, ehdr.e_entry) -% @as(usize, @intCast(first_text_addr))));
    } else {
        if (first_text_off == 0xffffffff) {
            first_text_off = 0;
            first_text_addr = 0;
        }
        exec.entry = @intCast(@intFromPtr(base) +% first_text_off +% (@as(usize, ehdr.e_entry) -% @as(usize, @intCast(first_text_addr))));
    }

    _ = c.sys_debug(c.DBGC_FLUSHCACHE, null);
    return finishReloc(ehdr, buf, mapped, 0);
}

inline fn round_page(x: anytype) usize {
    return (@as(usize, @intCast(x)) + c.PAGE_SIZE - 1) & ~@as(usize, c.PAGE_SIZE - 1);
}

pub export fn relocate_section_rela(sym_table: [*c]c.Elf32_Sym, rela: [*c]c.Elf32_Rela, target_sect: [*c]u8, nr_reloc: c_int) callconv(.c) c_int {
    const is_exec = ffi.global.get_elf_type() == c.ET_EXEC;
    const text_vma = ffi.global.get_text_vma();
    const data_vma = ffi.global.get_data_vma();
    const text_runtime = ffi.global.get_text_runtime();
    const data_runtime = ffi.global.get_data_runtime();

    var r = rela;
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const sym = &sym_table[@intCast(r[0].r_info >> 8)];
        if (@as(usize, r[0].r_info >> 8) == c.STN_UNDEF) {
            // Empty symbol used for R_ARM_V4BX, etc
        } else if (sym.st_shndx != c.STN_UNDEF) {
            var sym_val: c.Elf32_Addr = sym.st_value;
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
            if (c.relocate_rela(r, sym_val, target_sect) != 0) {
                return -1;
            }
        } else if ((sym.st_info >> 4) == c.STB_WEAK) {
            // undefined weak symbol for rela[i]
        }
        r += 1;
    }
    return 0;
}

pub export fn relocate_section_rel(sym_table: [*c]c.Elf32_Sym, rel: [*c]c.Elf32_Rel, target_sect: [*c]u8, nr_reloc: c_int) callconv(.c) c_int {
    const is_exec = ffi.global.get_elf_type() == c.ET_EXEC;
    const text_vma = ffi.global.get_text_vma();
    const data_vma = ffi.global.get_data_vma();
    const text_runtime = ffi.global.get_text_runtime();
    const data_runtime = ffi.global.get_data_runtime();

    var r = rel;
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const sym = &sym_table[@intCast(r[0].r_info >> 8)];
        if (@as(usize, r[0].r_info >> 8) == c.STN_UNDEF) {
            // Empty symbol used for R_ARM_V4BX, etc
        } else if (sym.st_shndx != c.STN_UNDEF) {
            var sym_val: c.Elf32_Addr = sym.st_value;
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
            if (c.relocate_rel(r, sym_val, target_sect) != 0) {
                return -1;
            }
        } else if ((sym.st_info >> 4) == c.STB_WEAK) {
            // undefined weak symbol for rel[i]
        }
        r += 1;
    }
    return 0;
}

pub export fn relocate_section(shdr: [*c]c.Elf32_Shdr, rel_data: [*c]u8) callconv(.c) c_int {
    if (shdr.*.sh_entsize == 0) {
        return 0;
    }

    const sect_addr_ptr: [*]const ?[*]u8 = @ptrCast(ffi.global.sect_addr_get());
    const target_sect: [*c]u8 = sect_addr_ptr[@intCast(shdr.*.sh_info)] orelse return 0;
    const sym_table: [*c]c.Elf32_Sym = @ptrCast(@alignCast(sect_addr_ptr[@intCast(shdr.*.sh_link)] orelse return -1));
    ffi.global.set_current_symtab(sym_table);

    const nr_reloc: c_int = @intCast(shdr.*.sh_size / shdr.*.sh_entsize);
    var error_code: c_int = undefined;
    switch (shdr.*.sh_type) {
        c.SHT_REL => error_code = relocate_section_rel(sym_table, @ptrFromInt(@intFromPtr(rel_data)), target_sect, nr_reloc),
        c.SHT_RELA => error_code = relocate_section_rela(sym_table, @ptrFromInt(@intFromPtr(rel_data)), target_sect, nr_reloc),
        else => error_code = -1,
    }
    return error_code;
}

pub export fn elf_init() void {}

pub export fn elf_probe(exec: *ffi.Exec) c_int {
    const ehdr: *c.Elf32_Ehdr = @ptrCast(@alignCast(exec.*.header));

    // Check ELF magic
    if (ehdr.e_ident[c.EI_MAG0] != c.ELFMAG0 or
        ehdr.e_ident[c.EI_MAG1] != c.ELFMAG1 or
        ehdr.e_ident[c.EI_MAG2] != c.ELFMAG2 or
        ehdr.e_ident[c.EI_MAG3] != c.ELFMAG3)
    {
        return c.PROBE_ERROR;
    }

    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        if (ehdr.e_type != c.ET_EXEC) {
            return c.PROBE_ERROR;
        }
    } else {
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            if (ehdr.e_type != c.ET_EXEC and ehdr.e_type != c.ET_REL) {
                return c.PROBE_ERROR;
            }
        } else {
            if (ehdr.e_type != c.ET_REL) {
                return c.PROBE_ERROR;
            }
        }
    }

    return c.PROBE_MATCH;
}

pub export fn elf_load(exec: *ffi.Exec) c_int {
    // Check permission
    if (c.access(exec.path, c.X_OK) == -1) {
        return c.errno;
    }

    const fd = c.open(exec.path, c.O_RDONLY);
    if (fd == -1) {
        return c.ENOENT;
    }

    var error_code: c_int = undefined;
    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        error_code = load_exec(@ptrCast(@alignCast(exec.header)), exec.task, fd, &exec.entry);
    } else {
        error_code = load_reloc(@ptrCast(@alignCast(exec.header)), exec, fd);
    }

    _ = c.close(fd);
    return error_code;
}
