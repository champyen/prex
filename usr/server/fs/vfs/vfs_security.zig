const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

const ACC_NG: c_int = -1;
const ACC_OK: c_int = 0;

const FSCap = struct {
    cap_read: c_int,
    cap_write: c_int,
    cap_exec: c_int,
};

fn matchBoot(path: [*c]const u8) bool {
    if (path[0] != '/') return false;
    if (path[1] != 'b') return false;
    if (path[2] != 'o') return false;
    if (path[3] != 'o') return false;
    if (path[4] != 't') return false;
    if (path[5] != '/') return false;
    return true;
}

fn matchBin(path: [*c]const u8) bool {
    if (path[0] != '/') return false;
    if (path[1] != 'b') return false;
    if (path[2] != 'i') return false;
    if (path[3] != 'n') return false;
    if (path[4] != '/') return false;
    return true;
}

fn matchEtc(path: [*c]const u8) bool {
    if (path[0] != '/') return false;
    if (path[1] != 'e') return false;
    if (path[2] != 't') return false;
    if (path[3] != 'c') return false;
    if (path[4] != '/') return false;
    return true;
}

fn matchUsr(path: [*c]const u8) bool {
    if (path[0] != '/') return false;
    if (path[1] != 'u') return false;
    if (path[2] != 's') return false;
    if (path[3] != 'r') return false;
    if (path[4] != '/') return false;
    return true;
}

fn lookupCap(path: [*c]const u8) ?FSCap {
    if (matchBoot(path)) {
        return FSCap{ .cap_read = c.CAP_SYSFILES, .cap_write = ACC_NG, .cap_exec = ACC_OK };
    }
    if (matchBin(path)) {
        return FSCap{ .cap_read = ACC_OK, .cap_write = c.CAP_SYSFILES, .cap_exec = ACC_OK };
    }
    if (matchEtc(path)) {
        return FSCap{ .cap_read = ACC_OK, .cap_write = c.CAP_SYSFILES, .cap_exec = ACC_NG };
    }
    if (matchUsr(path)) {
        return FSCap{ .cap_read = ACC_OK, .cap_write = ACC_OK, .cap_exec = ACC_OK };
    }
    return null;
}

fn capable(task: c.task_t, cap: c_int) bool {
    if (cap == ACC_OK) return true;
    if (cap == ACC_NG) return false;
    return c.task_chkcap(task, @intCast(cap)) == 0;
}

pub export fn sec_file_permission(task: c.task_t, path: [*c]const u8, acc: c_int) callconv(.c) c_int {
    if (acc == 0) return 0;

    if (lookupCap(path)) |map| {
        var error_val: c_int = 0;
        if (acc & c.VREAD != 0) {
            if (!capable(task, map.cap_read)) {
                error_val = ffi.prog.errno.EACCES;
            }
        }
        if (acc & c.VWRITE != 0) {
            if (!capable(task, map.cap_write)) {
                error_val = ffi.prog.errno.EACCES;
            }
        }
        return error_val;
    }
    return 0;
}

pub export fn sec_vnode_permission(path: [*c]const u8) callconv(.c) c_int {
    if (lookupCap(path)) |map| {
        if (map.cap_exec == ACC_OK) {
            return 0;
        }
    }
    return ffi.prog.errno.EACCES;
}
