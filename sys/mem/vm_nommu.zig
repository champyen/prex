const std = @import("std");
const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

const assert = std.debug.assert;

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
extern fn page_alloc(size: usize) callconv(.c) c.paddr_t;
extern fn page_free(pa: c.paddr_t, size: usize) callconv(.c) void;
extern fn page_reserve(pa: c.paddr_t, size: usize) callconv(.c) c_int;
extern fn kmem_alloc(n: usize) callconv(.c) ?*anyopaque;
extern fn kmem_free(p: ?*anyopaque) callconv(.c) void;

// ---------------------------------------------------------------------------
// Kernel map (module-level)
// ---------------------------------------------------------------------------

var kernel_map: c.struct_vm_map = undefined;

// ---------------------------------------------------------------------------
// Segment list helpers (operate on circular doubly-linked list)
// ---------------------------------------------------------------------------

fn seg_init(seg: *c.struct_seg) void {
    seg.next = seg;
    seg.prev = seg;
    seg.sh_next = seg;
    seg.sh_prev = seg;
    seg.addr = 0;
    seg.phys = 0;
    seg.size = 0;
    seg.flags = c.SEG_FREE;
}

fn seg_create(prev: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    const seg_ptr = kmem_alloc(@sizeOf(c.struct_seg)) orelse return null;
    const seg: *c.struct_seg = @ptrCast(@alignCast(seg_ptr));

    seg.addr = addr;
    seg.size = size;
    seg.phys = @intCast(addr);
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
        kmem_free(seg);
    }
}

fn seg_lookup(head: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    var seg: *c.struct_seg = head;
    while (true) {
        if (seg.addr <= addr and seg.addr + seg.size >= addr + size) {
            return seg;
        }
        seg = seg.next.?;
        if (seg == head) break;
    }
    return null;
}

fn seg_alloc(head: *c.struct_seg, size: usize) ?*c.struct_seg {
    const pa = page_alloc(size);
    if (pa == 0) return null;

    const seg = seg_create(head, @intCast(pa), size) orelse {
        page_free(pa, size);
        return null;
    };
    return seg;
}

fn seg_free(head: *c.struct_seg, seg: *c.struct_seg) void {
    _ = head;
    assert(seg.flags != c.SEG_FREE);

    if (seg.flags & c.SEG_SHARED != 0) {
        seg.sh_prev.*.sh_next = seg.sh_next;
        seg.sh_next.*.sh_prev = seg.sh_prev;
        if (seg.sh_prev == seg.sh_next) {
            seg.sh_prev.*.flags &= ~c.SEG_SHARED;
        }
    }
    seg.prev.*.next = seg.next;
    seg.next.*.prev = seg.prev;

    kmem_free(seg);
}

fn seg_reserve(head: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    const pa: c.paddr_t = @intCast(addr);

    if (page_reserve(pa, size) != 0) return null;

    const seg = seg_create(head, addr, size) orelse {
        page_free(pa, size);
        return null;
    };
    return seg;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn do_allocate(map: *c.struct_vm_map, addr: *?*anyopaque, size: usize, anywhere: c_int) c_int {
    if (size == 0) return c.EINVAL;
    if (map.total + size >= c.MAXMEM) return c.ENOMEM;

    var seg: *c.struct_seg = undefined;
    var start: c.vaddr_t = undefined;

    if (anywhere != 0) {
        const alloc_size = round_page(size);
        seg = seg_alloc(&map.head, alloc_size) orelse return c.ENOMEM;
        start = seg.addr;
    } else {
        start = trunc_page(@intFromPtr(addr.*));
        const end = round_page(start + size);
        const alloc_size = end - start;

        seg = seg_reserve(&map.head, start, alloc_size) orelse return c.ENOMEM;
        start = seg.addr;
    }
    seg.flags = c.SEG_READ | c.SEG_WRITE;

    // Zero fill
    const ptr: [*]u8 = @ptrFromInt(start);
    @memset(ptr[0..seg.size], 0);

    addr.* = @ptrFromInt(seg.addr);
    map.total += seg.size;
    return 0;
}

fn do_free(map: *c.struct_vm_map, addr: ?*anyopaque) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != va or seg.flags & c.SEG_FREE != 0) return c.EINVAL;

    if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
        page_free(seg.phys, seg.size);
    }

    map.total -= seg.size;
    seg_free(&map.head, seg);

    return 0;
}

