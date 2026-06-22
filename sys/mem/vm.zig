const std = @import("std");
const c = @import("c").c;
const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const mem = ffi.mem;
const kutil = ffi.kutil;
const sched = ffi.sched;
const task = ffi.task;
const page = ffi.page;
const kmem = ffi.kmem;
const smp = ffi.smp;
const thread = ffi.thread;

// ---------------------------------------------------------------------------
// Page size helpers
// ---------------------------------------------------------------------------






// ---------------------------------------------------------------------------
// Thread / task accessors
// ---------------------------------------------------------------------------



// ---------------------------------------------------------------------------
// FFI Structures
// ---------------------------------------------------------------------------




// ---------------------------------------------------------------------------
// MMU stubs
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// C memcpy/memset stubs (for page copy/zero-fill)
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Kernel map (module-level)
// ---------------------------------------------------------------------------

var kernel_map: mem.VmMap = undefined;

// ---------------------------------------------------------------------------
// Segment list helpers (operate on circular doubly-linked list)
// ---------------------------------------------------------------------------

fn seg_init(seg: *mem.Segment) void {
    seg.next = @as(*mem.Segment, @ptrCast(seg));
    seg.prev = @as(*mem.Segment, @ptrCast(seg));
    seg.sh_next = @as(*mem.Segment, @ptrCast(seg));
    seg.sh_prev = @as(*mem.Segment, @ptrCast(seg));
    seg.addr = @intCast(c.PAGE_SIZE);
    seg.phys = 0;
    seg.size = @intCast(c.USERLIMIT - c.PAGE_SIZE);
    seg.flags = c.SEG_FREE;
}

fn seg_create(prev: *mem.Segment, addr: kern.Vaddr, size: usize) ?*mem.Segment {
    const seg_ptr = kmem.alloc(@sizeOf(mem.Segment)) orelse return null;
    const seg: *mem.Segment = @ptrCast(@alignCast(seg_ptr));

    seg.addr = addr;
    seg.size = size;
    seg.phys = 0;
    seg.flags = c.SEG_FREE;
    seg.sh_next = seg;
    seg.sh_prev = seg;

    seg.next = prev.next;
    seg.prev = prev;
    prev.next.*.prev = seg;
    prev.next = seg;

    return seg;
}

fn seg_delete(head: *mem.Segment, seg: *mem.Segment) void {
    if (seg.flags & c.SEG_SHARED != 0) {
        seg.sh_prev.*.sh_next = seg.sh_next;
        seg.sh_next.*.sh_prev = seg.sh_prev;
        if (seg.sh_prev == seg.sh_next) {
            seg.sh_prev.*.flags &= ~c.SEG_SHARED;
        }
    }
    if (head != seg) {
        kmem.free(@ptrCast(@alignCast(seg)));
    }
}

fn seg_lookup(head: *mem.Segment, addr: kern.Vaddr, size: usize) ?*mem.Segment {
    var seg = head;
    while (true) {
        if (seg.addr <= addr and seg.addr + seg.size >= addr + size) {
            return seg;
        }
        seg = seg.next;
        if (seg == head) break;
    }
    return null;
}

fn seg_alloc(head: *mem.Segment, size: usize) ?*mem.Segment {
    var seg = head;
    while (true) {
        if (seg.flags & c.SEG_FREE != 0 and seg.size >= size) {
            if (seg.size != size) {
                _ = seg_create(seg, seg.addr + size, seg.size - size) orelse return null;
            }
            seg.size = size;
            return seg;
        }
        seg = seg.next;
        if (seg == head) break;
    }
    return null;
}

fn seg_free(head: *mem.Segment, seg: *mem.Segment) void {
    std.debug.assert(seg.flags != c.SEG_FREE);

    seg.flags = c.SEG_FREE;

    if (seg.flags & c.SEG_SHARED != 0) {
        seg.sh_prev.*.sh_next = seg.sh_next;
        seg.sh_next.*.sh_prev = seg.sh_prev;
        if (seg.sh_prev == seg.sh_next) {
            seg.sh_prev.*.flags &= ~c.SEG_SHARED;
        }
    }

    const next = seg.next;
    if (next != head and next.*.flags & c.SEG_FREE != 0) {
        seg.next = next.*.next;
        next.*.next.*.prev = seg;
        seg.size += next.*.size;
        kmem.free(@ptrCast(@alignCast(next)));
    }

    const prev = seg.prev;
    if (seg != head and prev.*.flags & c.SEG_FREE != 0) {
        prev.*.next = seg.next;
        seg.next.*.prev = prev;
        prev.*.size += seg.size;
        kmem.free(@ptrCast(@alignCast(seg)));
    }
}

