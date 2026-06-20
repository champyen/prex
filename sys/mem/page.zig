const std = @import("std");
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    c.panic("Zig panic");
    while (true) {}
}
const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

const Page = extern struct {
    next: ?*Page,
    prev: ?*Page,
    size: c.vsize_t,
};

var page_head = Page{
    .next = null,
    .prev = null,
    .size = 0,
};
var total_size: c.psize_t = 0;
var used_size: c.psize_t = 0;
var bootdisk_size: c.psize_t = 0;

inline fn ptokv(pa: c.paddr_t) ?*anyopaque {
    return @ptrFromInt(@as(usize, pa) + c.KERNOFFSET);
}

inline fn kvtop(va: anytype) c.paddr_t {
    return @intFromPtr(va) - c.KERNOFFSET;
}

inline fn round_page(x: usize) usize {
    const page_mask = @as(usize, @intCast(c.PAGE_SIZE - 1));
    return (x + page_mask) & ~page_mask;
}

inline fn trunc_page(x: usize) usize {
    const page_mask = @as(usize, @intCast(c.PAGE_SIZE - 1));
    return x & ~page_mask;
}

fn page_is_ram(pa: c.paddr_t) bool {
    var bi: ?*c.struct_bootinfo = null;
    c.machine_bootinfo(&bi);
    const info = bi orelse return false;
    var i: usize = 0;
    while (i < info.*.nr_rams) : (i += 1) {
        const ram = &info.*.ram[i];
        if (ram.*.type == c.MT_USABLE) {
            if (pa >= ram.*.base and pa < ram.*.base + ram.*.size) {
                return true;
            }
        }
    }
    return false;
}

pub export fn page_alloc(psize: c.psize_t) callconv(.c) c.paddr_t {
    c.sched_lock();
    _ = c.printf("page_alloc: psize=0x%x\n", psize);
    defer c.sched_unlock();

    const size = round_page(@as(usize, @intCast(psize)));
    var blk: ?*Page = page_head.next;

    while (blk != &page_head and blk != null) {
        if (blk.?.size >= size) break;
        blk = blk.?.next;
    }

    if (blk == &page_head or blk == null) {
        return 0;
    }

    const block = blk.?;

    if (block.*.size == size) {
        const prev = block.*.prev orelse &page_head;
        const next = block.*.next orelse &page_head;
        prev.*.next = next;
        next.*.prev = prev;
    } else {
        const tmp: *Page = @ptrFromInt(@intFromPtr(block) + size);
        tmp.*.size = block.*.size - size;
        tmp.*.prev = block.*.prev;
        tmp.*.next = block.*.next;
        const prev = block.*.prev orelse &page_head;
        const next = block.*.next orelse &page_head;
        prev.*.next = tmp;
        next.*.prev = tmp;
    }

    used_size += @as(c.psize_t, @intCast(size));
    const ret_val = kvtop(block);
    _ = c.printf("page_alloc: returning 0x%x\n", ret_val);
    return ret_val;
}

pub export fn page_free(paddr: c.paddr_t, psize: c.psize_t) callconv(.c) void {
    c.sched_lock();
    _ = c.printf("page_free: paddr=0x%x, size=0x%x\n", paddr, psize);
    defer c.sched_unlock();

    if (!page_is_ram(paddr)) {
        return;
    }

    const size = round_page(@as(usize, @intCast(psize)));
    const blk: *Page = @ptrCast(@alignCast(ptokv(paddr) orelse return));

    var prev: *Page = &page_head;
    while (prev.*.next != null and prev.*.next.? != &page_head) {
        const next = prev.*.next.?;
        if (@intFromPtr(next) >= @intFromPtr(blk)) break;
        prev = next;
    }

    blk.*.size = size;
    blk.*.prev = prev;
    blk.*.next = prev.*.next;
    const next_of_blk = blk.*.next orelse &page_head;
    next_of_blk.*.prev = blk;
    prev.*.next = blk;

    if (blk.*.next != null and blk.*.next.? != &page_head) {
        const nxt = blk.*.next.?;
        if (@intFromPtr(blk) + blk.*.size == @intFromPtr(nxt)) {
            blk.*.size += nxt.*.size;
            blk.*.next = nxt.*.next;
            const nn = nxt.*.next orelse &page_head;
            nn.*.prev = blk;
        }
    }

    if (blk.*.prev != null and blk.*.prev.? != &page_head) {
        const prv = blk.*.prev.?;
        if (@intFromPtr(prv) + prv.*.size == @intFromPtr(blk)) {
            prv.*.size += blk.*.size;
            prv.*.next = blk.*.next;
            const nn = blk.*.next orelse &page_head;
            nn.*.prev = prv;
        }
    }

    used_size = used_size -% @as(c.psize_t, @intCast(size));
    _ = c.printf("page_free: done, page_head.next=0x%x\n", @intFromPtr(page_head.next));
}

