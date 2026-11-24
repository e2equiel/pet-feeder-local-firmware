#ifndef PF_MCU_PROTOCOL_H
#define PF_MCU_PROTOCOL_H
#include <stddef.h>
#include <stdint.h>

#define PF_MAX_MEALS 8
#define PF_MAX_PORTIONS 10
#define PF_MAX_SCHEDULE_FRAME (7 + 5 * PF_MAX_MEALS)

struct pf_meal {
    uint8_t weekdays; /* Sunday=bit0 through Saturday=bit6. */
    uint8_t hour;
    uint8_t minute;
    uint8_t portions;
    uint8_t enabled;
};

int pf_meal_valid(const struct pf_meal *meal);
int pf_encode_feed(unsigned portions, uint8_t out[14]);
int pf_encode_clock(const unsigned fields[6], uint8_t out[10]);
size_t pf_encode_schedule_query(uint8_t out[7]);
int pf_encode_schedule(const struct pf_meal *meals, size_t count,
                       uint8_t *out, size_t capacity, size_t *length);
int pf_decode_schedule(const uint8_t *payload, size_t length,
                       struct pf_meal out[PF_MAX_MEALS], size_t *count);
uint32_t pf_schedule_revision(const struct pf_meal *meals, size_t count);
#endif
