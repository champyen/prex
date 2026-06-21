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
