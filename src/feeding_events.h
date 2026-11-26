#ifndef PF_FEEDING_EVENTS_H
#define PF_FEEDING_EVENTS_H
#include <stddef.h>
#include <stdint.h>
#define PF_EVENT_CAPACITY 16
void pf_events_init(const char *boot_id);
int pf_events_observe(const unsigned char *frame, size_t length, uint64_t now_ms);
int pf_events_json(char *out, size_t capacity, uint64_t now_ms);
#endif
