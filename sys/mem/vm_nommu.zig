const std = @import("std");
const c = @import("c").c;
const ffi = @import("ffi");
const hal = ffi.hal;
const kutil = ffi.kutil;

const sched = ffi.sched;
const task = ffi.task;
const page = ffi.page;
const kmem = ffi.kmem;
const smp = ffi.smp;
const thread = ffi.thread;

const assert = std.debug.assert;

// ---------------------------------------------------------------------------
// Page size helpers
// ---------------------------------------------------------------------------




// ---------------------------------------------------------------------------
// Thread / task accessors
// ---------------------------------------------------------------------------




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
    const seg_ptr = kmem.alloc(@sizeOf(c.struct_seg)) orelse return null;
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
        kmem.free(seg);
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
    const pa = page.alloc(size);
    if (pa == 0) return null;

    const seg = seg_create(head, @intCast(pa), size) orelse {
        page.free(pa, size);
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

    kmem.free(seg);
}

fn seg_reserve(head: *c.struct_seg, addr: c.vaddr_t, size: usize) ?*c.struct_seg {
    const pa: c.paddr_t = @intCast(addr);

    if (page.reserve(pa, size) != 0) return null;

    const seg = seg_create(head, addr, size) orelse {
        page.free(pa, size);
        return null;
    };
    return seg;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn do_allocate(vm_map: *c.struct_vm_map, addr: *?*anyopaque, size: usize, anywhere: c_int) c_int {
    if (size == 0) return c.EINVAL;
    if (vm_map.total + size >= c.MAXMEM) return c.ENOMEM;

    var seg: *c.struct_seg = undefined;
    var start: c.vaddr_t = undefined;

    if (anywhere != 0) {
        const alloc_size = kutil.round_page(size);
        seg = seg_alloc(&vm_map.head, alloc_size) orelse return c.ENOMEM;
        start = seg.addr;
    } else {
        start = kutil.trunc_page(@intFromPtr(addr.*));
        const end = kutil.round_page(start + size);
        const alloc_size = end - start;

        seg = seg_reserve(&vm_map.head, start, alloc_size) orelse return c.ENOMEM;
        start = seg.addr;
    }
    seg.flags = c.SEG_READ | c.SEG_WRITE;

    // Zero fill
    const ptr: [*]u8 = @ptrFromInt(start);
    @memset(ptr[0..seg.size], 0);

    addr.* = @ptrFromInt(seg.addr);
    vm_map.total += seg.size;
    return 0;
}

fn do_free(vm_map: *c.struct_vm_map, addr: ?*anyopaque) c_int {
    const va = kutil.trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
    if (seg.addr != va or seg.flags & c.SEG_FREE != 0) return c.EINVAL;

    if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
        page.free(seg.phys, seg.size);
    }

    vm_map.total -= seg.size;
    seg_free(&vm_map.head, seg);

    return 0;
}

fn do_attribute(vm_map: *c.struct_vm_map, addr: ?*anyopaque, attr: c_int) c_int {
    const va = kutil.trunc_page(@intFromPtr(addr));

    const seg = seg_lookup(&vm_map.head, @intCast(va), 1) orelse return c.EINVAL;
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

fn do_map(vm_map: *c.struct_vm_map, addr: ?*anyopaque, size: usize, alloc: *?*anyopaque) c_int {
    if (size == 0) return c.EINVAL;
    if (vm_map.total + size >= c.MAXMEM) return c.ENOMEM;

    // check fault
    var tmp: ?*anyopaque = null;
    if (hal.copyout(@ptrCast(&tmp), @ptrCast(alloc), @sizeOf(?*anyopaque)) != 0) return c.EFAULT;

    const start = kutil.trunc_page(@intFromPtr(addr));
    const end = kutil.round_page(@intFromPtr(addr) + size);
    const alloc_size = end - start;

    // Find the segment that includes target address
    const tgt = seg_lookup(&vm_map.head, @intCast(start), alloc_size) orelse return c.EINVAL;
    if (tgt.flags & c.SEG_FREE != 0) return c.EINVAL;

    // Create new segment to map
    const map_ptr = kutil.cur_task().map orelse return c.ENOMEM;
    const curmap: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));
    const seg = seg_create(&curmap.head, @intCast(start), alloc_size) orelse return c.ENOMEM;
    seg.flags = tgt.flags | c.SEG_MAPPED;

    _ = hal.copyout(@ptrCast(&addr), @ptrCast(alloc), @sizeOf(?*anyopaque));

    curmap.total += alloc_size;
    return 0;
}

