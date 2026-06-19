const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

comptime {
    @export(&enqueue, .{ .name = "enqueue", .linkage = .strong });
    @export(&dequeue, .{ .name = "dequeue", .linkage = .strong });
    @export(&queue_insert, .{ .name = "queue_insert", .linkage = .strong });
    @export(&queue_remove, .{ .name = "queue_remove", .linkage = .strong });
}

fn enqueue(head: c.queue_t, item: c.queue_t) callconv(.c) void {
    item.*.next = head;
    item.*.prev = head.*.prev;
    item.*.prev.*.next = item;
    head.*.prev = item;
}

fn dequeue(head: c.queue_t) callconv(.c) c.queue_t {
    if (head.*.next == head) return null;
    const item = head.*.next;
    item.*.next.*.prev = head;
    head.*.next = item.*.next;
    return item;
}

fn queue_insert(prev: c.queue_t, item: c.queue_t) callconv(.c) void {
    item.*.prev = prev;
    item.*.next = prev.*.next;
    prev.*.next.*.prev = item;
    prev.*.next = item;
}

fn queue_remove(item: c.queue_t) callconv(.c) void {
    item.*.prev.*.next = item.*.next;
    item.*.next.*.prev = item.*.prev;
}
