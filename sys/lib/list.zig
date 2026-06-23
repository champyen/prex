const std = @import("std");

pub const List = extern struct {
    next: ?*List = null,
    prev: ?*List = null,

    pub inline fn init(head: *List) void {
        head.next = head;
        head.prev = head;
    }

    pub inline fn insertAfter(prev: *List, node: *List) void {
        node.prev = prev;
        node.next = prev.next;
        prev.next.?.prev = node;
        prev.next = node;
    }

    pub inline fn remove(node: *List) void {
        node.prev.?.next = node.next;
        node.next.?.prev = node.prev;
    }

    pub inline fn isEmpty(head: *List) bool {
        return head.next == head;
    }

    pub inline fn first(head: *List) *List {
        return head.next.?;
    }

    pub inline fn nextNode(node: *List) *List {
        return node.next.?;
    }

    pub inline fn entry(node: *List, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const offset = @offsetOf(ParentType, field_name);
        return @ptrCast(@as(*ParentType, @ptrFromInt(@intFromPtr(node) - offset)));
    }
};

/// Comptime-validated type-safe helpers over a parent type T with a
/// field `field_name` of type Node (e.g. `c.struct_list`).
///
/// The comptime block verifies that T has the named field. The two
/// helpers then perform the @fieldParentPtr / @ptrCast traversal
/// internally, replacing the cast-at-every-use pattern at call sites.
pub fn IntrusiveList(comptime T: type, comptime Node: type, comptime field_name: []const u8) type {
    return struct {
        comptime {
            if (!@hasField(T, field_name))
                @compileError("IntrusiveList: type " ++ @typeName(T) ++ " has no field '" ++ field_name ++ "'");
        }

        /// Get the embedded node pointer from a parent T (or any pointer
        /// to a T), cast to *Node.
        /// Replaces: `@as(*ffi.lib.List, @ptrCast(&parent.*.field_name))`
        pub inline fn node(p: anytype) *Node {
            const offset = @offsetOf(T, field_name);
            const addr: usize = @intFromPtr(p);
            return @ptrFromInt(addr + offset);
        }

        /// Walk back from a list node pointer to the parent struct.
        /// Replaces: `@fieldParentPtr("field_name", node)`
        pub inline fn parent(n: *Node) *T {
            return @fieldParentPtr(field_name, n);
        }
    };
}

