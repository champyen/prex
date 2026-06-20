const std = @import("std");
const c = @import("c").c;

const ffi = @import("ffi");
const sched = ffi.sched;
const page = ffi.page;
const vm = ffi.vm;

// Type-safe inline functions for macros
pub inline fn ptokv(pa: c.paddr_t) ?*anyopaque {
    return @ptrFromInt(@as(usize, pa) + c.KERNOFFSET);
}

pub inline fn kvtop(va: anytype) c.paddr_t {
    return @intFromPtr(va) - c.KERNOFFSET;
}

pub inline fn alloc_size(n: usize) usize {
    return (n + ALIGN_MASK) & ~@as(usize, ALIGN_MASK);
}

pub inline fn pagetop(n: anytype) *page_hdr {
    const addr: usize = @intFromPtr(n);
    const page_size: usize = @intCast(c.PAGE_SIZE);
    return @ptrFromInt(addr & ~(page_size - 1));
}

pub inline fn blkndx(b: *block_hdr) usize {
    return @as(usize, b.*.size) >> 4;
}

pub inline fn max(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

// List helpers matching task.zig's style
pub inline fn list_init_fn(head: *c.struct_list) void {
    head.*.next = head;
    head.*.prev = head;
}

pub inline fn list_insert_fn(prev: *c.struct_list, node: *c.struct_list) void {
    node.*.next = prev.*.next;
    node.*.prev = prev;
    prev.*.next.*.prev = node;
    prev.*.next = node;
}

pub inline fn list_remove_fn(node: *c.struct_list) void {
    node.*.prev.*.next = node.*.next;
    node.*.next.*.prev = node.*.prev;
}

pub inline fn list_empty(head: *c.struct_list) bool {
    return head.*.next == head;
}

pub inline fn list_first(head: *c.struct_list) *c.struct_list {
    return head.*.next;
}

pub inline fn list_next_node(node: *c.struct_list) *c.struct_list {
    return node.*.next;
}

pub inline fn list_entry(node: *c.struct_list) *block_hdr {
    const offset = @offsetOf(block_hdr, "link");
    const ptr_val = @intFromPtr(node) - offset;
    return @ptrCast(@alignCast(@as(*block_hdr, @ptrFromInt(ptr_val))));
}

const block_hdr = extern struct {
    magic: u16,
    size: u16,
    link: c.struct_list,
    pg_next: ?*block_hdr,
};

const page_hdr = extern struct {
    magic: u16,
    nallocs: u16,
    first_blk: block_hdr,
};

// Constants
const ALIGN_SIZE = 16;
const ALIGN_MASK = ALIGN_SIZE - 1;
const NR_BLOCK_LIST = c.PAGE_SIZE / ALIGN_SIZE;
const BLOCK_MAGIC = 0xdead;
const PAGE_MAGIC = 0xbeef;
const BLKHDR_SIZE = @sizeOf(block_hdr);
const PGHDR_SIZE = @sizeOf(page_hdr);
const MAX_ALLOC_SIZE = if (@hasDecl(c, "CONFIG_MAX_ALLOC_SIZE")) c.CONFIG_MAX_ALLOC_SIZE else c.PAGE_SIZE - PGHDR_SIZE;
const MIN_BLOCK_SIZE = BLKHDR_SIZE + 16;

// Global free_blocks array
var free_blocks: [NR_BLOCK_LIST]c.struct_list = undefined;

// Find the free block for the specified size
fn block_find(size: usize) ?*block_hdr {
    var i: usize = size >> 4;
    while (i < NR_BLOCK_LIST) : (i += 1) {
        if (!list_empty(&free_blocks[i])) {
            const n = list_first(&free_blocks[i]);
            return list_entry(n);
        }
    }
    return null;
}

// Exported FFI functions
pub fn alloc(size: usize) callconv(.c) ?*anyopaque {
    sched.lock();

    const total_size = alloc_size(size + BLKHDR_SIZE);
    if (total_size > MAX_ALLOC_SIZE) {
        @panic("kmem_alloc: too large allocation");
    }

    var active_blk: *block_hdr = undefined;
    var pg: *page_hdr = undefined;

    if (block_find(total_size)) |found_blk| {
        active_blk = found_blk;
        list_remove_fn(&active_blk.*.link);
        pg = pagetop(active_blk);
    } else {
        var pg_size = alloc_size(total_size + PGHDR_SIZE);
        if (pg_size < c.PAGE_SIZE) pg_size = c.PAGE_SIZE;

        const pa = page.alloc(@intCast(pg_size));
        if (pa == 0) {
            sched.unlock();
            return null;
        }
        pg = @ptrCast(@alignCast(ptokv(pa).?));
        pg.*.nallocs = 0;
        pg.*.magic = PAGE_MAGIC;

        active_blk = &pg.*.first_blk;
        active_blk.*.magic = BLOCK_MAGIC;
        active_blk.*.size = @intCast(pg_size - (PGHDR_SIZE - BLKHDR_SIZE));
        active_blk.*.pg_next = null;
    }

    if (pg.*.magic != PAGE_MAGIC or active_blk.*.magic != BLOCK_MAGIC) {
        @panic("kmem_alloc: overrun");
    }

    if (active_blk.*.size - total_size >= MIN_BLOCK_SIZE) {
        const newblk: *block_hdr = @ptrFromInt(@intFromPtr(active_blk) + total_size);
        newblk.*.magic = BLOCK_MAGIC;
        newblk.*.size = @intCast(active_blk.*.size - total_size);
        list_insert_fn(&free_blocks[blkndx(newblk)], &newblk.*.link);

        newblk.*.pg_next = active_blk.*.pg_next;
        active_blk.*.pg_next = newblk;
        active_blk.*.size = @intCast(total_size);
    }

    pg.*.nallocs += 1;
    const p: ?*anyopaque = @ptrFromInt(@intFromPtr(active_blk) + BLKHDR_SIZE);

    sched.unlock();
    return p;
}

pub fn free(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr == null) {
        @panic("kmem_free: null pointer");
    }

    sched.lock();

    const blk: *block_hdr = @ptrCast(@alignCast(@as(*block_hdr, @ptrFromInt(@intFromPtr(ptr) - BLKHDR_SIZE))));
    if (blk.*.magic != BLOCK_MAGIC) {
        @panic("kmem_free: invalid address");
    }

    const pg = pagetop(blk);
    if (blk.*.size > (c.PAGE_SIZE - PGHDR_SIZE)) {
        pg.*.nallocs -= 1;
        if (pg.*.nallocs == 0) {
            var tmp: ?*block_hdr = &pg.*.first_blk;
            while (tmp) |t| {
                if (t != blk) {
                    list_remove_fn(&t.*.link);
                }
                tmp = t.*.pg_next;
            }
            pg.*.magic = 0;
            page.free(kvtop(pg), @intCast(blk.*.size + PGHDR_SIZE));
        } else {
            @panic("kmem_free: large block split free not supported");
        }
    } else {
        list_insert_fn(&free_blocks[blkndx(blk)], &blk.*.link);
        pg.*.nallocs -= 1;
        if (pg.*.nallocs == 0) {
            var tmp: ?*block_hdr = &pg.*.first_blk;
            while (tmp) |t| {
                list_remove_fn(&t.*.link);
                tmp = t.*.pg_next;
            }
            pg.*.magic = 0;
            page.free(kvtop(pg), @intCast(c.PAGE_SIZE));
        }
    }

    sched.unlock();
}

pub fn map(addr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const pa = vm.translate(@intFromPtr(addr), size);
    if (pa == 0) return null;
    return ptokv(pa);
}

pub fn init() callconv(.c) void {
    var i: usize = 0;
    while (i < NR_BLOCK_LIST) : (i += 1) {
        list_init_fn(&free_blocks[i]);
    }
}

comptime {
    if (@import("root") == @This()) {
        @export(&alloc, .{ .name = "kmem_alloc", .linkage = .strong });
        @export(&free, .{ .name = "kmem_free", .linkage = .strong });
        @export(&map, .{ .name = "kmem_map", .linkage = .strong });
        @export(&init, .{ .name = "kmem_init", .linkage = .strong });
    }
}