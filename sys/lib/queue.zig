const c = @import("c").c;

pub fn enqueue(head: c.queue_t, item: c.queue_t) callconv(.c) void {
    item.*.next = head;
    item.*.prev = head.*.prev;
    item.*.prev.*.next = item;
    head.*.prev = item;
}

pub fn dequeue(head: c.queue_t) callconv(.c) c.queue_t {
    if (head.*.next == head) return null;
    const item = head.*.next;
    item.*.next.*.prev = head;
    head.*.next = item.*.next;
    return item;
}

pub fn insert(prev: c.queue_t, item: c.queue_t) callconv(.c) void {
    item.*.prev = prev;
    item.*.next = prev.*.next;
    prev.*.next.*.prev = item;
    prev.*.next = item;
}

pub fn remove(item: c.queue_t) callconv(.c) void {
    item.*.prev.*.next = item.*.next;
    item.*.next.*.prev = item.*.prev;
}

comptime {
    if (@import("root") == @This()) {
        @export(&enqueue, .{ .name = "enqueue", .linkage = .strong });
        @export(&dequeue, .{ .name = "dequeue", .linkage = .strong });
        @export(&insert, .{ .name = "queue_insert", .linkage = .strong });
        @export(&remove, .{ .name = "queue_remove", .linkage = .strong });
    }
}
