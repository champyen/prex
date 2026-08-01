/// fs_ffi.zig - Centralized FFI module for the VFS server
///
/// Encapsulates raw C imports and provides clean namespaces (prog, task, elf)
/// and layout-compatible structures.

pub const prog = @import("prog");
pub const task = @import("task");

const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("sys/list.h");
    @cInclude("sys/buf.h");
    @cInclude("sys/vnode.h");
    @cInclude("sys/file.h");
    @cInclude("sys/mount.h");
    @cInclude("sys/poll.h");
    @cInclude("sys/capability.h");
    @cInclude("sys/param.h");
    @cInclude("ipc/fs.h");
    @cInclude("ipc/ipc.h");
    @cInclude("ipc/exec.h");
    @cInclude("ipc/proc.h");
    @cInclude("usr/server/fs/vfs/vfs.h");
});

pub const raw = c;

pub const List = extern struct {
    next: ?*List = null,
    prev: ?*List = null,

    pub inline fn init(self: *List) void {
        self.next = self;
        self.prev = self;
    }

    pub inline fn first(self: *List) ?*List {
        return self.next;
    }

    pub inline fn nextNode(self: *List) ?*List {
        return self.next;
    }

    pub inline fn insert(self: *List, node: *List) void {
        node.next = self.next;
        node.prev = self;
        if (self.next) |n| {
            n.prev = node;
        }
        self.next = node;
    }

    pub inline fn remove(self: *List) void {
        if (self.prev) |p| {
            p.next = self.next;
        }
        if (self.next) |n| {
            n.prev = self.prev;
        }
    }

    pub inline fn empty(self: *List) bool {
        return self.next == self;
    }

    pub inline fn entry(self: *List, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const ptr: *c.struct_list = @ptrCast(self);
        return @fieldParentPtr(field_name, ptr);
    }
};

pub inline fn VOP_POLL(vp: c.vnode_t, fp: c.file_t, events: c_int) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_poll) |poll_fn| {
                return poll_fn(vp, fp, events);
            }
        }
    }
    return 0;
}
