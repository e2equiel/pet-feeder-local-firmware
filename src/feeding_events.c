#include <stdio.h>
#include <string.h>
#include "feeding_events.h"
#include "mcu_protocol.h"

struct scheduled_event { unsigned sequence; uint64_t observed_ms; struct pf_meal meal; };
static struct scheduled_event events[PF_EVENT_CAPACITY];
static unsigned sequence, count;
static char boot_id[33];

void pf_events_init(const char *identity) {
    memset(events, 0, sizeof(events)); sequence = count = 0;
    boot_id[0] = 0;
    if (!identity || strlen(identity) != 32 || strspn(identity, "0123456789abcdef") != 32) return;
    memcpy(boot_id, identity, 33);
}

int pf_events_observe(const unsigned char *frame, size_t length, uint64_t now_ms) {
    if (!boot_id[0] || length != 9 || frame[0] != 255 || frame[1] != 252 ||
        frame[2] != 7 || frame[3] != 5) return 0;
    struct pf_meal meal = {frame[4], frame[5], frame[6], frame[7], frame[8]};
    if (!pf_meal_valid(&meal) || !meal.enabled || sequence == 0xffffffffu) return 0;
    unsigned slot = sequence % PF_EVENT_CAPACITY;
    events[slot].sequence = ++sequence;
    events[slot].observed_ms = now_ms;
    events[slot].meal = meal;
    if (count < PF_EVENT_CAPACITY) count++;
    return 1;
}

int pf_events_json(char *out, size_t capacity, uint64_t now_ms) {
    if (!boot_id[0] || !capacity) return -1;
    int n = snprintf(out, capacity, "{\"boot_id\":\"%s\",\"sequence\":%u,\"events\":[", boot_id, sequence);
    if (n < 0 || (size_t)n >= capacity) return -1;
    size_t used = (size_t)n;
    unsigned written = 0;
    for (unsigned i = sequence - count; i < sequence; i++) {
        const struct scheduled_event *event = &events[i % PF_EVENT_CAPACITY];
        if (now_ms < event->observed_ms || now_ms - event->observed_ms > 600000) continue;
        const struct pf_meal *m = &event->meal;
        n = snprintf(out + used, capacity - used,
            "%s{\"sequence\":%u,\"age_ms\":%u,\"meal\":{\"weekdays\":%u,\"hour\":%u,\"minute\":%u,\"portions\":%u,\"enabled\":true}}",
            written ? "," : "", event->sequence, (unsigned)(now_ms-event->observed_ms),
            m->weekdays, m->hour, m->minute, m->portions);
        if (n < 0 || (size_t)n >= capacity - used) return -1;
        used += (size_t)n; written++;
    }
    n = snprintf(out + used, capacity - used, "]}");
    return n < 0 || (size_t)n >= capacity - used ? -1 : 0;
}
