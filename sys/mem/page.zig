const std = @import("std");
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    lib.panic("Zig panic");
    while (true) {}
}
const c = @import("c").c;

const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const kutil = ffi.kutil;
const lib = ffi.lib;
const sched = ffi.sched;

const debug_page = false;

inline fn dprintf(comptime fmt: [*:0]const u8, args: anytype) void {
    if (debug_page) {
        lib.printf(fmt, args);
    }
}

const Page = extern struct {
    next: ?*Page,
    prev: ?*Page,
    size: kern.Vsize,
};

var page_head = Page{
    .next = null,
    .prev = null,
    .size = 0,
};
var total_size: kern.Psize = 0;
var used_size: kern.Psize = 0;
var bootdisk_size: kern.Psize = 0;





fn page_is_ram(pa: kern.Paddr) bool {
    var bi: ?*hal.BootInfo = null;
    hal.machine_bootinfo(&bi);
    const binfo = bi orelse return false;
    var i: usize = 0;
    while (i < binfo.*.nr_rams) : (i += 1) {
        const ram = &binfo.*.ram[i];
        if (ram.*.type == c.MT_USABLE) {
            if (pa >= ram.*.base and pa < ram.*.base + ram.*.size) {
                return true;
            }
        }
    }
    return false;
}

pub fn alloc(psize: kern.Psize) callconv(.c) kern.Paddr {
    sched.lock();
    dprintf("page_alloc: psize=0x%x\n", .{psize});
    defer sched.unlock();

    const size = kutil.round_page(@as(usize, @intCast(psize)));
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

    used_size += @as(kern.Psize, @intCast(size));
    const ret_val = kutil.kvtop(block);
    dprintf("page_alloc: returning 0x%x\n", .{ret_val});
    return ret_val;
}

pub fn free(paddr: kern.Paddr, psize: kern.Psize) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    if (!page_is_ram(paddr)) {
        return;
    }

    const size = kutil.round_page(@as(usize, @intCast(psize)));
    dprintf("page_free: paddr=0x%x, size=0x%x\n", .{ paddr, size });
    const blk: *Page = @ptrCast(@alignCast(kutil.ptokv(paddr) orelse return));

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

    used_size = used_size -% @as(kern.Psize, @intCast(size));
    dprintf("page_free: done, page_head.next=0x%x\n", .{@intFromPtr(page_head.next)});
}

pub fn reserve(paddr: kern.Paddr, psize: kern.Psize) callconv(.c) c_int {
    if (psize == 0) return 0;

    var pa = paddr;
    var sz = psize;
    const page_size = @as(kern.Paddr, @intCast(c.PAGE_SIZE));
    if (pa < page_size) {
        if (pa + sz <= page_size) return 0;
        sz -= (page_size - pa);
        pa = page_size;
    }

    const start = kutil.trunc_page(@as(usize, @intFromPtr(kutil.ptokv(pa) orelse return 0)));
    const end = kutil.round_page(@as(usize, @intFromPtr(kutil.ptokv(pa + sz) orelse return 0)));
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

    used_size += @as(kern.Psize, @intCast(size));
    return 0;
}

pub fn info(mem_info: *hal.MemInfo) callconv(.c) void {
    mem_info.*.total = total_size;
    mem_info.*.free = total_size - used_size;
    mem_info.*.bootdisk = bootdisk_size;
    if (!@hasDecl(c, "CONFIG_ROMBOOT")) {
        mem_info.*.free -= bootdisk_size;
    }
}

pub fn init() callconv(.c) void {
    var bi: ?*hal.BootInfo = null;
    hal.machine_bootinfo(&bi);
    const binfo = bi orelse return;

    dprintf("page_init: nr_rams=%d\n", .{binfo.*.nr_rams});
    var k: usize = 0;
    while (k < binfo.*.nr_rams) : (k += 1) {
        const ram = &binfo.*.ram[k];
        dprintf("  ram[%d]: base=0x%x, size=0x%x, type=%d\n", .{ @as(c_int, @intCast(k)), ram.*.base, ram.*.size, ram.*.type });
    }

    total_size = 0;
    bootdisk_size = 0;
    page_head.next = &page_head;
    page_head.prev = &page_head;

    var i: usize = 0;
    while (i < binfo.*.nr_rams) : (i += 1) {
        const ram = &binfo.*.ram[i];
        if (ram.*.type == c.MT_USABLE) {
            var base = ram.*.base;
            var size = ram.*.size;
            if (base == 0) {
                base += c.PAGE_SIZE;
                size -= c.PAGE_SIZE;
            }
            free(base, size);
            total_size += size;
        }
    }

    i = 0;
    while (i < binfo.*.nr_rams) : (i += 1) {
        const ram = &binfo.*.ram[i];
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
            while (j < binfo.*.nr_rams) : (j += 1) {
                if (binfo.*.ram[j].type == c.MT_USABLE) {
                    if (!(ram.*.base >= binfo.*.ram[j].base + binfo.*.ram[j].size or
                        ram.*.base + ram.*.size <= binfo.*.ram[j].base))
                    {
                        overlap = true;
                        break;
                    }
                }
            }
            if (overlap) {
                _ = reserve(ram.*.base, ram.*.size);
            }
        }
    }
    used_size = 0;
}
comptime {
    if (@import("root") == @This()) {
        @export(&alloc, .{ .name = "page_alloc", .linkage = .strong });
        @export(&free, .{ .name = "page_free", .linkage = .strong });
        @export(&reserve, .{ .name = "page_reserve", .linkage = .strong });
        @export(&info, .{ .name = "page_info", .linkage = .strong });
        @export(&init, .{ .name = "page_init", .linkage = .strong });
    }
}
