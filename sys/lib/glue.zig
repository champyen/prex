const std = @import("std");

pub const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

// Manual definitions for C symbols that are broken in cImport
pub extern var curthread: c.thread_t;
pub extern var kernel_lock: c.spinlock_t;
pub extern var idle_thread: c.struct_thread;

pub const NR_PRIQS = 32;

// Implementation of macros as Zig functions to avoid linker errors
pub inline fn list_init(head: [*c]c.list) void {
    head.*.next = head;
    head.*.prev = head;
}

pub inline fn queue_init(head: [*c]c.queue) void {
    head.*.next = head;
    head.*.prev = head;
}

pub inline fn queue_empty(head: [*c]c.queue) bool {
    return head.*.next == head;
}

pub inline fn list_empty(head: [*c]c.list) bool {
    return head.*.next == head;
}

pub inline fn event_init(event: [*c]c.event, name_val: [*c]const u8) void {
    queue_init(&event.*.sleepq);
    event.*.name = @constCast(name_val);
}

pub inline fn event_waiting(event: [*c]c.event) bool {
    return !queue_empty(&event.*.sleepq);
}

// Spinlocks (ported in zig_runtime.zig)
pub extern fn spinlock_lock(lock: [*c]c.spinlock_t) void;
pub extern fn spinlock_unlock(lock: [*c]c.spinlock_t) void;

// Deadlock stubs
pub inline fn deadlock_record_lock(lock: ?*anyopaque, type_val: c_int) void { _ = lock; _ = type_val; }
pub inline fn deadlock_record_unlock(lock: ?*anyopaque) void { _ = lock; }
pub inline fn deadlock_sleep(r: ?*anyopaque, n: [*c]const u8) void { _ = r; _ = n; }
pub inline fn deadlock_stop_sleep() void {}
pub inline fn deadlock_mutex_wait(m: c.mutex_t, waiter: c.thread_t) void { _ = m; _ = waiter; }
pub inline fn deadlock_mutex_stop_wait(waiter: c.thread_t) void { _ = waiter; }

// Other ported functions
pub extern fn exception_post(task: c.task_t, excno: c_int) c_int;
pub extern fn object_cleanup(task: c.task_t) void;
pub extern fn mutex_cleanup(task: c.task_t) void;
pub extern fn cond_cleanup(task: c.task_t) void;
pub extern fn sem_cleanup(task: c.task_t) void;
pub extern fn msg_cancel(t: c.thread_t) void;
pub extern fn mutex_cancel(t: c.thread_t) void;
pub extern fn mutex_setpri(t: c.thread_t, pri: c_int) void;
pub extern fn ksem_post(s: c.sem_t) c_int;
pub extern fn object_valid(obj: c.object_t) c_int;
pub extern fn mutex_lock(mp: [*c]c.mutex_t) c_int;
pub extern fn mutex_unlock(mp: [*c]c.mutex_t) c_int;
pub extern fn msg_abort(obj: c.object_t) void;
pub extern fn thread_destroy(th: c.thread_t) void;
pub extern fn vm_load(map: c.vm_map_t, mod: [*c]c.struct_module, stack: [*c]?*anyopaque) c_int;

// MMU HAL calls (using correct names from hal.h)
pub inline fn mmu_init(table: [*c]c.struct_mmumap) void { c.mmu_init(table); }
pub inline fn mmu_newmap() c.pgd_t { return c.mmu_newmap(); }
pub inline fn mmu_terminate(pgd: c.pgd_t) void { c.mmu_terminate(pgd); }
pub inline fn mmu_map(pgd: c.pgd_t, pa: c.paddr_t, va: c.vaddr_t, sz: usize, t: c_int) c_int { return c.mmu_map(pgd, pa, va, sz, t); }
pub inline fn mmu_switch(pgd: c.pgd_t) void { c.mmu_switch(pgd); }
pub inline fn mmu_extract(pgd: c.pgd_t, va: c.vaddr_t, sz: usize) c.paddr_t { return c.mmu_extract(pgd, va, sz); }

pub inline fn user_area(a: ?*const anyopaque) bool {
    if (a == null) return false;
    if (@hasDecl(c, "CONFIG_MMU")) {
        return @intFromPtr(a) < c.USERLIMIT;
    } else {
        return true;
    }
}

pub inline fn trunc_page(x: usize) usize {
    return x & ~@as(usize, c.PAGE_SIZE - 1);
}

pub inline fn round_page(x: usize) usize {
    return (x + (c.PAGE_SIZE - 1)) & ~@as(usize, c.PAGE_SIZE - 1);
}