fn do_attribute(map: *c.struct_vm_map, addr: ?*anyopaque, attr: c_int) c_int {
    const va = trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != va or seg.flags & c.SEG_FREE != 0) return c.EINVAL;
    if (seg.flags & c.SEG_MAPPED != 0 or seg.flags & c.SEG_SHARED != 0) return c.EINVAL;

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
    if (new_flags == 0) return 0; // same attribute
    seg.flags = new_flags;
    return 0;
}

fn do_map(map: *c.struct_vm_map, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) c_int {
    if (size == 0) return c.EINVAL;
    if (map.total + size >= c.MAXMEM) return c.ENOMEM;

    // check fault
    var tmp: ?*anyopaque = null;
    if (copyout(@ptrCast(&tmp), @ptrCast(alloc), @sizeOf(?*anyopaque)) != 0) return c.EFAULT;

    const start = trunc_page(@intFromPtr(addr));
    const end = round_page(@intFromPtr(addr) + size);
    const alloc_size = end - start;

    // Find the segment that includes target address
    const tgt = seg_lookup(&map.head, @intCast(start), alloc_size) orelse return c.EINVAL;
    if (tgt.flags & c.SEG_FREE != 0) return c.EINVAL;

    // Create new segment to map
    const map_ptr = get_curtask().map orelse return c.ENOMEM;
    const curmap: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));
    const seg = seg_create(&curmap.head, @intCast(start), alloc_size) orelse return c.ENOMEM;
    seg.flags = tgt.flags | c.SEG_MAPPED;

    _ = copyout(@ptrCast(&addr), @ptrCast(alloc), @sizeOf(?*anyopaque));

    curmap.total += alloc_size;
    return 0;
}

// ---------------------------------------------------------------------------
// Exported FFI functions
// ---------------------------------------------------------------------------

export fn vm_allocate(task: ?*c.struct_task, addr: [*c]?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int {
    var error_val: c_int = undefined;
    var uaddr: ?*anyopaque = undefined;

    sched_lock();

    if (task_valid(task) == 0) {
        sched_unlock();
        return c.ESRCH;
    }
    if (task != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) {
        sched_unlock();
        return c.EPERM;
    }
    if (copyin(@ptrCast(addr), @ptrCast(&uaddr), @sizeOf(?*anyopaque)) != 0) {
        sched_unlock();
        return c.EFAULT;
    }
    if (anywhere == 0 and !user_area(uaddr)) {
        sched_unlock();
        return c.EACCES;
    }

    error_val = do_allocate(task.?.map.?, &uaddr, size, anywhere);
    if (error_val == 0) {
        if (copyout(@ptrCast(&uaddr), @ptrCast(addr), @sizeOf(?*anyopaque)) != 0) {
            error_val = c.EFAULT;
        }
    }
    sched_unlock();
    return error_val;
}

export fn vm_free(task: ?*c.struct_task, addr: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched_lock();
    if (task_valid(task) == 0) {
        sched_unlock();
        return c.ESRCH;
    }
    if (task != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) {
        sched_unlock();
        return c.EPERM;
    }
    if (!user_area(addr)) {
        sched_unlock();
        return c.EFAULT;
    }

    error_val = do_free(task.?.map.?, addr);

    sched_unlock();
    return error_val;
}

export fn vm_attribute(task: ?*c.struct_task, addr: ?*anyopaque, attr: c_int) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched_lock();
    if (attr == 0 or attr & ~(c.PROT_READ | c.PROT_WRITE) != 0) {
        sched_unlock();
        return c.EINVAL;
    }
    if (task_valid(task) == 0) {
        sched_unlock();
        return c.ESRCH;
    }
    if (task != get_curtask() and task_capable(c.CAP_EXTMEM) == 0) {
        sched_unlock();
        return c.EPERM;
    }
    if (!user_area(addr)) {
        sched_unlock();
        return c.EFAULT;
    }

    error_val = do_attribute(task.?.map.?, addr, attr);

    sched_unlock();
    return error_val;
}

export fn vm_map(target: ?*c.struct_task, addr: ?*anyopaque, size: usize, alloc: [*c]?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched_lock();
    if (task_valid(target) == 0) {
        sched_unlock();
        return c.ESRCH;
    }
    if (target == get_curtask()) {
        sched_unlock();
        return c.EINVAL;
    }
    if (task_capable(c.CAP_EXTMEM) == 0) {
        sched_unlock();
        return c.EPERM;
    }
    if (!user_area(addr)) {
        sched_unlock();
        return c.EFAULT;
    }

    error_val = do_map(target.?.map.?, addr, size, alloc);

    sched_unlock();
    return error_val;
}

