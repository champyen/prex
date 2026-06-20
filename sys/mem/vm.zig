const std = @import("std");
const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

// ---------------------------------------------------------------------------
// Page size helpers
// ---------------------------------------------------------------------------

inline fn round_page(x: usize) usize {
    const page_mask = @as(usize, @intCast(c.PAGE_SIZE - 1));
    return (x + page_mask) & ~page_mask;
}

inline fn trunc_page(x: usize) usize {
    const page_mask = @as(usize, @intCast(c.PAGE_SIZE - 1));
    return x & ~page_mask;
}

inline fn user_area(addr: anytype) bool {
    if (@hasDecl(c, "USERLIMIT")) {
        return @intFromPtr(addr) < c.USERLIMIT;
    }
    return true;
}

inline fn ptokv(pa: c.paddr_t) ?*anyopaque {
    return @ptrFromInt(@as(usize, pa) + c.KERNOFFSET);
}

inline fn kvtop(va: anytype) c.paddr_t {
    return @intFromPtr(va) - c.KERNOFFSET;
}

// ---------------------------------------------------------------------------
// Thread / task accessors
// ---------------------------------------------------------------------------

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

inline fn get_curthread() *c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.*.active_thread.?);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread.?);
    }
}

inline fn get_curtask() *c.struct_task {
    return @ptrCast(get_curthread().*.task.?);
}

// ---------------------------------------------------------------------------
// Scheduler lock stubs
// ---------------------------------------------------------------------------

extern fn sched_lock() callconv(.c) void;
extern fn sched_unlock() callconv(.c) void;
extern fn task_valid(t: c.task_t) callconv(.c) c_int;
extern fn task_capable(cap: c_int) callconv(.c) c_int;
extern fn copyin(src: ?*const anyopaque, dst: ?*anyopaque, n: usize) callconv(.c) c_int;
extern fn copyout(src: ?*const anyopaque, dst: ?*anyopaque, n: usize) callconv(.c) c_int;

// ---------------------------------------------------------------------------
// Page / MMU stubs
// ---------------------------------------------------------------------------