fn seg_reserve(head: *mem.Segment, addr: kern.Vaddr, size: usize) ?*mem.Segment {
    var seg = seg_lookup(head, addr, size) orelse return null;
    if (seg.flags & c.SEG_FREE == 0) return null;

    var prev: ?*mem.Segment = null;
    if (seg.addr != addr) {
        prev = seg;
        const diff: usize = @intCast(addr - seg.addr);
        seg = seg_create(prev.?, addr, prev.?.size - diff) orelse return null;
        prev.?.size = diff;
    }

    if (seg.size != size) {
        _ = seg_create(seg, seg.addr + size, seg.size - size) orelse {
            if (prev) |_| {
                seg_free(head, seg);
            }
            return null;
        };
        seg.size = size;
    }
    seg.flags = 0;
    return seg;
}

// ---------------------------------------------------------------------------
// Internal do_* helpers
// ---------------------------------------------------------------------------

fn do_allocate(vm_map: *mem.VmMap, addr: *?*anyopaque, size: usize, anywhere: c_int) c_int {
    var seg: ?*mem.Segment = null;
    const vaddr_val = @intFromPtr(addr.*);

    if (size == 0) return c.EINVAL;
    if (vm_map.total + size >= c.MAXMEM) return c.ENOMEM;

    if (anywhere != 0) {
        const alloc_size = kutil.round_page(size);
        seg = seg_alloc(&vm_map.head, alloc_size) orelse return c.ENOMEM;
    } else {
        const start = kutil.trunc_page(vaddr_val);
        const end = kutil.round_page(start + size);
        const total = end - start;
        seg = seg_reserve(&vm_map.head, @intCast(start), total) orelse return c.ENOMEM;
    }

    seg.?.flags = c.SEG_READ | c.SEG_WRITE;

    const pa = page.alloc(@intCast(seg.?.size));
    if (pa == 0) {
        seg_free(&vm_map.head, seg.?);
        return c.ENOMEM;
    }

    if (hal.mmu_map(vm_map.pgd, pa, seg.?.addr, seg.?.size, c.PG_WRITE) != 0) {
        page.free(pa, @intCast(seg.?.size));
        seg_free(&vm_map.head, seg.?);
        return c.ENOMEM;
    }

    seg.?.phys = pa;
    @memset(@as([*]u8, @ptrCast(kutil.ptokv(pa).?))[0..seg.?.size], 0);
    addr.* = @ptrFromInt(seg.?.addr);
    vm_map.total += seg.?.size;
    return 0;
}

fn do_free(vm_map: *mem.VmMap, addr: ?*anyopaque) c_int {
    const va = kutil.trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != @as(kern.Vaddr, @intCast(va)) or seg.flags & c.SEG_FREE != 0) {
        return c.EINVAL;
    }

    _ = hal.mmu_map(vm_map.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

    if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
        page.free(seg.phys, @intCast(seg.size));
    }

    vm_map.total -= seg.size;
    seg_free(&vm_map.head, seg);
    return 0;
}

fn do_attribute(vm_map: *mem.VmMap, addr: ?*anyopaque, attr: c_int) c_int {
    const va = kutil.trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != @as(kern.Vaddr, @intCast(va)) or seg.flags & c.SEG_FREE != 0) return c.EINVAL;
    if (seg.flags & c.SEG_MAPPED != 0) return c.EINVAL;

    var new_flags: c_int = 0;
    if (seg.flags & c.SEG_WRITE != 0) {
        if (attr & c.PROT_WRITE == 0) {
            new_flags = c.SEG_READ;
        }
    } else {
        if (attr & c.PROT_WRITE != 0) {
            new_flags = c.SEG_READ | c.SEG_WRITE;
        }
    }
    if (new_flags == 0) return 0;

    const map_type: c_int = if (new_flags & c.SEG_WRITE != 0) c.PG_WRITE else c.PG_READ;

    if (seg.flags & c.SEG_SHARED != 0) {
        const old_pa = seg.phys;
        const new_pa = page.alloc(@intCast(seg.size));
        if (new_pa == 0) return c.ENOMEM;

        @memcpy(@as([*]u8, @ptrCast(kutil.ptokv(new_pa).?))[0..seg.size], @as([*]const u8, @ptrCast(kutil.ptokv(old_pa).?))[0..seg.size]);

        if (hal.mmu_map(vm_map.pgd, new_pa, seg.addr, seg.size, map_type) != 0) {
            page.free(new_pa, @intCast(seg.size));
            return c.ENOMEM;
        }
        seg.phys = new_pa;

        seg.sh_prev.*.sh_next = seg.sh_next;
        seg.sh_next.*.sh_prev = seg.sh_prev;
        if (seg.sh_prev == seg.sh_next) {
            seg.sh_prev.*.flags &= ~c.SEG_SHARED;
        }
        seg.sh_next = seg;
        seg.sh_prev = seg;
    } else {
        if (hal.mmu_map(vm_map.pgd, seg.phys, seg.addr, seg.size, map_type) != 0) return c.ENOMEM;
    }

    seg.flags = new_flags;
    return 0;
}

