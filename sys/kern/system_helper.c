#include <kernel.h>

const char* wrap_get_hostname(void) {
    return HOSTNAME;
}

const char* wrap_get_version(void) {
    return VERSION;
}

const char* wrap_get_machine(void) {
    return MACHINE;
}

const char* wrap_get_build_date(void) {
    return __DATE__;
}
