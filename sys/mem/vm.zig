const std = @import("std");
const c = @import("c").c;
const ffi = @import("ffi");
const sched = ffi.sched;
const task = ffi.task;
const page = ffi.page;
const kmem = ffi.kmem;
const smp = ffi.smp;
const thread = ffi.thread;

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

inline fn get_curthread() *c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(smp.get_cpu_control().*.active_thread);
    } else {
        return @ptrCast(thread.curthread.?);
    }
}

inline fn get_curtask() *c.struct_task {
    return @ptrCast(get_curthread().*.task.?);
}

// ---------------------------------------------------------------------------
// FFI Structures
// ---------------------------------------------------------------------------



extern fn copyin(src: ?*const anyopaque, dst: ?*anyopaque, n: usize) callconv(.c) c_int;
extern fn copyout(src: ?*const anyopaque, dst: ?*anyopaque, n: usize) callconv(.c) c_int;

// ---------------------------------------------------------------------------
// MMU stubs
// ---------------------------------------------------------------------------

extern fn mmu_newmap() callconv(.c) c.pgd_t;
extern fn mmu_switch(pgd: c.pgd_t) callconv(.c) void;
extern fn mmu_map(pgd: c.pgd_t, pa: c.paddr_t, va: c.vaddr_t, size: usize, flags: c_int) callconv(.c) c_int;
extern fn mmu_terminate(pgd: c.pgd_t) callconv(.c) void;
extern fn mmu_extract(pgd: c.pgd_t, addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t;

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
    const seg_ptr = kmem.alloc(@sizeOf(c.struct_seg)) orelse return null;
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
        kmem.free(@ptrCast(@alignCast(seg)));
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

fn do_allocate(vm_map: *c.struct_vm_map, addr: *?*anyopaque, size: usize, anywhere: c_int) c_int {
    var seg: ?*c.struct_seg = null;
    const vaddr_val = @intFromPtr(addr.*);

    if (size == 0) return c.EINVAL;
    if (vm_map.total + size >= c.MAXMEM) return c.ENOMEM;

    if (anywhere != 0) {
        const alloc_size = round_page(size);
        seg = seg_alloc(&vm_map.head, alloc_size) orelse return c.ENOMEM;
    } else {
        const start = trunc_page(vaddr_val);
        const end = round_page(start + size);
        const total = end - start;
        seg = seg_reserve(&vm_map.head, @intCast(start), total) orelse return c.ENOMEM;
    }

    seg.?.flags = c.SEG_READ | c.SEG_WRITE;

    const pa = page.alloc(@intCast(seg.?.size));
    if (pa == 0) {
        seg_free(&vm_map.head, seg.?);
        return c.ENOMEM;
    }

    if (mmu_map(vm_map.pgd, pa, seg.?.addr, seg.?.size, c.PG_WRITE) != 0) {
        page.free(pa, @intCast(seg.?.size));
        seg_free(&vm_map.head, seg.?);
        return c.ENOMEM;
    }

    seg.?.phys = pa;
    @memset(@as([*]u8, @ptrCast(ptokv(pa).?))[0..seg.?.size], 0);
    addr.* = @ptrFromInt(seg.?.addr);
    vm_map.total += seg.?.size;
    return 0;
}

fn do_free(vm_map: *c.struct_vm_map, addr: ?*anyopaque) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != @as(c.vaddr_t, @intCast(va)) or seg.flags & c.SEG_FREE != 0) {
        return c.EINVAL;
    }

    _ = mmu_map(vm_map.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

    if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
        page.free(seg.phys, @intCast(seg.size));
    }

    vm_map.total -= seg.size;
    seg_free(&vm_map.head, seg);
    return 0;
}

fn do_attribute(vm_map: *c.struct_vm_map, addr: ?*anyopaque, attr: c_int) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
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
        const new_pa = page.alloc(@intCast(seg.size));
        if (new_pa == 0) return c.ENOMEM;

        @memcpy(@as([*]u8, @ptrCast(ptokv(new_pa).?))[0..seg.size], @as([*]const u8, @ptrCast(ptokv(old_pa).?))[0..seg.size]);

        if (mmu_map(vm_map.pgd, new_pa, seg.addr, seg.size, map_type) != 0) {
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
        if (mmu_map(vm_map.pgd, seg.phys, seg.addr, seg.size, map_type) != 0) return c.ENOMEM;
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
            const dest_ptr = kmem.alloc(@sizeOf(c.struct_seg)) orelse return null;
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
    const map_ptr = kmem.alloc(@sizeOf(c.struct_vm_map)) orelse return null;
    const vm_map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));

    vm_map.refcnt = 1;
    vm_map.total = 0;

    vm_map.pgd = mmu_newmap();
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

