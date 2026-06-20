pub const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});
