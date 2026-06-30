// bsp/boot/common/jump_entry.c — Helper function to jump to the kernel entry point.
//
// In Zig 0.16, function pointer calls from integer values generate
// incorrect code on all architectures (both ARM Thumb and x86). The
// `@ptrCast(@as(EntryFn, @ptrFromInt(entry_ptr)))` pattern calls the
// source pointer instead of the function. This C helper function provides
// a correct indirect call to the kernel entry point.
//
// This file is compiled as C and linked with the Zig-compiled bootloader.

typedef void (*entry_fn_t)(void);

// Use unsigned long instead of uintptr_t to avoid needing stdint.h
// (the project uses -nostdinc, so stdint.h is not available).
void _jump_to_kernel(unsigned long entry_ptr) {
    entry_fn_t entry = (entry_fn_t)entry_ptr;
    entry();
}