pub fn allocate(tsk: c.task_t, addr: *?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;

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

pub fn free(tsk: c.task_t, addr: ?*anyopaque) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_free(task_opt.?.map.?, addr);
}

pub fn attribute(tsk: c.task_t, addr: ?*anyopaque, attr: c_int) callconv(.c) c_int {
    const task_opt: ?*c.struct_task = @ptrCast(tsk);
    sched.lock();
    defer sched.unlock();

    if (attr == 0 or attr & ~(c.PROT_READ | c.PROT_WRITE) != 0) return c.EINVAL;
    if (task.valid(tsk) == 0) return c.ESRCH;
    if (task_opt != get_curtask() and task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_attribute(task_opt.?.map.?, addr, attr);
}

pub fn map(target: c.task_t, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) callconv(.c) c_int {
    const target_opt: ?*c.struct_task = @ptrCast(target);
    sched.lock();
    defer sched.unlock();

    if (task.valid(target) == 0) return c.ESRCH;
    if (target_opt == get_curtask()) return c.EINVAL;
    if (task.capable(c.CAP_EXTMEM) == 0) return c.EPERM;
    if (!user_area(addr)) return c.EFAULT;

    return do_map(target_opt.?.map.?, addr, size, alloc);
}

pub fn terminate(vm_map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*c.struct_vm_map = @ptrCast(vm_map);
    if (map_opt.?.refcnt > 0) {
        map_opt.?.refcnt -= 1;
        if (map_opt.?.refcnt > 0) return;
    }

    sched.lock();
    defer sched.unlock();

    var seg: *c.struct_seg = &map_opt.?.head;
    while (true) {
        if (seg.flags != c.SEG_FREE) {
            _ = mmu_map(map_opt.?.pgd, seg.phys, seg.addr, seg.size, c.PG_UNMAP);

            if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
                page.free(seg.phys, @intCast(seg.size));
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
    kmem.free(@ptrCast(@alignCast(map_opt)));
}

pub fn dup(org_map: c.vm_map_t) callconv(.c) c.vm_map_t {
    const org_map_opt: ?*c.struct_vm_map = @ptrCast(org_map);
    sched.lock();
    defer sched.unlock();
    return @ptrCast(do_dup(org_map_opt.?));
}

pub fn @"switch"(vm_map: c.vm_map_t) callconv(.c) void {
    const map_opt: ?*c.struct_vm_map = @ptrCast(vm_map);
    if (map_opt != &kernel_map) {
        mmu_switch(map_opt.?.pgd);
    }
}

pub fn reference(vm_map: c.vm_map_t) callconv(.c) c_int {
    const map_opt: ?*c.struct_vm_map = @ptrCast(vm_map);
    map_opt.?.refcnt += 1;
    return 0;
}

pub fn load(vm_map: c.vm_map_t, mod: *c.struct_module, stack: *?*anyopaque) callconv(.c) c_int {
    const map_opt: ?*c.struct_vm_map = @ptrCast(vm_map);
    const src_addr: usize = @intFromPtr(ptokv(mod.*.phys));
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

pub fn translate(addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t {
    const map_ptr = get_curtask().map;
    if (map_ptr == null) return 0;
    return mmu_extract(map_ptr.*.pgd, addr, size);
}

pub fn info(vminfo: *c.struct_vminfo) callconv(.c) c_int {
    const target = vminfo.cookie;
    const tsk = vminfo.task;
    const task_opt: ?*c.struct_task = @ptrCast(tsk);

    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) return c.ESRCH;

    const vm_map: *c.struct_vm_map = @ptrCast(@alignCast(task_opt.?.map.?));
    var seg: *c.struct_seg = &vm_map.head;
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
    const pgd = mmu_newmap();
    if (pgd == c.NO_PGD) {
        while (true) {}
    }
    kernel_map.pgd = pgd;
    mmu_switch(pgd);

    seg_init(&kernel_map.head);
    c.kernel_task.map = &kernel_map;
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