fn do_map(target_map: *mem.VmMap, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) c_int {
    const curmap_raw = kutil.cur_task().map;
    if (curmap_raw == null) return c.EINVAL;
    const curmap: *mem.VmMap = @ptrCast(curmap_raw);

    if (size == 0) return c.EINVAL;
    if (target_map.total + size >= c.MAXMEM) return c.ENOMEM;

    var tmp: ?*anyopaque = null;
    _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&tmp)), @as(?*anyopaque, @ptrCast(alloc)), @sizeOf(?*anyopaque));

    const start = kutil.trunc_page(@intFromPtr(addr));
    const end = kutil.round_page(@intFromPtr(addr) + size);
    const total = end - start;
    const offset = @intFromPtr(addr) - start;

    const tgt = seg_lookup(&target_map.head, @intCast(start), total) orelse return c.EINVAL;
    if (tgt.flags & c.SEG_FREE != 0) return c.EINVAL;

    const cur_seg = seg_alloc(&curmap.head, total) orelse return c.ENOMEM;

    const map_type: c_int = if (tgt.flags & c.SEG_WRITE != 0) c.PG_WRITE else c.PG_READ;

    const pa = tgt.phys + (start - tgt.addr);
    if (hal.mmu_map(curmap.pgd, pa, cur_seg.addr, total, map_type) != 0) {
        seg_free(&curmap.head, cur_seg);
        return c.ENOMEM;
    }

    cur_seg.flags = tgt.flags | c.SEG_MAPPED;
    cur_seg.phys = pa;

    const result: ?*anyopaque = @ptrFromInt(cur_seg.addr + offset);
    _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&result)), @as(?*anyopaque, @ptrCast(alloc)), @sizeOf(?*anyopaque));

    curmap.total += total;
    return 0;
}

fn do_dup(org_map: *mem.VmMap) ?*mem.VmMap {
    const new_map_ptr = vm_create_internal() orelse return null;

    new_map_ptr.total = org_map.total;

    var tmp: *mem.Segment = &new_map_ptr.head;
    var src: *mem.Segment = &org_map.head;

    @memcpy(@as([*]u8, @ptrCast(tmp))[0..@sizeOf(mem.Segment)], @as([*]const u8, @ptrCast(src))[0..@sizeOf(mem.Segment)]);
    tmp.next = @as(*mem.Segment, @ptrCast(tmp));
    tmp.prev = @as(*mem.Segment, @ptrCast(tmp));

    if (@intFromPtr(src) == @intFromPtr(src.next)) return new_map_ptr;

    var dest: *mem.Segment = undefined;
    while (true) {
        if (src == &org_map.head) {
            dest = tmp;
        } else {
            const dest_ptr = kmem.alloc(@sizeOf(mem.Segment)) orelse return null;
            dest = @ptrCast(@alignCast(dest_ptr));
            dest.* = src.*;
            dest.prev = tmp;
            dest.next = tmp.next;
            tmp.next.*.prev = dest;
            tmp.next = dest;
            tmp = dest;
        }

        if (src.flags == c.SEG_FREE) {
            // Skip free segment
        } else {
            if (src.flags & c.SEG_WRITE == 0 and src.flags & c.SEG_MAPPED == 0) {
                dest.flags |= c.SEG_SHARED;
            }

            if (dest.flags & c.SEG_SHARED == 0) {
                dest.phys = page.alloc(@intCast(src.size));
                if (dest.phys == 0) return null;

                @memcpy(@as([*]u8, @ptrCast(kutil.ptokv(dest.phys).?))[0..src.size], @as([*]const u8, @ptrCast(kutil.ptokv(src.phys).?))[0..src.size]);
            }

            const map_type: c_int = if (dest.flags & c.SEG_WRITE != 0) c.PG_WRITE else c.PG_READ;
            if (hal.mmu_map(new_map_ptr.pgd, dest.phys, dest.addr, dest.size, map_type) != 0) return null;
        }

        src = src.next;
        if (src == &org_map.head) break;
    }

    dest = &new_map_ptr.head;
    src = &org_map.head;
    while (true) {
        if (dest.flags & c.SEG_SHARED != 0) {
            src.flags |= c.SEG_SHARED;
            dest.sh_prev = src;
            dest.sh_next = src.sh_next;
            src.sh_next.*.sh_prev = dest;
            src.sh_next = dest;
        }
        dest = dest.next;
        src = src.next;
        if (src == &org_map.head) break;
    }

    return new_map_ptr;
}

