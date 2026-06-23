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
        /// Replaces: `@as(*ffi.lib.Queue, @ptrCast(&parent.*.field_name))`
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

