const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

inline fn is_mutex_initializer(m: c.mutex_t) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x4d496e69;
    }
    return false;
}

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

inline fn list_init(head: *c.struct_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove(node: *c.struct_list) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == @as(?*c.struct_list, @ptrCast(head));
}

inline fn list_first(head: *c.struct_list) *c.struct_list {
    return @ptrCast(head.next.?);
}

inline fn list_next(node: *c.struct_list) *c.struct_list {
    return @ptrCast(node.next.?);
}

fn mutex_valid(m: c.mutex_t) c_int {
    const head = &get_curtask().*.mutexes;
    var n = head.*.next.?;
    while (n != @as(*c.struct_list, @ptrCast(head))) : (n = n.*.next.?) {
        const node: *c.struct_list = @ptrCast(n);
        const tmp: *c.struct_mutex = @fieldParentPtr("task_link", node);
        if (tmp == m) {
            return 1;
        }
    }
    return 0;
}

fn mutex_copyin(ump: ?*c.mutex_t, kmp: ?*c.mutex_t) c_int {
    var m: c.mutex_t = undefined;
    if (c.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t)) != 0) {
        return c.EFAULT;
    }

    if (is_mutex_initializer(m)) {
        const error_code = mutex_init(ump);
        if (error_code != 0) {
            return error_code;
        }
        _ = c.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t));
    } else {
        if (mutex_valid(m) == 0) {
            return c.EINVAL;
        }
    }
    kmp.?.* = m;
    return 0;
}

fn prio_inherit(waiter: c.thread_t) c_int {
    var m: c.mutex_t = waiter.*.mutex_waiting;
    var holder: c.thread_t = undefined;
    var count: c_int = 0;
    var iters: u32 = 0;
    
    while (m != null) {
        holder = m.*.holder;
        c.deadlock_check_loop("prio_inherit", &iters);
        
        if (holder == waiter) {
            return c.EDEADLK;
        }
        
        if (holder.*.priority > waiter.*.priority) {
            c.sched_setpri(holder, holder.*.basepri, waiter.*.priority);
            m.*.priority = waiter.*.priority;
        }
        
        m = @ptrCast(holder.*.mutex_waiting);
        
        count += 1;
        if (count >= c.MAXINHERIT) {
            break;
        }
    }
    return 0;
}

fn prio_uninherit(t: c.thread_t) void {
    if (t.*.priority == t.*.basepri) {
        return;
    }
    
    var maxpri = t.*.basepri;
    const head = &t.*.mutexes;
    var n = head.*.next.?;
    while (n != @as(*c.struct_list, @ptrCast(head))) : (n = n.*.next.?) {
        const node: *c.struct_list = @ptrCast(n);
        const m: *c.struct_mutex = @fieldParentPtr("link", node);
        if (m.*.priority < maxpri) {
            maxpri = m.*.priority;
        }
    }
    
    c.sched_setpri(t, t.*.basepri, maxpri);
}

pub fn mutex_init(mp: ?*c.mutex_t) callconv(.c) c_int {
    const self = get_curtask();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }
    
    const mem = c.kmem_alloc(@sizeOf(c.struct_mutex)) orelse return c.ENOMEM;
    const m: c.mutex_t = @ptrCast(@alignCast(mem));
    
    c.event_init(&m.*.event, "mutex");
    m.*.owner = self;
    m.*.holder = null;
    m.*.priority = c.MINPRI;
    
    if (c.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(mp)), @sizeOf(c.mutex_t)) != 0) {
        c.kmem_free(m);
        return c.EFAULT;
    }
    
    c.sched_lock();
    list_insert(&self.*.mutexes, &m.*.task_link);
    self.*.nsyncs += 1;
    c.sched_unlock();
    return 0;
}

fn mutex_deallocate(m: c.mutex_t) void {
    m.*.owner.*.nsyncs -= 1;
    list_remove(&m.*.task_link);
    c.kmem_free(m);
}