extern fn page_alloc(size: c.psize_t) callconv(.c) c.paddr_t;
extern fn page_free(pa: c.paddr_t, size: c.psize_t) callconv(.c) void;
extern fn mmu_newmap() callconv(.c) c.pgd_t;
extern fn mmu_switch(pgd: c.pgd_t) callconv(.c) void;
extern fn mmu_map(pgd: c.pgd_t, pa: c.paddr_t, va: c.vaddr_t, size: usize, flags: c_int) callconv(.c) c_int;
extern fn mmu_terminate(pgd: c.pgd_t) callconv(.c) void;
extern fn mmu_extract(pgd: c.pgd_t, addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t;

// ---------------------------------------------------------------------------
// Memory allocator stubs
// ---------------------------------------------------------------------------

extern fn kmem_alloc(n: usize) callconv(.c) ?*anyopaque;
extern fn kmem_free(p: ?*anyopaque) callconv(.c) void;

// ---------------------------------------------------------------------------
// C memcpy/memset stubs (for page copy/zero-fill)
// ---------------------------------------------------------------------------

extern fn @"memcpy"(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) ?*anyopaque;
extern fn @"memset"(dst: ?*anyopaque, val: c_int, n: usize) callconv(.c) ?*anyopaque;

// ---------------------------------------------------------------------------
// Kernel map (module-level)
// ---------------------------------------------------------------------------

var kernel_map: c.struct_vm_map = undefined;

// ---------------------------------------------------------------------------
// Segment list helpers (operate on circular doubly-linked list)
// ---------------------------------------------------------------------------

fn seg_init(seg: *c.struct_seg) void {
    seg.next = @as(*c.struct_seg, @ptrCast(seg));
    seg.prev = @as(*c.struct_seg, @ptrCast(seg));
    seg.sh_next = @as(*c.struct_seg, @ptrCast(seg));
    seg.sh_prev = @as(*c.struct_seg, @ptrCast(seg));
    seg.addr = @intCast(c.PAGE_SIZE);
    seg.phys = 0;
    seg.size = @intCast(c.USERLIMIT - c.PAGE_SIZE);
    seg.flags = c.SEG_FREE;
}

fn seg_create(prev: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    const seg_ptr = kmem_alloc(@sizeOf(c.struct_seg)) orelse return null;
    const seg: *c.struct_seg = @ptrCast(@alignCast(seg_ptr));

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

fn seg_delete(head: *c.struct_seg, seg: *c.struct_seg) void {
    if (seg.flags & c.SEG_SHARED != 0) {
        seg.sh_prev.*.sh_next = seg.sh_next;
        seg.sh_next.*.sh_prev = seg.sh_prev;
        if (seg.sh_prev == seg.sh_next) {
            seg.sh_prev.*.flags &= ~c.SEG_SHARED;
        }
    }
    if (head != seg) {
        kmem_free(@ptrCast(@alignCast(seg)));
    }
}

fn seg_lookup(head: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
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

fn seg_alloc(head: *c.struct_seg, size: usize) ?*c.struct_seg {
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

fn seg_free(head: *c.struct_seg, seg: *c.struct_seg) void {
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
        kmem_free(@ptrCast(@alignCast(next)));
    }

    const prev = seg.prev;
    if (seg != head and prev.*.flags & c.SEG_FREE != 0) {
        prev.*.next = seg.next;
        seg.next.*.prev = prev;
        prev.*.size += seg.size;
        kmem_free(@ptrCast(@alignCast(seg)));
    }
}

fn seg_reserve(head: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    var seg = seg_lookup(head, addr, size) orelse return null;
    if (seg.flags & c.SEG_FREE == 0) return null;

    var prev: ?*c.struct_seg = null;
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

fn do_allocate(map: *c.struct_vm_map, addr: *?*anyopaque, size: usize, anywhere: c_int) c_int {
    var seg: ?*c.struct_seg = null;
    const vaddr_val = @intFromPtr(addr.*);

    if (size == 0) return c.EINVAL;
    if (map.total + size >= c.MAXMEM) return c.ENOMEM;

    if (anywhere != 0) {
        const alloc_size = round_page(size);
        seg = seg_alloc(&map.head, alloc_size) orelse return c.ENOMEM;
    } else {
        const start = trunc_page(vaddr_val);
        const end = round_page(start + size);
        const total = end - start;
        seg = seg_reserve(&map.head, @intCast(start), total) orelse return c.ENOMEM;
    }

    seg.?.flags = c.SEG_READ | c.SEG_WRITE;

    const pa = page_alloc(@intCast(seg.?.size));
    if (pa == 0) {
        seg_free(&map.head, seg.?);
        return c.ENOMEM;
    }

    if (mmu_map(map.pgd, pa, seg.?.addr, seg.?.size, c.PG_WRITE) != 0) {
        page_free(pa, @intCast(seg.?.size));
        seg_free(&map.head, seg.?);
        return c.ENOMEM;
    }

    seg.?.phys = pa;
    @memset(@as([*]u8, @ptrCast(ptokv(pa).?))[0..seg.?.size], 0);
    addr.* = @ptrFromInt(seg.?.addr);
    map.total += seg.?.size;
    return 0;
}

fn do_free(map: *c.struct_vm_map, addr: ?*anyopaque) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != @as(c.vaddr_t, @intCast(va)) or seg.flags & c.SEG_FREE != 0) {
        return c.EINVAL;
    }

    _ = mmu_map(map.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

    if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
        page_free(seg.phys, @intCast(seg.size));
    }

    map.total -= seg.size;
    seg_free(&map.head, seg);
    return 0;
}

fn do_attribute(map: *c.struct_vm_map, addr: ?*anyopaque, attr: c_int) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != @as(c.vaddr_t, @intCast(va)) or seg.flags & c.SEG_FREE != 0) return c.EINVAL;
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
        const new_pa = page_alloc(@intCast(seg.size));
        if (new_pa == 0) return c.ENOMEM;

        @memcpy(@as([*]u8, @ptrCast(ptokv(new_pa).?))[0..seg.size], @as([*]const u8, @ptrCast(ptokv(old_pa).?))[0..seg.size]);

        if (mmu_map(map.pgd, new_pa, seg.addr, seg.size, map_type) != 0) {
            page_free(new_pa, @intCast(seg.size));
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
        if (mmu_map(map.pgd, seg.phys, seg.addr, seg.size, map_type) != 0) return c.ENOMEM;
    }

    seg.flags = new_flags;
    return 0;
}