// ---------------------------------------------------------------------------
// Exported FFI functions
// ---------------------------------------------------------------------------

pub fn allocate(tsk: ?*c.struct_task, addr: [*c]?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int {
    var error_val: c_int = undefined;
    var uaddr: ?*anyopaque = undefined;

    sched.lock();

    if (task.valid(tsk) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (tsk != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    if (hal.copyin(@ptrCast(addr), @ptrCast(&uaddr), @sizeOf(?*anyopaque)) != 0) {
        sched.unlock();
        return c.EFAULT;
    }
    if (anywhere == 0 and !kutil.user_area(uaddr)) {
        sched.unlock();
        return c.EACCES;
    }

    error_val = do_allocate(tsk.?.map.?, &uaddr, size, anywhere);
    if (error_val == 0) {
        if (hal.copyout(@ptrCast(&uaddr), @ptrCast(addr), @sizeOf(?*anyopaque)) != 0) {
            error_val = c.EFAULT;
        }
    }
    sched.unlock();
    return error_val;
}

pub fn free(tsk: ?*c.struct_task, addr: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched.lock();
    if (task.valid(tsk) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (tsk != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    if (!kutil.user_area(addr)) {
        sched.unlock();
        return c.EFAULT;
    }

    error_val = do_free(tsk.?.map.?, addr);

    sched.unlock();
    return error_val;
}

pub fn attribute(tsk: ?*c.struct_task, addr: ?*anyopaque, attr: c_int) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched.lock();
    if (attr == 0 or attr & ~(c.PROT_READ | c.PROT_WRITE) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (task.valid(tsk) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (tsk != kutil.cur_task() and task.capable(c.CAP_EXTMEM) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    if (!kutil.user_area(addr)) {
        sched.unlock();
        return c.EFAULT;
    }

    error_val = do_attribute(tsk.?.map.?, addr, attr);

    sched.unlock();
    return error_val;
}

pub fn map(target: ?*c.struct_task, addr: ?*anyopaque, size: usize, alloc: [*c]?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = undefined;

    sched.lock();
    if (task.valid(target) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (target == kutil.cur_task()) {
        sched.unlock();
        return c.EINVAL;
    }
    if (task.capable(c.CAP_EXTMEM) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    if (!kutil.user_area(addr)) {
        sched.unlock();
        return c.EFAULT;
    }

    error_val = do_map(target.?.map.?, addr, size, alloc);

    sched.unlock();
    return error_val;
}

pub fn create() callconv(.c) c.vm_map_t {
    const map_ptr = kmem.alloc(@sizeOf(c.struct_vm_map)) orelse return null;
    const vm_map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));

    vm_map.refcnt = 1;
    vm_map.total = 0;

    seg_init(&vm_map.head);
    return vm_map;
}

pub fn terminate(vm_map: ?*c.struct_vm_map) callconv(.c) void {
    if (vm_map == null) return;
    const m = vm_map.?;
    if (m.refcnt - 1 > 0) {
        m.refcnt -= 1;
        return;
    }
    m.refcnt -= 1;

    sched.lock();
    var seg: *c.struct_seg = &m.head;
    while (true) {
        if (seg.flags != c.SEG_FREE) {
            if (seg.flags & c.SEG_SHARED == 0 and seg.flags & c.SEG_MAPPED == 0) {
                page.free(seg.phys, seg.size);
            }
        }
        const tmp = seg;
        seg = seg.next.?;
        seg_delete(&m.head, tmp);
        if (seg == &m.head) break;
    }

    kmem.free(m);
    sched.unlock();
}

pub fn dup(org_map: ?*c.struct_vm_map) callconv(.c) c.vm_map_t {
    _ = org_map;
    return null;
}

pub fn @"switch"(vm_map: ?*c.struct_vm_map) callconv(.c) void {
    _ = vm_map;
}

pub fn reference(vm_map: ?*c.struct_vm_map) callconv(.c) c_int {
    vm_map.?.refcnt += 1;
    return 0;
}

pub fn load(vm_map: ?*c.struct_vm_map, mod: *c.struct_module, stack: [*c]?*anyopaque) callconv(.c) c_int {
    const m = vm_map.?;

    if (mod.textsz == 0) return c.EINVAL;

    if (mod.datasz + mod.bsssz > 0 and kutil.trunc_page(mod.data) >= kutil.round_page(mod.text + mod.textsz)) {
        // Separate text and data/bss segments
        // 1. Text segment
        var start = kutil.trunc_page(mod.text);
        var end = kutil.round_page(mod.text + mod.textsz);
        var size = end - start;
        var seg = seg_create(&m.head, @intCast(start), size) orelse return c.ENOMEM;
        seg.flags = c.SEG_READ | c.SEG_WRITE;

        // 2. Data/BSS segment
        start = kutil.trunc_page(mod.data);
        end = kutil.round_page(mod.data + mod.datasz + mod.bsssz);
        size = end - start;
        seg = seg_create(&m.head, @intCast(start), size) orelse {
            // Clean up text segment
            const tseg = seg_lookup(&m.head, kutil.trunc_page(mod.text), 1);
            if (tseg) |ts| {
                seg_delete(&m.head, ts);
            }
            return c.ENOMEM;
        };
        seg.flags = c.SEG_READ | c.SEG_WRITE;
    } else {
        // Combined text and data/bss segment
        const start = kutil.trunc_page(mod.text);
        const total_size = mod.textsz + mod.datasz + mod.bsssz;
        const end = kutil.round_page(start + total_size);
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

pub fn translate(addr: c.vaddr_t, size: usize) callconv(.c) c.paddr_t {
    _ = size;
    return @intCast(addr);
}

pub fn info(vminfo: *c.struct_vminfo) callconv(.c) c_int {
    const target = vminfo.cookie;
    const tsk: ?*c.struct_task = vminfo.task;

    sched.lock();
    if (task.valid(tsk) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    const map_ptr = tsk.?.map orelse return c.ESRCH;
    const vm_map: *c.struct_vm_map = @ptrCast(@alignCast(map_ptr));
    var seg: *c.struct_seg = &vm_map.head;
    var i: c_ulong = 0;
    while (true) {
        if (i == target) {
            vminfo.cookie = i + 1;
            vminfo.virt = seg.addr;
            vminfo.size = seg.size;
            vminfo.flags = seg.flags;
            vminfo.phys = seg.phys;
            sched.unlock();
            return 0;
        }
        i += 1;
        seg = seg.next.?;
        if (seg == &vm_map.head) break;
    }
    sched.unlock();
    return c.ESRCH;
}

pub fn init() callconv(.c) void {
    seg_init(&kernel_map.head);
    c.kernel_task.map = &kernel_map;
}

comptime {
    if (@import("root") == @This()) {
        @export(&allocate, .{ .name = "vm_allocate", .linkage = .strong });
        @export(&free, .{ .name = "vm_free", .linkage = .strong });
        @export(&attribute, .{ .name = "vm_attribute", .linkage = .strong });
        @export(&map, .{ .name = "vm_map", .linkage = .strong });
        @export(&create, .{ .name = "vm_create", .linkage = .strong });
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
