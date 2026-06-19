#ifndef ZIG_HELPER_H
#define ZIG_HELPER_H

#include <conf/config.h>

struct event {
    struct queue {
        struct queue *next;
        struct queue *prev;
    } sleepq;
    const char *name;
};

/*
 * Dummy inline functions to replace C void macros (e.g. ((void)0)).
 * This resolves Zig's @cImport translation failures where void macros
 * are incorrectly translated to functions returning 'anyopaque'.
 */

#if !defined(DEBUG) || !defined(CONFIG_KD)

static inline void wrap_deadlock_init(void) {}
static inline void wrap_deadlock_check_spin(void *lock, uint32_t start_tick, uint32_t *iters) {
    (void)lock; (void)start_tick; (void)iters;
}
static inline void wrap_deadlock_record_lock(void *lock, int type) {
    (void)lock; (void)type;
}
static inline void wrap_deadlock_record_unlock(void *lock) {
    (void)lock;
}
static inline void wrap_deadlock_dump(void) {}
static inline void wrap_deadlock_check_loop(const char *func, uint32_t *iters) {
    (void)func; (void)iters;
}
static inline void wrap_deadlock_heartbeat(void) {}
static inline void wrap_deadlock_proactive_check(void) {}
static inline void wrap_deadlock_sleep(void *resource, const char *name) {
    (void)resource; (void)name;
}
static inline void wrap_deadlock_stop_sleep(void) {}
static inline void wrap_deadlock_mutex_wait(void *m, void *w) {
    (void)m; (void)w;
}
static inline void wrap_deadlock_mutex_stop_wait(void *w) {
    (void)w;
}

#undef deadlock_init
#undef deadlock_check_spin
#undef deadlock_check_loop
#undef deadlock_record_lock
#undef deadlock_record_unlock
#undef deadlock_dump
#undef deadlock_heartbeat
#undef deadlock_proactive_check
#undef deadlock_sleep
#undef deadlock_stop_sleep
#undef deadlock_mutex_wait
#undef deadlock_mutex_stop_wait

#define deadlock_init wrap_deadlock_init
#define deadlock_check_spin wrap_deadlock_check_spin
#define deadlock_check_loop wrap_deadlock_check_loop
#define deadlock_record_lock wrap_deadlock_record_lock
#define deadlock_record_unlock wrap_deadlock_record_unlock
#define deadlock_dump wrap_deadlock_dump
#define deadlock_heartbeat wrap_deadlock_heartbeat
#define deadlock_proactive_check wrap_deadlock_proactive_check
#define deadlock_sleep wrap_deadlock_sleep
#define deadlock_stop_sleep wrap_deadlock_stop_sleep
#define deadlock_mutex_wait wrap_deadlock_mutex_wait
#define deadlock_mutex_stop_wait wrap_deadlock_mutex_stop_wait

#endif /* !DEBUG || !CONFIG_KD */

#if !defined(CONFIG_SMP)

static inline void wrap_spinlock_lock(void *lock) {
    (void)lock;
}
static inline void wrap_spinlock_unlock(void *lock) {
    (void)lock;
}

#undef spinlock_lock
#undef spinlock_unlock

#define spinlock_lock wrap_spinlock_lock
#define spinlock_unlock wrap_spinlock_unlock

#endif /* !CONFIG_SMP */

/*
 * event_init macro replacement to avoid "do { } while (0)" translation error
 */
#undef event_init
static inline void wrap_event_init(void *event_ptr, const char *evt_name) {
    struct event *evt = (struct event *)event_ptr;
    evt->sleepq.next = &evt->sleepq;
    evt->sleepq.prev = &evt->sleepq;
    evt->name = evt_name;
}
#define event_init wrap_event_init

#endif /* ZIG_HELPER_H */