pub export fn page_reserve(paddr: c.paddr_t, psize: c.psize_t) callconv(.c) c_int {
    if (psize == 0) return 0;

    var pa = paddr;
    var sz = psize;
    const page_size = @as(c.paddr_t, @intCast(c.PAGE_SIZE));
    if (pa < page_size) {
        if (pa + sz <= page_size) return 0;
        sz -= (page_size - pa);
        pa = page_size;
    }

    const start = trunc_page(@as(usize, @intFromPtr(ptokv(pa) orelse return 0)));
    const end = round_page(@as(usize, @intFromPtr(ptokv(pa + sz) orelse return 0)));
    const size = end - start;

    var blk: ?*Page = page_head.next;
    while (blk != &page_head and blk != null) {
        const block = blk.?;
        if (@intFromPtr(block) <= start and end <= @intFromPtr(block) + block.size) {
            break;
        }
        blk = block.next;
    }

    if (blk == &page_head or blk == null) {
        return @intCast(c.ENOMEM);
    }

    const block = blk.?;

    if (@intFromPtr(block) == start and block.size == size) {
        const prev = block.prev orelse &page_head;
        const next = block.next orelse &page_head;
        prev.*.next = next;
        next.*.prev = prev;
    } else {
        if (@intFromPtr(block) + block.size != end) {
            const tmp: *Page = @ptrFromInt(end);
            tmp.size = @intFromPtr(block) + block.size - end;
            tmp.next = block.next;
            tmp.prev = block;

            block.size -= tmp.size;
            const nxt = block.next orelse &page_head;
            nxt.*.prev = tmp;
            block.next = tmp;
        }

        if (@intFromPtr(block) == start) {
            const prev = block.prev orelse &page_head;
            const next = block.next orelse &page_head;
            prev.*.next = next;
            next.*.prev = prev;
        } else {
            block.size = start - @intFromPtr(block);
        }
    }

    used_size += @as(c.psize_t, @intCast(size));
    return 0;
}

pub export fn page_info(info: *c.struct_meminfo) callconv(.c) void {
    info.*.total = total_size;
    info.*.free = total_size - used_size;
    info.*.bootdisk = bootdisk_size;
    if (!@hasDecl(c, "CONFIG_ROMBOOT")) {
        info.*.free -= bootdisk_size;
    }
}

pub export fn page_init() callconv(.c) void {
    var bi: ?*c.struct_bootinfo = null;
    c.machine_bootinfo(&bi);
    const info = bi orelse return;

    _ = c.printf("page_init: nr_rams=%d\n", info.*.nr_rams);
    var k: usize = 0;
    while (k < info.*.nr_rams) : (k += 1) {
        const ram = &info.*.ram[k];
        _ = c.printf("  ram[%d]: base=0x%x, size=0x%x, type=%d\n", @as(c_int, @intCast(k)), ram.*.base, ram.*.size, ram.*.type);
    }

    total_size = 0;
    bootdisk_size = 0;
    page_head.next = &page_head;
    page_head.prev = &page_head;

    var i: usize = 0;
    while (i < info.*.nr_rams) : (i += 1) {
        const ram = &info.*.ram[i];
        if (ram.*.type == c.MT_USABLE) {
            var base = ram.*.base;
            var size = ram.*.size;
            if (base == 0) {
                base += c.PAGE_SIZE;
                size -= c.PAGE_SIZE;
            }
            page_free(base, size);
            total_size += size;
        }
    }

    i = 0;
    while (i < info.*.nr_rams) : (i += 1) {
        const ram = &info.*.ram[i];
        const is_bootdisk = ram.*.type == c.MT_BOOTDISK;
        const is_memhole = ram.*.type == c.MT_MEMHOLE;
        const is_reserved = ram.*.type == c.MT_RESERVED;

        if (is_bootdisk or is_memhole or is_reserved) {
            if (is_bootdisk) {
                bootdisk_size += ram.*.size;
            }
            if (is_bootdisk or is_memhole) {
                total_size -= ram.*.size;
            }

            var overlap: bool = false;
            var j: usize = 0;
            while (j < info.*.nr_rams) : (j += 1) {
                if (info.*.ram[j].type == c.MT_USABLE) {
                    if (!(ram.*.base >= info.*.ram[j].base + info.*.ram[j].size or
                        ram.*.base + ram.*.size <= info.*.ram[j].base))
                    {
                        overlap = true;
                        break;
                    }
                }
            }
            if (overlap) {
                _ = page_reserve(ram.*.base, ram.*.size);
            }
        }
    }
    used_size = 0;
}