// ---------------------------------------------------------------------------
// Exported VM API
// ---------------------------------------------------------------------------

fn vm_create_internal() ?*mem.VmMap {
    const map_ptr = kmem.alloc(@sizeOf(mem.VmMap)) orelse return null;
    const vm_map: *mem.VmMap = @ptrCast(@alignCast(map_ptr));

    vm_map.refcnt = 1;
    vm_map.total = 0;

    vm_map.pgd = hal.mmu_newmap();
    if (vm_map.pgd == c.NO_PGD) {
        kmem.free(map_ptr);
        return null;
    }

    seg_init(&vm_map.head);
    return vm_map;
}

pub fn create() callconv(.c) c.vm_map_t {
    sched.lock();
    defer sched.unlock();
    const m = vm_create_internal();
    return @ptrCast(m);
}

pub fn allocate(tsk: kern.TaskRef, addr: *?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int {
    const task_opt: ?*kern.Task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;

    var uaddr: ?*anyopaque = null;
    _ = hal.copyin(@as(?*const anyopaque, @ptrCast(addr)), @as(?*anyopaque, @ptrCast(&uaddr)), @sizeOf(?*anyopaque));

    if (anywhere == 0 and !kutil.user_area(addr.*)) return c.EACCES;

    const err = do_allocate(@ptrCast(@alignCast(task_opt.?.map.?)), &uaddr, size, anywhere);
    if (err == 0) {
        if (hal.copyout(@as(?*const anyopaque, @ptrCast(&uaddr)), @as(?*anyopaque, @ptrCast(addr)), @sizeOf(?*anyopaque)) != 0) {
            return c.EFAULT;
        }
    }
    return err;
}

pub fn free(tsk: kern.TaskRef, addr: ?*anyopaque) callconv(.c) c_int {
    const task_opt: ?*kern.Task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!kutil.user_area(addr)) return c.EFAULT;

    return do_free(@ptrCast(@alignCast(task_opt.?.map.?)), addr);
}

pub fn attribute(tsk: kern.TaskRef, addr: ?*anyopaque, attr: c_int) callconv(.c) c_int {
    const task_opt: ?*kern.Task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (attr == 0 or attr & ~(c.PROT_READ | c.PROT_WRITE) != 0) return c.EINVAL;
    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!kutil.user_area(addr)) return c.EFAULT;

    return do_attribute(@ptrCast(@alignCast(task_opt.?.map.?)), addr, attr);
}

pub fn map(target: kern.TaskRef, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) callconv(.c) c_int {
    const target_opt: ?*kern.Task = @ptrCast(target);
    sched.lock();
    defer sched.unlock();

    if (task.valid(target) == 0) return c.ESRCH;
    if (target_opt == kutil.cur_task()) return c.EINVAL;
    if (task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!kutil.user_area(addr)) return c.EFAULT;

    return do_map(@ptrCast(@alignCast(target_opt.?.map.?)), addr, size, alloc);
}

pub fn terminate(vm_map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*mem.VmMap = @ptrCast(vm_map);
    if (map_opt.?.refcnt > 0) {
        map_opt.?.refcnt -= 1;
        if (map_opt.?.refcnt > 0) return;
    }

    sched.lock();
    defer sched.unlock();

    var seg: *mem.Segment = &map_opt.?.head;
    while (true) {
        if (seg.flags != c.SEG_FREE) {
            _ = hal.mmu_map(map_opt.?.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

            if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
                page.free(seg.phys, @intCast(seg.size));
            }
        }
        const tmp = seg;
        seg = seg.next;
        seg_delete(&map_opt.?.head, tmp);
        if (seg == &map_opt.?.head) break;
    }

    if (map_opt == @as(?*mem.VmMap, @ptrCast(@alignCast(kutil.cur_task().map)))) {
        hal.mmu_switch(kernel_map.pgd);
    }

    hal.mmu_terminate(map_opt.?.pgd);
    kmem.free(@ptrCast(@alignCast(map_opt)));
}

pub fn dup(org_map: c.vm_map_t) callconv(.c) c.vm_map_t {
    const org_map_opt: ?*mem.VmMap = @ptrCast(org_map);
    sched.lock();
    defer sched.unlock();
    return @ptrCast(do_dup(org_map_opt.?));
}