pub fn mutex_destroy(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;
    c.sched_lock();
    if (c.copyin(@as(?*const anyopaque, @ptrCast(mp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t)) != 0) {
        c.sched_unlock();
        return c.EFAULT;
    }
    if (mutex_valid(m) == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (m.*.holder != null or !c.queue_empty(&m.*.event.sleepq)) {
        c.sched_unlock();
        return c.EBUSY;
    }
    mutex_deallocate(m);
    c.sched_unlock();
    return 0;
}

pub fn mutex_cleanup(task: c.task_t) callconv(.c) void {
    while (!list_empty(&task.*.mutexes)) {
        const n = list_first(&task.*.mutexes);
        const m: *c.struct_mutex = @fieldParentPtr("task_link", n);
        mutex_deallocate(m);
    }
}

pub fn mutex_lock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;
    
    c.sched_lock();
    const error_code = mutex_copyin(mp, &m);
    if (error_code != 0) {
        c.sched_unlock();
        return error_code;
    }
    
    if (m.*.holder == get_curthread()) {
        m.*.locks += 1;
    } else {
        if (m.*.holder == null) {
            m.*.priority = get_curthread().*.priority;
            m.*.locks = 1;
            m.*.holder = get_curthread();
            list_insert(&get_curthread().*.mutexes, &m.*.link);
            c.deadlock_record_lock(m, c.LOCK_TYPE_MUTEX);
        } else {
            c.deadlock_mutex_wait(m, get_curthread());
            get_curthread().*.mutex_waiting = m;
            const inherit_err = prio_inherit(get_curthread());
            if (inherit_err != 0) {
                c.deadlock_mutex_stop_wait(get_curthread());
                get_curthread().*.mutex_waiting = null;
                c.sched_unlock();
                return inherit_err;
            }
            const rc = c.sched_sleep(&m.*.event);
            c.deadlock_mutex_stop_wait(get_curthread());
            get_curthread().*.mutex_waiting = null;
            if (rc == c.SLP_INTR) {
                c.sched_unlock();
                return c.EINTR;
            }
            m.*.locks = 1;
            list_insert(&get_curthread().*.mutexes, &m.*.link);
            c.deadlock_record_lock(m, c.LOCK_TYPE_MUTEX);
        }
    }
    c.sched_unlock();
    return 0;
}

pub fn mutex_trylock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;
    
    c.sched_lock();
    const error_code = mutex_copyin(mp, &m);
    if (error_code != 0) {
        c.sched_unlock();
        return error_code;
    }
    
    var err: c_int = 0;
    if (m.*.holder == get_curthread()) {
        m.*.locks += 1;
    } else {
        if (m.*.holder != null) {
            err = c.EBUSY;
        } else {
            m.*.locks = 1;
            m.*.holder = get_curthread();
            list_insert(&get_curthread().*.mutexes, &m.*.link);
            c.deadlock_record_lock(m, c.LOCK_TYPE_MUTEX);
        }
    }
    c.sched_unlock();
    return err;
}

pub fn mutex_unlock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;
    
    c.sched_lock();
    const error_code = mutex_copyin(mp, &m);
    if (error_code != 0) {
        c.sched_unlock();
        return error_code;
    }
    
    if (m.*.holder != get_curthread() or m.*.locks <= 0) {
        c.sched_unlock();
        return c.EPERM;
    }
    
    m.*.locks -= 1;
    if (m.*.locks == 0) {
        c.deadlock_record_unlock(m);
        list_remove(&m.*.link);
        prio_uninherit(get_curthread());
        
        m.*.holder = c.sched_wakeone(&m.*.event);
        if (m.*.holder) |holder| {
            holder.*.mutex_waiting = null;
        }
        
        m.*.priority = if (m.*.holder) |holder| holder.*.priority else c.MINPRI;
    }
    c.sched_unlock();
    return 0;
}

pub fn mutex_cancel(t: c.thread_t) callconv(.c) void {
    const head = &t.*.mutexes;
    while (!list_empty(head)) {
        const n = list_first(head);
        const m: *c.struct_mutex = @fieldParentPtr("link", n);
        m.*.locks = 0;
        list_remove(&m.*.link);
        
        const holder = c.sched_wakeone(&m.*.event);
        if (holder) |h| {
            h.*.mutex_waiting = null;
            m.*.locks = 1;
            list_insert(&h.*.mutexes, &m.*.link);
        }
        m.*.holder = holder;
    }
}

pub fn mutex_setpri(t: c.thread_t, pri: c_int) callconv(.c) void {
    if (t.*.mutex_waiting != null and pri < t.*.priority) {
        _ = prio_inherit(t);
    }
}

comptime {
    @export(&mutex_init, .{ .name = "mutex_init", .linkage = .strong });
    @export(&mutex_destroy, .{ .name = "mutex_destroy", .linkage = .strong });
    @export(&mutex_cleanup, .{ .name = "mutex_cleanup", .linkage = .strong });
    @export(&mutex_lock, .{ .name = "mutex_lock", .linkage = .strong });
    @export(&mutex_trylock, .{ .name = "mutex_trylock", .linkage = .strong });
    @export(&mutex_unlock, .{ .name = "mutex_unlock", .linkage = .strong });
    @export(&mutex_cancel, .{ .name = "mutex_cancel", .linkage = .strong });
    @export(&mutex_setpri, .{ .name = "mutex_setpri", .linkage = .strong });
}
