const std = @import("std");
const c = @import("c").c;

pub const Queue = extern struct {
    next: ?*Queue = null,
    prev: ?*Queue = null,

    pub inline fn init(self: *Queue) void {
        self.next = self;
        self.prev = self;
    }

    pub inline fn isEmpty(self: *const Queue) bool {
        return self.next == self;
    }

    pub inline fn insert(self: *Queue, item: *Queue) void {
        item.prev = self;
        item.next = self.next;
        self.next.?.prev = item;
        self.next = item;
    }

    pub inline fn remove(self: *Queue) void {
        self.prev.?.next = self.next;
        self.next.?.prev = self.prev;
    }

    pub inline fn enqueue(self: *Queue, item: *Queue) void {
        item.next = self;
        item.prev = self.prev;
        self.prev.?.next = item;
        self.prev = item;
    }

    pub inline fn dequeue(self: *Queue) ?*Queue {
        if (self.next == self) return null;
        const item = self.next.?;
        item.next.?.prev = self;
        self.next = item.next;
        return item;
    }

    pub inline fn first(self: *const Queue) *Queue {
        return self.next.?;
    }

    pub inline fn nextNode(self: *const Queue) *Queue {
        return self.next.?;
    }

    pub inline fn prevNode(self: *const Queue) *Queue {
        return self.prev.?;
    }

    pub inline fn entry(self: *Queue, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const offset = @offsetOf(ParentType, field_name);
        return @ptrCast(@as(*ParentType, @ptrFromInt(@intFromPtr(self) - offset)));
    }
};

pub fn c_enqueue(head: c.queue_t, item: c.queue_t) callconv(.c) void {
    const q: *Queue = @ptrCast(head);
    const it: *Queue = @ptrCast(item);
    q.enqueue(it);
}

pub fn c_dequeue(head: c.queue_t) callconv(.c) c.queue_t {
    const q: *Queue = @ptrCast(head);
    if (q.dequeue()) |it| {
        return @ptrCast(it);
    }
    return null;
}

pub fn c_insert(prev: c.queue_t, item: c.queue_t) callconv(.c) void {
    const p: *Queue = @ptrCast(prev);
    const it: *Queue = @ptrCast(item);
    p.insert(it);
}

pub fn c_remove(item: c.queue_t) callconv(.c) void {
    const it: *Queue = @ptrCast(item);
    it.remove();
}

comptime {
    if (@import("root") == @This()) {
        @export(&c_enqueue, .{ .name = "enqueue", .linkage = .strong });
        @export(&c_dequeue, .{ .name = "dequeue", .linkage = .strong });
        @export(&c_insert, .{ .name = "queue_insert", .linkage = .strong });
        @export(&c_remove, .{ .name = "queue_remove", .linkage = .strong });
    }
}