pub fn @"switch"(vm_map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*mem.VmMap = @ptrCast(vm_map);
    if (map_opt != &kernel_map) {
        hal.mmu_switch(map_opt.?.pgd);
    }
}

pub fn reference(vm_map: c.vm_map_t) callconv(.c) c_int {
    const map_opt: ?*mem.VmMap = @ptrCast(vm_map);
    map_opt.?.refcnt += 1;
    return 0;
}

pub fn load(vm_map: c.vm_map_t, mod: *hal.Module, stack: *?*anyopaque) callconv(.c) c_int {
    const map_opt: ?*mem.VmMap = @ptrCast(vm_map);
    const src_addr: usize = @intFromPtr(kutil.ptokv(mod.*.phys));
    var text: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(mod.*.text));
    var data: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(mod.*.data));

    @"switch"(vm_map);

    var err = do_allocate(@ptrCast(@alignCast(map_opt.?)), &text, mod.textsz, 0);
    if (err != 0) return err;
    @memcpy(@as([*]u8, @ptrCast(text.?))[0..mod.textsz], @as([*]const u8, @ptrFromInt(src_addr))[0..mod.textsz]);
    err = do_attribute(@ptrCast(@alignCast(map_opt.?)), text, c.PROT_READ);
    if (err != 0) return err;

    if (mod.datasz + mod.bsssz != 0) {
        err = do_allocate(@ptrCast(@alignCast(map_opt.?)), &data, mod.datasz + mod.bsssz, 0);
        if (err != 0) return err;
        if (mod.datasz > 0) {
            const data_src = src_addr + (mod.*.data - mod.*.text);
            @memcpy(@as([*]u8, @ptrCast(data.?))[0..mod.datasz], @as([*]const u8, @ptrFromInt(data_src))[0..mod.datasz]);
        }
    }

    stack.* = @as(?*anyopaque, @ptrFromInt(c.USRSTACK));
    err = do_allocate(@ptrCast(@alignCast(map_opt.?)), stack, c.DFLSTKSZ, 0);
    if (err != 0) return err;

    page.free(mod.*.phys, @intCast(mod.*.size));
    return 0;
}

pub fn translate(addr: kern.Vaddr, size: usize) callconv(.c) kern.Paddr {
    const map_ptr = kutil.cur_task().map;
    if (map_ptr == null) return 0;
    return hal.mmu_extract(map_ptr.*.pgd, addr, size);
}

pub fn info(vminfo: *hal.VmInfo) callconv(.c) c_int {
    const target = vminfo.cookie;
    const tsk = vminfo.task;
    const task_opt: ?*kern.Task = @ptrCast(tsk);

    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;

    const vm_map: *mem.VmMap = @ptrCast(@alignCast(task_opt.?.map.?));
    var seg: *mem.Segment = &vm_map.head;
    var i: c_ulong = 0;
    while (true) {
        if (i == target) {
            vminfo.cookie = i + 1;
            vminfo.virt = seg.addr;
            vminfo.size = seg.size;
            vminfo.flags = seg.flags;
            vminfo.phys = seg.phys;
            return 0;
        }
        i += 1;
        seg = seg.next;
        if (seg == &vm_map.head) break;
    }
    return c.ESRCH;
}

pub fn init() callconv(.c) void {
    const pgd = hal.mmu_newmap();
    if (pgd == c.NO_PGD) {
        while (true) {}
    }
    kernel_map.pgd = pgd;
    hal.mmu_switch(pgd);

    seg_init(&kernel_map.head);
    c.kernel_task.map = @ptrCast(&kernel_map);
}

comptime {
    if (@import("root") == @This()) {
        @export(&create, .{ .name = "vm_create", .linkage = .strong });
        @export(&allocate, .{ .name = "vm_allocate", .linkage = .strong });
        @export(&free, .{ .name = "vm_free", .linkage = .strong });
        @export(&attribute, .{ .name = "vm_attribute", .linkage = .strong });
        @export(&map, .{ .name = "vm_map", .linkage = .strong });
        @export(&terminate, .{ .name = "vm_terminate", .linkage = .strong });
        @export(&dup, .{ .name = "vm_dup", .linkage = .strong });
        @export(&@"switch", .{ .name = "vm_switch", .linkage = .strong });
        @export(&reference, .{ .name = "vm_reference", .linkage = .strong });
        @export(&load, .{ .name = "vm_load", .linkage = .strong });
        @export(&translate, .{ .name = "vm_translate", .linkage = .strong });
        @export(&info, .{ .name = "vm_info", .linkage = .strong });
        @export(&init, .{ .name = "vm_init", .linkage = .strong });
    }
}