fn do_map(target_map: *c.struct_vm_map, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) c_int {
    const curmap_raw = get_curtask().map;
    if (curmap_raw == null) return c.EINVAL;
    const curmap: *c.struct_vm_map = @ptrCast(curmap_raw);

    if (size == 0) return c.EINVAL;
    if (target_map.total + size >= c.MAXMEM) return c.ENOMEM;

    var tmp: ?*anyopaque = null;
    _ = copyout(@as(?*const anyopaque, @ptrCast(&tmp)), @as(?*anyopaque, @ptrCast(alloc)), @sizeOf(?*anyopaque));

    const start = trunc_page(@intFromPtr(addr));
    const end = round_page(@intFromPtr(addr) + size);
    const total = end - start;
    const offset = @intFromPtr(addr) - start;

    const tgt = seg_lookup(&target_map.head, @intCast(start), total) orelse return c.EINVAL;
    if (tgt.flags & c.SEG_FREE != 0) return c.EINVAL;

    const cur_seg = seg_alloc(&curmap.head, total) orelse return c.ENOMEM;

    const map_type: c_int = if (tgt.flags & c.SEG_WRITE != 0) c.PG_WRITE else c.PG_READ;

    const pa = tgt.phys + (start - tgt.addr);
    if (mmu_map(curmap.pgd, pa, cur_seg.addr, total, map_type) != 0) {
        seg_free(&curmap.head, cur_seg);
        return c.ENOMEM;
    }

    cur_seg.flags = tgt.flags | c.SEG_MAPPED;
    cur_seg.phys = pa;

    const result: ?*anyopaque = @ptrFromInt(cur_seg.addr + offset);
    _ = copyout(@as(?*const anyopaque, @ptrCast(&result)), @as(?*anyopaque, @ptrCast(alloc)), @sizeOf(?*anyopaque));

    curmap.total += total;
    return 0;
}

fn do_dup(org_map: *c.struct_vm_map) ?*c.struct_vm_map {
    const new_map_ptr = vm_create_internal() orelse return null;

    new_map_ptr.total = org_map.total;

    var tmp: *c.struct_seg = &new_map_ptr.head;
    var src: *c.struct_seg = &org_map.head;

    @memcpy(@as([*]u8, @ptrCast(tmp))[0..@sizeOf(c.struct_seg)], @as([*]const u8, @ptrCast(src))[0..@sizeOf(c.struct_seg)]);
    tmp.next = @as(*c.struct_seg, @ptrCast(tmp));
    tmp.prev = @as(*c.struct_seg, @ptrCast(tmp));

    if (@intFromPtr(src) == @intFromPtr(src.next)) return new_map_ptr;

    var dest: *c.struct_seg = undefined;
    while (true) {
        std.debug.assert(src.next != null);
        if (src == &org_map.head) {
            dest = tmp;
        } else {
            const dest_ptr = kmem_alloc(@sizeOf(c.struct_seg)) orelse return null;
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
                dest.phys = page_alloc(@intCast(src.size));
                if (dest.phys == 0) return null;

                @memcpy(@as([*]u8, @ptrCast(ptokv(dest.phys).?))[0..src.size], @as([*]const u8, @ptrCast(ptokv(src.phys).?))[0..src.size]);
            }

            const map_type: c_int = if (dest.flags & c.SEG_WRITE != 0) c.PG_WRITE else c.PG_READ;
            if (mmu_map(new_map_ptr.pgd, dest.phys, dest.addr, dest.size, map_type) != 0) return null;
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

fn vm_create_internal() ?*c.struct_vm_map {
    const map_ptr = kmem_alloc(@sizeOf(c.struct_vm_map)) orelse return null;
    const map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));

    map.refcnt = 1;
    map.total = 0;

    map.pgd = mmu_newmap();
    if (map.pgd == c.NO_PGD) {
        kmem_free(map_ptr);
        return null;
    }

    seg_init(&map.head);
    return map;
}

pub export fn vm_create() callconv(.c) c.vm_map_t {
    sched_lock();
    defer sched_unlock();
    const m = vm_create_internal();
    return @ptrCast(m);
}

pub export fn vm_allocate(task: c.task_t, addr: *?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(task);
    sched_lock();
    defer sched_unlock();

    if (task_valid(task) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) return c.EPERM;

    var uaddr: ?*anyopaque = null;
    _ = copyin(@as(?*const anyopaque, @ptrCast(addr)), @as(?*anyopaque, @ptrCast(&uaddr)), @sizeOf(?*anyopaque));

    if (anywhere == 0 and !user_area(addr.*)) return c.EACCES;

    const err = do_allocate(task_opt.?.map.?, &uaddr, size, anywhere);
    if (err == 0) {
        if (copyout(@as(?*const anyopaque, @ptrCast(&uaddr)), @as(?*anyopaque, @ptrCast(addr)), @sizeOf(?*anyopaque)) != 0) {
            return c.EFAULT;
        }
    }
    return err;
}

