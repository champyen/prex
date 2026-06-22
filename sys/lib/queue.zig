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

// C wrapper functions that use c.queue_t (the C pointer type for queue heads).
// These are needed because the Zig compiler cannot inline Queue methods across
// separate compilation units, so it generates calls to the C function names
// (enqueue, dequeue, queue_insert, queue_remove) that are declared in
// include/sys/queue.h. The wrapper functions are exported only when this
// file is the root of the compilation unit.
pub const c_export = struct {
    pub fn enqueue(head: c.queue_t, item: c.queue_t) callconv(.c) void {
        const q: *Queue = @ptrCast(head);
        const it: *Queue = @ptrCast(item);
        q.enqueue(it);
    }

    pub fn dequeue(head: c.queue_t) callconv(.c) c.queue_t {
        const q: *Queue = @ptrCast(head);
        if (q.dequeue()) |it| {
            return @ptrCast(it);
        }
        return null;
    }

    pub fn queue_insert(prev: c.queue_t, item: c.queue_t) callconv(.c) void {
        const p: *Queue = @ptrCast(prev);
        const it: *Queue = @ptrCast(item);
        p.insert(it);
    }

    pub fn queue_remove(item: c.queue_t) callconv(.c) void {
        const it: *Queue = @ptrCast(item);
        it.remove();
    }
};

comptime {
    if (@import("root") == @This()) {
        @export(&c_export.enqueue, .{ .name = "enqueue", .linkage = .strong });
        @export(&c_export.dequeue, .{ .name = "dequeue", .linkage = .strong });
        @export(&c_export.queue_insert, .{ .name = "queue_insert", .linkage = .strong });
        @export(&c_export.queue_remove, .{ .name = "queue_remove", .linkage = .strong });
    }
}

/// Comptime-validated type-safe helpers over a parent type T with a
/// field `field_name` of type Node (e.g. `c.struct_queue`).
pub fn IntrusiveQueue(comptime T: type, comptime Node: type, comptime field_name: []const u8) type {
    return struct {
        comptime {
            if (!@hasField(T, field_name))
                @compileError("IntrusiveQueue: type " ++ @typeName(T) ++ " has no field '" ++ field_name ++ "'");
        }

        /// Get the embedded node pointer from a parent T (or any pointer
        /// to a T), cast to *Node.
        /// Replaces: `@as(*ffi.Queue, @ptrCast(&parent.*.field_name))`
        pub inline fn node(p: anytype) *Node {
            const offset = @offsetOf(T, field_name);
            const addr: usize = @intFromPtr(p);
            return @ptrFromInt(addr + offset);
        }

        /// Walk back from a queue node pointer to the parent struct.
        /// Replaces: `@fieldParentPtr("field_name", node)`
        pub inline fn parent(n: *Node) *T {
            return @fieldParentPtr(field_name, n);
        }
    };
}