export fn vm_create() callconv(.c) c.vm_map_t {
    const map_ptr = kmem_alloc(@sizeOf(c.struct_vm_map)) orelse return null;
    const map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));

    map.refcnt = 1;
    map.total = 0;

    seg_init(&map.head);
    return map;
}

export fn vm_terminate(map: ?*c.struct_vm_map) callconv(.c) void {
    if (map == null) return;
    const m = map.?;
    if (m.refcnt - 1 > 0) {
        m.refcnt -= 1;
        return;
    }
    m.refcnt -= 1;

    sched_lock();
    var seg: *c.struct_seg = &m.head;
    while (true) {
        if (seg.flags != c.SEG_FREE) {
            if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
                page_free(seg.phys, seg.size);
            }
        }
        const tmp = seg;
        seg = seg.next.?;
        seg_delete(&m.head, tmp);
        if (seg == &m.head) break;
    }

    kmem_free(m);
    sched_unlock();
}

export fn vm_dup(org_map: ?*c.struct_vm_map) callconv(.c) c.vm_map_t {
    _ = org_map;
    return null;
}

export fn vm_switch(map: ?*c.struct_vm_map) callconv(.c) void {
    _ = map;
}

export fn vm_reference(map: ?*c.struct_vm_map) callconv(.c) c_int {
    map.?.refcnt += 1;
    return 0;
}

export fn vm_load(map: ?*c.struct_vm_map, mod: *c.struct_module, stack: [*c]?*anyopaque) callconv(.c) c_int {
    const m = map.?;

    if (mod.textsz == 0) return c.EINVAL;

    if (mod.datasz + mod.bsssz > 0 and trunc_page(mod.data) >= round_page(mod.text + mod.textsz)) {
        // Separate text and data/bss segments
        // 1. Text segment
        var start = trunc_page(mod.text);
        var end = round_page(mod.text + mod.textsz);
        var size = end - start;
        var seg = seg_create(&m.head, @intCast(start), size) orelse return c.ENOMEM;
        seg.flags = c.SEG_READ | c.SEG_WRITE;

        // 2. Data/BSS segment
        start = trunc_page(mod.data);
        end = round_page(mod.data + mod.datasz + mod.bsssz);
        size = end - start;
        seg = seg_create(&m.head, @intCast(start), size) orelse {
            // Clean up text segment
            const tseg = seg_lookup(&m.head, trunc_page(mod.text), 1);
            if (tseg) |ts| {
                seg_delete(&m.head, ts);
            }
            return c.ENOMEM;
        };
        seg.flags = c.SEG_READ | c.SEG_WRITE;
    } else {
        // Combined text and data/bss segment
        const start = trunc_page(mod.text);
        const total_size = mod.textsz + mod.datasz + mod.bsssz;
        const end = round_page(start + total_size);
        const size = end - start;

        const seg = seg_create(&m.head, @intCast(start), size) orelse return c.ENOMEM;
        seg.flags = c.SEG_READ | c.SEG_WRITE;
    }

    if (mod.bsssz != 0) {
        const bss_ptr: [*]u8 = @ptrFromInt(mod.data + mod.datasz);
        @memset(bss_ptr[0..mod.bsssz], 0);
    }

    // Create stack
    return do_allocate(m, stack, c.DFLSTKSZ, 1);
}

export fn vm_translate(addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t {
    _ = size;
    return @intCast(addr);
}

export fn vm_info(info: *c.struct_vminfo) callconv(.c) c_int {
    const target = info.cookie;
    const task: ?*c.struct_task = info.task;

    sched_lock();
    if (task_valid(task) == 0) {
        sched_unlock();
        return c.ESRCH;
    }
    const map_ptr = task.?.map orelse return c.ESRCH;
    const map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));
    var seg: *c.struct_seg = &map.head;
    var i: c_ulong = 0;
    while (true) {
        if (i == target) {
            info.cookie = i + 1;
            info.virt = seg.addr;
            info.size = seg.size;
            info.flags = seg.flags;
            info.phys = seg.phys;
            sched_unlock();
            return 0;
        }
        i += 1;
        seg = seg.next.?;
        if (seg == &map.head) break;
    }
    sched_unlock();
    return c.ESRCH;
}

export fn vm_init() callconv(.c) void {
    seg_init(&kernel_map.head);
    c.kernel_task.map = &kernel_map;
}