pub export fn vm_free(task: c.task_t, addr: ?*anyopaque) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(task);
    sched_lock();
    defer sched_unlock();

    if (task_valid(task) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_free(task_opt.?.map.?, addr);
}

pub export fn vm_attribute(task: c.task_t, addr: ?*anyopaque, attr: c_int) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(task);
    sched_lock();
    defer sched_unlock();

    if (attr == 0 or attr & ~(c.PROT_READ | c.PROT_WRITE) != 0) return c.EINVAL;
    if (task_valid(task) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_attribute(task_opt.?.map.?, addr, attr);
}

pub export fn vm_map(target: c.task_t, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) callconv(.c) c_int {
    const target_opt: ?*c.struct_task = @ptrCast(target);
    sched_lock();
    defer sched_unlock();

    if (task_valid(target) == 0) return c.ESRCH;
    if (target_opt == get_curtask()) return c.EINVAL;
    if (task_capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_map(target_opt.?.map.?, addr, size, alloc);
}

pub export fn vm_terminate(map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*c.struct_vm_map = @ptrCast(map);
    if (map_opt.?.refcnt > 0) {
        map_opt.?.refcnt -= 1;
        if (map_opt.?.refcnt > 0) return;
    }

    sched_lock();
    defer sched_unlock();

    var seg: *c.struct_seg = &map_opt.?.head;
    while (true) {
        if (seg.flags != c.SEG_FREE) {
            _ = mmu_map(map_opt.?.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

            if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
                page_free(seg.phys, @intCast(seg.size));
            }
        }
        const tmp = seg;
        seg = seg.next;
        seg_delete(&map_opt.?.head, tmp);
        if (seg == &map_opt.?.head) break;
    }

    if (map_opt == get_curtask().map) {
        mmu_switch(kernel_map.pgd);
    }

    mmu_terminate(map_opt.?.pgd);
    kmem_free(@ptrCast(@alignCast(map_opt)));
}

pub export fn vm_dup(org_map: c.vm_map_t) callconv(.c) c.vm_map_t {
    const org_map_opt: ?*c.struct_vm_map = @ptrCast(org_map);
    sched_lock();
    defer sched_unlock();
    return @ptrCast(do_dup(org_map_opt.?));
}

pub export fn vm_switch(map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*c.struct_vm_map = @ptrCast(map);
    if (map_opt != &kernel_map) {
        mmu_switch(map_opt.?.pgd);
    }
}

pub export fn vm_reference(map: c.vm_map_t) callconv(.c) c_int {
    const map_opt: ?*c.struct_vm_map = @ptrCast(map);
    map_opt.?.refcnt += 1;
    return 0;
}

pub export fn vm_load(map: c.vm_map_t, mod: *c.struct_module, stack: *?*anyopaque) callconv(.c) c_int {
    const map_opt: ?*c.struct_vm_map = @ptrCast(map);
    const src_addr: usize = @intFromPtr(ptokv(mod.*.phys));
    var text: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(mod.*.text));
    var data: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(mod.*.data));

    vm_switch(map);

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

    page_free(mod.*.phys, @intCast(mod.*.size));
    return 0;
}

pub export fn vm_translate(addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t {
    const map_ptr = get_curtask().map;
    if (map_ptr == null) return 0;
    return mmu_extract(map_ptr.*.pgd, addr, size);
}

pub export fn vm_info(info: *c.struct_vminfo) callconv(.c) c_int {
    const target = info.cookie;
    const task = info.task;
    const task_opt: ?*c.struct_task = @ptrCast(task);

    sched_lock();
    defer sched_unlock();

    if (task_valid(task) == 0) return c.ESRCH;

    const map: *c.struct_vm_map = @ptrCast(@alignCast(task_opt.?.map.?));
    var seg: *c.struct_seg = &map.head;
    var i: c_ulong = 0;
    while (true) {
        if (i == target) {
            info.cookie = i + 1;
            info.virt = seg.addr;
            info.size = seg.size;
            info.flags = seg.flags;
            info.phys = seg.phys;
            return 0;
        }
        i += 1;
        seg = seg.next;
        if (seg == &map.head) break;
    }
    return c.ESRCH;
}

pub export fn vm_init() callconv(.c) void {
    const pgd = mmu_newmap();
    if (pgd == c.NO_PGD) {
        while (true) {}
    }
    kernel_map.pgd = pgd;
    mmu_switch(pgd);

    seg_init(&kernel_map.head);
    c.kernel_task.map = &kernel_map;
}
